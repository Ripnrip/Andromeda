import AndromedaDomain
import AndromedaJournal
import CryptoKit
import Foundation

public actor MemoryRuntime {
    private static let operationalSinkID = "memory.operational.sqlite"
    private static let operationalSchemaVersion = "memory.operational.v1"

    private let journal: any EventJournal
    private let operationalStore: any MemoryOperationalStore
    private let classifier: DefaultMemoryClassifier
    private let routingPolicy: DefaultMemoryRoutingPolicy
    private let projectionSinks: [any MemoryProjectionSink]
    private let clock: any ClockProviding
    private let uuidProvider: any UUIDProviding

    public init(
        journal: any EventJournal,
        operationalStore: any MemoryOperationalStore,
        classifier: DefaultMemoryClassifier = .init(),
        routingPolicy: DefaultMemoryRoutingPolicy = .init(),
        projectionSinks: [any MemoryProjectionSink] = [],
        clock: any ClockProviding = LiveClock(),
        uuidProvider: any UUIDProviding = LiveUUIDProvider()
    ) {
        self.journal = journal
        self.operationalStore = operationalStore
        self.classifier = classifier
        self.routingPolicy = routingPolicy
        self.projectionSinks = projectionSinks
        self.clock = clock
        self.uuidProvider = uuidProvider
    }

    public func journalBacklogCount() async throws -> Int {
        try await journal.replay(after: nil).count
    }

    public func remember(_ intent: RememberIntent) async throws -> MemoryRememberResponse {
        if let existing = try await recordForIdempotencyKey(intent.idempotencyKey) {
            try await operationalStore.upsert(existing)
            return response(for: existing, sinkReceipts: [
                MemoryWriteReceipt(
                    memoryID: existing.memoryID,
                    sinkID: Self.operationalSinkID,
                    schemaVersion: Self.operationalSchemaVersion,
                    checksum: existing.checksum,
                    status: .skipped,
                    verification: .verified
                ),
            ], warnings: ["Idempotency key reused existing canonical memory."])
        }

        let classification = try classifier.classify(intent)
        let memoryID = MemoryID(rawValue: await uuidProvider.makeUUID())
        let eventID = EventID(rawValue: await uuidProvider.makeUUID())
        let correlationID = await uuidProvider.makeUUID()
        let occurredAt = await clock.now()
        let checksum = Self.checksum(
            content: intent.content,
            kind: intent.kind,
            privacyLevel: intent.privacyLevel,
            tags: classification.tags,
            metadata: classification.metadata
        )
        let record = MemoryRecord(
            memoryID: memoryID,
            eventID: eventID,
            correlationID: correlationID,
            scope: intent.scope,
            source: intent.source,
            kind: intent.kind,
            privacyLevel: intent.privacyLevel,
            summary: classification.summary,
            content: intent.content.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: classification.tags,
            metadata: classification.metadata,
            relatedContext: intent.relatedContext,
            checksum: checksum,
            createdAt: occurredAt
        )

        let envelope: EventEnvelope<CanonicalEventPayload> = EventEnvelope(
            id: eventID,
            correlationID: correlationID,
            occurredAt: occurredAt,
            source: EventSource(
                subsystem: intent.source.subsystem,
                actor: intent.source.actor,
                scope: intent.scope
            ),
            payload: CanonicalEventPayload.memoryRemembered(record.canonicalPayload)
        )

        do {
            _ = try await journal.append(envelope, idempotencyKey: intent.idempotencyKey)
        } catch AndromedaRuntimeError.duplicateIdempotencyConflict {
            guard let existing = try await recordForIdempotencyKey(intent.idempotencyKey) else {
                throw AndromedaRuntimeError.invalidRuntimeRequest(
                    "Canonical memory exists for idempotency key \(intent.idempotencyKey.rawValue) but could not be reloaded."
                )
            }
            try await operationalStore.upsert(existing)
            return response(for: existing, sinkReceipts: [
                MemoryWriteReceipt(
                    memoryID: existing.memoryID,
                    sinkID: Self.operationalSinkID,
                    schemaVersion: Self.operationalSchemaVersion,
                    checksum: existing.checksum,
                    status: .skipped,
                    verification: .verified
                ),
            ], warnings: ["Idempotency key reused existing canonical memory."])
        }

        var warnings = classification.warnings
        var sinkReceipts: [MemoryWriteReceipt] = []

        do {
            try await operationalStore.upsert(record)
            sinkReceipts.append(
                MemoryWriteReceipt(
                    memoryID: record.memoryID,
                    sinkID: Self.operationalSinkID,
                    schemaVersion: Self.operationalSchemaVersion,
                    checksum: record.checksum,
                    status: .committed,
                    verification: .verified
                )
            )
        } catch {
            warnings.append("Operational store update failed: \(error.localizedDescription)")
            sinkReceipts.append(
                MemoryWriteReceipt(
                    memoryID: record.memoryID,
                    sinkID: Self.operationalSinkID,
                    schemaVersion: Self.operationalSchemaVersion,
                    checksum: record.checksum,
                    status: .retryableFailure,
                    verification: .failed
                )
            )
        }

        for sink in routingPolicy.sinks(for: record, availableSinks: projectionSinks) {
            do {
                sinkReceipts.append(try await sink.write(record: record))
            } catch {
                warnings.append("Projection sink \(sink.sinkID) failed: \(error.localizedDescription)")
                sinkReceipts.append(
                    MemoryWriteReceipt(
                        memoryID: record.memoryID,
                        sinkID: sink.sinkID,
                        schemaVersion: sink.schemaVersion,
                        checksum: record.checksum,
                        status: .retryableFailure,
                        verification: .failed
                    )
                )
            }
        }

        return response(for: record, sinkReceipts: sinkReceipts, warnings: warnings)
    }

    public func recall(_ request: RecallRequest) async throws -> MemoryRecallResponse {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AndromedaRuntimeError.invalidRecallQuery("Recall query must not be empty.")
        }
        guard request.resultLimit > 0 else {
            throw AndromedaRuntimeError.invalidRecallQuery("Recall result limit must be greater than zero.")
        }

        let allRecords = try await operationalStore.fetchAll()
        let now = await clock.now()
        let filtered = allRecords.filter { record in
            self.scopeMatches(record.scope, requested: request.scope)
                && self.privacyAllows(record, requestedScope: request.scope, ceiling: request.privacyCeiling)
                && (request.kinds.isEmpty || request.kinds.contains(record.kind))
                && self.matchesRecency(record, recencyWindowDays: request.recencyWindowDays, now: now)
        }

        let ranked = filtered
            .map { record in
                MemoryRecallHit(
                    record: record,
                    score: Self.score(record: record, query: query, now: now),
                    provenance: MemoryProvenance(
                        eventID: record.eventID,
                        correlationID: record.correlationID,
                        checksum: record.checksum
                    )
                )
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.record.createdAt > $1.record.createdAt
                }
                return $0.score > $1.score
            }

        let hits = Array(ranked.prefix(request.resultLimit))
        let synthesizedContext = hits.isEmpty
            ? "No matching memory records were found for the requested scope."
            : hits.enumerated()
                .map { index, hit in
                    "\(index + 1). [\(hit.record.kind.rawValue)] \(hit.record.summary)"
                }
                .joined(separator: "\n")
        return MemoryRecallResponse(synthesizedContext: synthesizedContext, records: hits, warnings: [])
    }

    public func rebuildOperationalStoreFromJournal() async throws -> Int {
        try await operationalStore.reset()
        let events = try await journal.replay(after: nil)
        var restored = 0
        for event in events {
            guard case .memoryRemembered(let payload) = event.envelope.payload else {
                continue
            }
            try await operationalStore.upsert(payload.record(eventID: event.envelope.id, correlationID: event.envelope.correlationID))
            restored += 1
        }
        return restored
    }

    private func response(
        for record: MemoryRecord,
        sinkReceipts: [MemoryWriteReceipt],
        warnings: [String]
    ) -> MemoryRememberResponse {
        MemoryRememberResponse(
            memoryID: record.memoryID,
            eventID: record.eventID,
            correlationID: record.correlationID,
            sinkReceipts: sinkReceipts,
            verificationStatus: Self.aggregateVerificationStatus(from: sinkReceipts),
            warnings: warnings,
            retryStatus: sinkReceipts.contains(where: { $0.status == .retryableFailure }) ? .pending : .none
        )
    }

    private func recordForIdempotencyKey(_ key: IdempotencyKey) async throws -> MemoryRecord? {
        let events = try await journal.replay(after: nil)
        guard let persisted = events.first(where: { $0.idempotencyKey == key }) else {
            return nil
        }
        guard case .memoryRemembered(let payload) = persisted.envelope.payload else {
            return nil
        }
        return payload.record(
            eventID: persisted.envelope.id,
            correlationID: persisted.envelope.correlationID
        )
    }

    private func scopeMatches(_ recordScope: EventScope, requested: EventScope) -> Bool {
        if let projectID = requested.projectID, recordScope.projectID != projectID { return false }
        if let memoryID = requested.memoryID, recordScope.memoryID != memoryID { return false }
        if let repositoryID = requested.repositoryID, recordScope.repositoryID != repositoryID { return false }
        if let sessionID = requested.sessionID, recordScope.sessionID != sessionID { return false }
        if let checkpointID = requested.checkpointID, recordScope.checkpointID != checkpointID { return false }
        if let leaseID = requested.leaseID, recordScope.leaseID != leaseID { return false }
        if let environmentID = requested.environmentID, recordScope.environmentID != environmentID { return false }
        if let userID = requested.userID, recordScope.userID != userID { return false }
        if let teamID = requested.teamID, recordScope.teamID != teamID { return false }
        if let organizationID = requested.organizationID, recordScope.organizationID != organizationID { return false }
        return true
    }

    private func privacyAllows(
        _ record: MemoryRecord,
        requestedScope: EventScope,
        ceiling: PrivacyLevel
    ) -> Bool {
        guard record.privacyLevel <= ceiling else { return false }

        switch record.privacyLevel {
        case .public:
            return true
        case .project:
            if let recordProjectID = record.scope.projectID {
                return requestedScope.projectID == recordProjectID
            }
            return false
        case .private:
            if let sessionID = record.scope.sessionID, requestedScope.sessionID == sessionID {
                return true
            }
            if let userID = record.scope.userID, requestedScope.userID == userID {
                return true
            }
            return false
        }
    }

    private func matchesRecency(_ record: MemoryRecord, recencyWindowDays: Int?, now: Date) -> Bool {
        guard let recencyWindowDays else { return true }
        let cutoff = record.createdAt.addingTimeInterval(TimeInterval(recencyWindowDays * 86_400))
        return cutoff >= now
    }

    private static func aggregateVerificationStatus(from receipts: [MemoryWriteReceipt]) -> VerificationStatus {
        if receipts.contains(where: { $0.verification == .failed }) {
            return .failed
        }
        if receipts.contains(where: { $0.verification == .pending }) {
            return .pending
        }
        if receipts.allSatisfy({ $0.verification == .unsupported }) {
            return .unsupported
        }
        return .verified
    }

    private static func checksum(
        content: String,
        kind: MemoryKind,
        privacyLevel: PrivacyLevel,
        tags: [String],
        metadata: [String: String]
    ) -> String {
        let material = [
            content,
            kind.rawValue,
            privacyLevel.rawValue,
            tags.joined(separator: ","),
            metadata.keys.sorted().map { "\($0)=\(metadata[$0] ?? "")" }.joined(separator: ","),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func score(record: MemoryRecord, query: String, now: Date) -> Double {
        let queryTerms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
        let haystack = [
            record.summary.lowercased(),
            record.content.lowercased(),
            record.tags.joined(separator: " ").lowercased(),
        ].joined(separator: " ")
        let matchCount = queryTerms.reduce(into: 0) { result, term in
            if haystack.contains(term) {
                result += 1
            }
        }
        let ageDays = max(0, now.timeIntervalSince(record.createdAt) / 86_400)
        let recencyBonus = 1.0 / (1.0 + ageDays)
        return Double(matchCount) * 10.0 + recencyBonus
    }
}

extension MemoryRecord {
    var canonicalPayload: MemoryRememberedPayload {
        MemoryRememberedPayload(
            memoryID: memoryID,
            scope: scope,
            sourceSubsystem: source.subsystem,
            sourceActor: source.actor,
            sourceLabel: source.label,
            kind: kind.rawValue,
            privacyLevel: privacyLevel.rawValue,
            summary: summary,
            content: content,
            tags: tags,
            metadata: metadata,
            relatedContext: relatedContext,
            checksum: checksum,
            createdAt: createdAt
        )
    }
}

extension MemoryRememberedPayload {
    fileprivate func record(eventID: EventID, correlationID: UUID) -> MemoryRecord {
        MemoryRecord(
            memoryID: memoryID,
            eventID: eventID,
            correlationID: correlationID,
            scope: scope,
            source: MemorySource(
                subsystem: sourceSubsystem,
                actor: sourceActor,
                label: sourceLabel
            ),
            kind: MemoryKind(rawValue: kind) ?? .note,
            privacyLevel: PrivacyLevel(rawValue: privacyLevel) ?? .project,
            summary: summary,
            content: content,
            tags: tags,
            metadata: metadata,
            relatedContext: relatedContext,
            checksum: checksum,
            createdAt: createdAt
        )
    }
}
