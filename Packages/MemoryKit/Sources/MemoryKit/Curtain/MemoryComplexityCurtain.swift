/**
 * MemoryComplexityCurtain — Andromida complexity curtain facade (BIN-246–251).
 *
 * Agents call retain / recall / forget / health. JSON outbox is write authority.
 * Live projection is fail-open. Retrieval is planned + fused. Drift is visible.
 */

import Foundation

public struct RetainReceipt: Sendable, Equatable {
    public let memoryID: UUID
    public let contentHash: String
    public let deliveryState: OutboxDeliveryState
    public let writeKind: CurtainWriteKind
    public let warnings: [String]

    public init(
        memoryID: UUID,
        contentHash: String,
        deliveryState: OutboxDeliveryState,
        writeKind: CurtainWriteKind,
        warnings: [String]
    ) {
        self.memoryID = memoryID
        self.contentHash = contentHash
        self.deliveryState = deliveryState
        self.writeKind = writeKind
        self.warnings = warnings
    }
}

public struct ForgetReceipt: Sendable, Equatable {
    public let tombstoneID: UUID
    public let targetMemoryID: UUID
    public let warnings: [String]

    public init(tombstoneID: UUID, targetMemoryID: UUID, warnings: [String]) {
        self.tombstoneID = tombstoneID
        self.targetMemoryID = targetMemoryID
        self.warnings = warnings
    }
}

public struct RecallResponse: Sendable, Equatable {
    public let intent: RecallQueryIntent
    public let plan: RecallPlan
    public let hits: [FusedRecallHit]
    public let warnings: [String]

    public init(intent: RecallQueryIntent, plan: RecallPlan, hits: [FusedRecallHit], warnings: [String]) {
        self.intent = intent
        self.plan = plan
        self.hits = hits
        self.warnings = warnings
    }
}

public enum CurtainHealthLevel: String, Sendable, Codable, Equatable {
    case green
    case yellow
    case red
}

public struct OutboxDriftReport: Sendable, Equatable {
    public let authorityCounts: [OutboxDeliveryState: Int]
    public let projectionCounts: [OutboxDeliveryState: Int]
    public let missingInProjection: Int
    public let extraInProjection: Int
    public let drifted: Bool

    public init(
        authorityCounts: [OutboxDeliveryState: Int],
        projectionCounts: [OutboxDeliveryState: Int],
        missingInProjection: Int,
        extraInProjection: Int,
        drifted: Bool
    ) {
        self.authorityCounts = authorityCounts
        self.projectionCounts = projectionCounts
        self.missingInProjection = missingInProjection
        self.extraInProjection = extraInProjection
        self.drifted = drifted
    }
}

public struct CurtainHealthReport: Sendable, Equatable {
    public let level: CurtainHealthLevel
    public let outboxCounts: [OutboxDeliveryState: Int]
    public let projectionID: String
    public let projectionFailure: String?
    public let drift: OutboxDriftReport
    public let notes: [String]

    public init(
        level: CurtainHealthLevel,
        outboxCounts: [OutboxDeliveryState: Int],
        projectionID: String,
        projectionFailure: String?,
        drift: OutboxDriftReport,
        notes: [String]
    ) {
        self.level = level
        self.outboxCounts = outboxCounts
        self.projectionID = projectionID
        self.projectionFailure = projectionFailure
        self.drift = drift
        self.notes = notes
    }
}

/// Optional hot-working recall adapter (e.g. SwiftData) — fail-open when nil.
public protocol HotWorkingRecallSource: Sendable {
    func search(query: String, limit: Int) async -> [RawRecallHit]
}

/// Optional long-doc / graph / synthesis adapters — fail-open stubs by default.
public protocol CurtainRecallAdapter: Sendable {
    var route: RecallBackendRoute { get }
    func search(query: String, limit: Int) async -> [RawRecallHit]
}

/// Main Andromida curtain actor.
public actor MemoryComplexityCurtain {
    private let outbox: JSONOutboxAuthority
    private let projection: any OutboxLiveProjection
    private let planner: RecallPlanner
    private let hotWorking: (any HotWorkingRecallSource)?
    private let adapters: [any CurtainRecallAdapter]

    public init(
        outbox: JSONOutboxAuthority,
        projection: any OutboxLiveProjection = RealmOutboxLiveProjection(),
        planner: RecallPlanner = RecallPlanner(),
        hotWorking: (any HotWorkingRecallSource)? = nil,
        adapters: [any CurtainRecallAdapter] = []
    ) {
        self.outbox = outbox
        self.projection = projection
        self.planner = planner
        self.hotWorking = hotWorking
        self.adapters = adapters
    }

    /// Convenience constructor with a temporary on-disk outbox.
    public static func makeEphemeral() async throws -> MemoryComplexityCurtain {
        let outbox = try JSONOutboxAuthority.makeTemporary()
        let curtain = MemoryComplexityCurtain(outbox: outbox)
        // Rebuild projection from any pre-existing seeds (none for temp).
        await curtain.rebuildProjectionFromAuthority()
        return curtain
    }

    // MARK: - Verbs

    /// `memory_retain` — durable acceptance via JSON outbox; projection fail-open.
    public func retain(
        narrative: String,
        project: String,
        agent: String,
        provenance: String = "memory_retain",
        visibility: String = "private",
        tags: [String] = [],
        capabilityAlias: String? = nil,
        id: UUID = UUID()
    ) async throws -> RetainReceipt {
        let writeKind = CurtainWriteKindResolver.resolve(capabilityAlias: capabilityAlias)
        var warnings: [String] = []
        if let alias = capabilityAlias?.lowercased(),
           case .compatibilityShim(_, let shimAlias, let hotPath)? = MemoryVerbSurface.resolve(alias)
        {
            if !hotPath {
                warnings.append("Alias \(shimAlias) is off the agent hot path; routed as retain/\(writeKind.rawValue).")
            } else if shimAlias != MemoryVerb.retain.rawValue {
                warnings.append("Compatibility shim \(shimAlias) → memory_retain.")
            }
        }
        if writeKind == .inferAliasDeprecated {
            warnings.append("infer.write is deprecated; mapped to episodic retain.")
        }

        let record = try await outbox.retain(
            narrative: narrative,
            project: project,
            agent: agent,
            provenance: provenance,
            visibility: visibility,
            tags: tags,
            writeKind: writeKind,
            id: id
        )

        // Fail-open: projection errors never undo retain authority.
        await projection.mirror(record)
        if let failure = await projection.lastFailureMessage {
            warnings.append("Live projection fail-open: \(failure)")
        }

        return RetainReceipt(
            memoryID: record.id,
            contentHash: record.contentHash,
            deliveryState: record.deliveryState,
            writeKind: record.writeKind,
            warnings: warnings
        )
    }

    /// `memory_forget` — durable tombstone; suppresses future fused recall.
    public func forget(
        targetMemoryID: UUID,
        reason: String = "",
        agent: String = "agent",
        project: String = "default"
    ) async throws -> ForgetReceipt {
        let record = try await outbox.forget(
            targetMemoryID: targetMemoryID,
            reason: reason,
            agent: agent,
            project: project
        )
        var warnings: [String] = []
        await projection.mirror(record)
        if let failure = await projection.lastFailureMessage {
            warnings.append("Live projection fail-open: \(failure)")
        }
        // Mark tombstone delivered to authority state machine (local accept).
        try await outbox.mark(record.id, state: .delivered)
        await projection.mirror(
            OutboxRecord(
                id: record.id,
                contentHash: record.contentHash,
                narrative: record.narrative,
                project: record.project,
                agent: record.agent,
                provenance: record.provenance,
                visibility: record.visibility,
                tags: record.tags,
                writeKind: record.writeKind,
                createdAt: record.createdAt,
                deliveryState: .delivered,
                targetMemoryID: record.targetMemoryID,
                isTombstone: true
            )
        )
        return ForgetReceipt(tombstoneID: record.id, targetMemoryID: targetMemoryID, warnings: warnings)
    }

    /// `memory_recall` — intent plan → multi-route search → RRF → tombstone filter.
    public func recall(
        query: String,
        intentHint: RecallQueryIntent = .auto,
        limit: Int = 10
    ) async -> RecallResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings: [String] = []
        guard !trimmed.isEmpty else {
            return RecallResponse(
                intent: .exact,
                plan: RecallPlan(intent: .exact, steps: []),
                hits: [],
                warnings: ["Empty recall query."]
            )
        }

        let intent = planner.classify(query: trimmed, hint: intentHint)
        let plan = planner.plan(for: intent)
        let tombstones = await outbox.tombstoneIDs()

        var lists: [[RawRecallHit]] = []
        for step in plan.steps {
            let hits = await search(route: step.route, query: trimmed, limit: limit)
            if hits.isEmpty {
                warnings.append("Route \(step.route.rawValue) returned no hits (\(step.reason)).")
            }
            lists.append(hits)
        }

        let fused = RankFusion.fuse(lists: lists, tombstones: tombstones, limit: limit)
        return RecallResponse(intent: intent, plan: plan, hits: fused, warnings: warnings)
    }

    /// `memory_health` — outbox + projection + drift.
    public func health() async -> CurtainHealthReport {
        let authorityCounts = await outbox.countsByState()
        let projectionCounts = await projection.countsByState()
        let authorityIDs = Set(await outbox.allRecords().map(\.id))
        let projectionIDs = Set(await projection.snapshot().map(\.id))
        let missing = authorityIDs.subtracting(projectionIDs).count
        let extra = projectionIDs.subtracting(authorityIDs).count
        let drift = OutboxDriftReport(
            authorityCounts: authorityCounts,
            projectionCounts: projectionCounts,
            missingInProjection: missing,
            extraInProjection: extra,
            drifted: missing > 0 || extra > 0
        )

        var notes: [String] = []
        let projectionFailure = await projection.lastFailureMessage
        if let projectionFailure {
            notes.append("Projection fail-open: \(projectionFailure)")
        }
        if drift.drifted {
            notes.append("Drift detected between JSON authority and live projection.")
        }
        let dead = authorityCounts[.deadLetter, default: 0]
        if dead > 0 {
            notes.append("\(dead) dead-letter outbox row(s) need replay.")
        }

        let level: CurtainHealthLevel
        if dead > 0 || (drift.drifted && missing > 5) {
            level = .red
        } else if drift.drifted || projectionFailure != nil || authorityCounts[.pending, default: 0] > 20 {
            level = .yellow
        } else {
            level = .green
        }

        return CurtainHealthReport(
            level: level,
            outboxCounts: authorityCounts,
            projectionID: projection.projectionID,
            projectionFailure: projectionFailure,
            drift: drift,
            notes: notes
        )
    }

    // MARK: - Operator flows (BIN-251)

    /// Rebuild live projection entirely from JSON seeds.
    public func rebuildProjectionFromAuthority() async {
        let records = await outbox.allRecords()
        await projection.rebuild(from: records)
    }

    /// Replay pending/dead-letter rows through a delivery handler, then update states.
    public func replayPending(
        deliver: @Sendable (OutboxRecord) async throws -> Void
    ) async -> (delivered: Int, deadLetter: Int) {
        let pending = await outbox.pendingForReplay()
        var delivered = 0
        var dead = 0
        for record in pending {
            do {
                try await deliver(record)
                try await outbox.mark(record.id, state: .delivered)
                if let refreshed = await outbox.allRecords().first(where: { $0.id == record.id }) {
                    await projection.mirror(refreshed)
                }
                delivered += 1
            } catch {
                try? await outbox.mark(record.id, state: .deadLetter, error: error.localizedDescription)
                if var refreshed = await outbox.allRecords().first(where: { $0.id == record.id }) {
                    refreshed.deliveryState = .deadLetter
                    refreshed.lastError = error.localizedDescription
                    await projection.mirror(refreshed)
                }
                dead += 1
            }
        }
        return (delivered, dead)
    }

    /// Companion / operator queue insights (no store brands).
    public func outboxQueueInsights() async -> CompanionOutboxInsights {
        let counts = await outbox.countsByState()
        let rows = await projection.snapshot()
        let health = await health()
        return CompanionOutboxInsights(
            pending: counts[.pending, default: 0],
            delivered: counts[.delivered, default: 0],
            deadLetter: counts[.deadLetter, default: 0],
            healthLevel: health.level,
            driftDetected: health.drift.drifted,
            recentRows: Array(rows.suffix(20).reversed())
        )
    }

    // MARK: - Private search

    private func search(route: RecallBackendRoute, query: String, limit: Int) async -> [RawRecallHit] {
        switch route {
        case .durableOutbox:
            let records = await outbox.allRecords().filter { !$0.isTombstone }
            return records.compactMap { record in
                let score = CurtainLexicalScorer.score(
                    query: query,
                    haystack: [record.narrative, record.tags.joined(separator: " "), record.project].joined(separator: " ")
                )
                guard score > 0 else { return nil }
                return RawRecallHit(
                    id: record.id,
                    title: String(record.narrative.prefix(80)),
                    body: record.narrative,
                    route: .durableOutbox,
                    score: score,
                    createdAt: record.createdAt
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }

        case .hotWorking:
            if let hotWorking {
                return await hotWorking.search(query: query, limit: limit)
            }
            // Degrade: reuse durable outbox as working set when no hot adapter is wired.
            return await search(route: .durableOutbox, query: query, limit: limit)

        case .longDocumentIndex, .codeGraph, .synthesis:
            if let adapter = adapters.first(where: { $0.route == route }) {
                return await adapter.search(query: query, limit: limit)
            }
            // Fail-open stub: no adapter → empty list (planner still records the route).
            return []
        }
    }
}

/// Companion-facing outbox queue summary (BIN-252).
public struct CompanionOutboxInsights: Sendable, Equatable {
    public let pending: Int
    public let delivered: Int
    public let deadLetter: Int
    public let healthLevel: CurtainHealthLevel
    public let driftDetected: Bool
    public let recentRows: [OutboxProjectionRow]

    public init(
        pending: Int,
        delivered: Int,
        deadLetter: Int,
        healthLevel: CurtainHealthLevel,
        driftDetected: Bool,
        recentRows: [OutboxProjectionRow]
    ) {
        self.pending = pending
        self.delivered = delivered
        self.deadLetter = deadLetter
        self.healthLevel = healthLevel
        self.driftDetected = driftDetected
        self.recentRows = recentRows
    }
}
