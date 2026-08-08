import AndromedaDomain
import AndromedaJournal
import AndromedaMemory
import Foundation
import Testing

@Suite("AndromedaMemory.MemoryRuntime")
struct MemoryRuntimeTests {
    @Test("classifier normalizes tags and derives a summary")
    func classifierNormalizesInput() throws {
        let classifier = DefaultMemoryClassifier()
        let classification = try classifier.classify(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "unit"),
                content: "Decision: keep the canonical journal append-first.\nThe projection stays rebuildable.",
                kind: .decision,
                privacyLevel: .project,
                tags: [" Runtime ", "runtime", "Journal"],
                metadata: [" owner ": " andromeda "],
                idempotencyKey: "classify-1"
            )
        )

        #expect(classification.summary == "Decision: keep the canonical journal append-first.")
        #expect(classification.tags == ["journal", "runtime"])
        #expect(classification.metadata == ["owner": "andromeda"])
    }

    @Test("routing policy includes only accepting sinks")
    func routingPolicyFiltersSinks() {
        let policy = DefaultMemoryRoutingPolicy()
        let record = makeRecord(kind: .decision, privacy: .project)
        let accepting = RecordingSink(sinkID: "sink.accept", acceptsPrivate: true, shouldFail: false)
        let rejecting = RecordingSink(sinkID: "sink.reject", acceptsPrivate: false, shouldFail: false, allowedKinds: [.workflow])

        let selected = policy.sinks(for: record, availableSinks: [accepting, rejecting]).map(\.sinkID)

        #expect(selected == ["sink.accept"])
    }

    @Test("private memories do not cross unauthorized scopes")
    func privacyFilteringRespectsUnauthorizedScopes() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "private"),
                content: "Sensitive session-only note.",
                kind: .note,
                privacyLevel: .private,
                idempotencyKey: "private-1"
            )
        )
        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: otherSessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "project"),
                content: "Project-level discovery.",
                kind: .discovery,
                privacyLevel: .project,
                idempotencyKey: "project-1"
            )
        )

        let projectOnly = try await runtime.recall(
            RecallRequest(
                query: "note discovery",
                scope: EventScope(projectID: projectID),
                privacyCeiling: .private,
                resultLimit: 10
            )
        )
        #expect(projectOnly.records.count == 1)
        #expect(projectOnly.records.first?.record.privacyLevel == .project)

        let authorizedSession = try await runtime.recall(
            RecallRequest(
                query: "sensitive",
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                privacyCeiling: .private,
                resultLimit: 10
            )
        )
        #expect(authorizedSession.records.count == 1)
        #expect(authorizedSession.records.first?.record.privacyLevel == .private)
    }

    @Test("duplicate remembers reuse a single canonical event")
    func rememberIdempotency() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        let intent = RememberIntent(
            scope: EventScope(projectID: projectID, sessionID: sessionID),
            source: MemorySource(subsystem: "tests", actor: "memory", label: "idempotent"),
            content: "Use JSONL as the canonical journal.",
            kind: .decision,
            privacyLevel: .project,
            idempotencyKey: "remember-same"
        )

        let first = try await runtime.remember(intent)
        let second = try await runtime.remember(intent)
        let replay = try await context.journal.replay(after: nil)
        let stored = try await context.store.fetchAll()

        #expect(first.memoryID == second.memoryID)
        #expect(first.eventID == second.eventID)
        #expect(replay.count == 1)
        #expect(stored.count == 1)
    }

    @Test("idempotent remember rejects a conflicting intent for the same key")
    func rememberIdempotencyRejectsConflictingIntent() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "idempotent"),
                content: "Use JSONL as the canonical journal.",
                kind: .decision,
                privacyLevel: .project,
                idempotencyKey: "remember-conflict"
            )
        )

        await #expect(throws: AndromedaRuntimeError.self) {
            _ = try await runtime.remember(
                RememberIntent(
                    scope: EventScope(projectID: projectID, sessionID: sessionID),
                    source: MemorySource(subsystem: "tests", actor: "memory", label: "idempotent"),
                    content: "A different canonical journal decision.",
                    kind: .decision,
                    privacyLevel: .project,
                    idempotencyKey: "remember-conflict"
                )
            )
        }
    }

    @Test("partial sink failure does not roll back the canonical commit")
    func partialSinkFailureKeepsCanonicalCommit() async throws {
        let context = try TestContext()
        let successSink = RecordingSink(sinkID: "sink.ok", acceptsPrivate: true, shouldFail: false)
        let failureSink = RecordingSink(sinkID: "sink.fail", acceptsPrivate: true, shouldFail: true)
        let runtime = try makeRuntime(context: context, sinks: [successSink, failureSink])

        let response = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "fanout"),
                content: "Projection fan-out can fail independently.",
                kind: .workflow,
                privacyLevel: .project,
                idempotencyKey: "fanout-1"
            )
        )

        let replay = try await context.journal.replay(after: nil)
        let stored = try await context.store.fetchAll()

        #expect(replay.count == 1)
        #expect(stored.count == 1)
        #expect(response.retryStatus == .pending)
        #expect(response.sinkReceipts.contains(where: { $0.sinkID == "sink.fail" && $0.status == .retryableFailure }))
        #expect(response.sinkReceipts.contains(where: { $0.sinkID == "sink.ok" && $0.status == .committed }))
    }

    @Test("concurrent remembers keep journal and operational state consistent")
    func concurrentRemembersStayConsistent() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try await runtime.remember(
                        RememberIntent(
                            scope: EventScope(projectID: projectID, sessionID: sessionID),
                            source: MemorySource(subsystem: "tests", actor: "memory", label: "concurrency"),
                            content: "Concurrent memory \(index)",
                            kind: .note,
                            privacyLevel: .project,
                            idempotencyKey: IdempotencyKey(rawValue: "concurrency-\(index)")
                        )
                    )
                }
            }
            try await group.waitForAll()
        }

        let replay = try await context.journal.replay(after: nil)
        let stored = try await context.store.fetchAll()

        #expect(replay.count == 20)
        #expect(stored.count == 20)
        #expect(Set(stored.map(\.memoryID)).count == 20)
    }

    @Test("operational state rebuild from journal replay matches original state")
    func rebuildMatchesOriginalState() async throws {
        let original = try TestContext()
        let runtime = try makeRuntime(context: original)

        for index in 0..<3 {
            _ = try await runtime.remember(
                RememberIntent(
                    scope: EventScope(projectID: projectID, sessionID: sessionID),
                    source: MemorySource(subsystem: "tests", actor: "memory", label: "rebuild"),
                    content: "Rebuild memory \(index)",
                    kind: index == 0 ? .decision : .note,
                    privacyLevel: .project,
                    idempotencyKey: IdempotencyKey(rawValue: "rebuild-\(index)")
                )
            )
        }

        let expected = try await original.store.fetchAll()
            .sorted { $0.memoryID.description < $1.memoryID.description }

        let rebuiltStoreURL = original.directory.appending(path: "rebuilt.sqlite3")
        let rebuiltStore = try SQLiteMemoryOperationalStore(databaseURL: rebuiltStoreURL)
        let rebuiltRuntime = MemoryRuntime(
            journal: original.journal,
            operationalStore: rebuiltStore,
            clock: FixedClock(date: fixedDate),
            uuidProvider: DeterministicUUIDProvider(values: uuidSequence)
        )
        let rebuiltCount = try await rebuiltRuntime.rebuildOperationalStoreFromJournal()
        let actual = try await rebuiltStore.fetchAll()
            .sorted { $0.memoryID.description < $1.memoryID.description }

        #expect(rebuiltCount == 3)
        #expect(expected.map(\.memoryID) == actual.map(\.memoryID))
        #expect(expected.map(\.checksum) == actual.map(\.checksum))
        #expect(expected.map(\.summary) == actual.map(\.summary))
    }

    @Test("empty content and empty recall queries fail with typed errors")
    func invalidContentRejected() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        await #expect(throws: AndromedaRuntimeError.invalidMemoryContent("Memory content must not be empty.")) {
            _ = try await runtime.remember(
                RememberIntent(
                    scope: EventScope(projectID: projectID, sessionID: sessionID),
                    source: MemorySource(subsystem: "tests", actor: "memory", label: "invalid"),
                    content: "   ",
                    kind: .note,
                    privacyLevel: .project,
                    idempotencyKey: "invalid-memory"
                )
            )
        }

        await #expect(throws: AndromedaRuntimeError.invalidRecallQuery("Recall query must not be empty.")) {
            _ = try await runtime.recall(
                RecallRequest(
                    query: "  ",
                    scope: EventScope(projectID: projectID),
                    privacyCeiling: .project
                )
            )
        }
    }

    @Test("recall with zero matching query terms returns no records")
    func recallZeroMatchReturnsNothing() async throws {
        let context = try TestContext()
        let runtime = try makeRuntime(context: context)

        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID, sessionID: sessionID),
                source: MemorySource(subsystem: "tests", actor: "memory", label: "recall"),
                content: "Deployment runbook for the autocache gateway.",
                kind: .note,
                privacyLevel: .project,
                idempotencyKey: "recall-zero-match-1"
            )
        )

        let response = try await runtime.recall(
            RecallRequest(
                query: "zqxwv frabjous snickerdoodle",
                scope: EventScope(projectID: projectID),
                privacyCeiling: .project
            )
        )

        #expect(response.records.isEmpty)
        #expect(response.synthesizedContext == "No matching memory records were found for the requested scope.")
    }

    private func makeRuntime(
        context: TestContext,
        sinks: [any MemoryProjectionSink] = []
    ) throws -> MemoryRuntime {
        MemoryRuntime(
            journal: context.journal,
            operationalStore: context.store,
            projectionSinks: sinks,
            clock: FixedClock(date: fixedDate),
            uuidProvider: DeterministicUUIDProvider(values: uuidSequence)
        )
    }
}

private struct TestContext {
    let directory: URL
    let journal: JSONLineEventJournal
    let store: SQLiteMemoryOperationalStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        journal = try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl"))
        store = try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memories.sqlite3"))
    }
}

private final class RecordingSink: MemoryProjectionSink, @unchecked Sendable {
    let sinkID: String
    let schemaVersion: String = "sink.v1"
    let acceptsPrivate: Bool
    let shouldFail: Bool
    let allowedKinds: Set<MemoryKind>

    init(
        sinkID: String,
        acceptsPrivate: Bool,
        shouldFail: Bool,
        allowedKinds: Set<MemoryKind> = Set(MemoryKind.allCases)
    ) {
        self.sinkID = sinkID
        self.acceptsPrivate = acceptsPrivate
        self.shouldFail = shouldFail
        self.allowedKinds = allowedKinds
    }

    func accepts(_ record: MemoryRecord) -> Bool {
        allowedKinds.contains(record.kind) && (acceptsPrivate || record.privacyLevel != .private)
    }

    func write(record: MemoryRecord) async throws -> MemoryWriteReceipt {
        if shouldFail {
            throw AndromedaRuntimeError.operationalStoreFailed("Injected sink failure.")
        }
        return MemoryWriteReceipt(
            memoryID: record.memoryID,
            sinkID: sinkID,
            schemaVersion: schemaVersion,
            checksum: record.checksum,
            status: .committed,
            verification: .pending
        )
    }
}

private extension MemoryRuntimeTests {
    var fixedDate: Date { Date(timeIntervalSince1970: 1_722_000_000) }

    var projectID: ProjectID {
        ProjectID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }

    var sessionID: SessionID {
        SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
    }

    var otherSessionID: SessionID {
        SessionID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
    }

    var uuidSequence: [UUID] {
        [
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab0")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaab9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac0")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaac9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad0")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaad9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae0")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaae9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf0")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaf9")!,
        ]
    }

    func makeRecord(kind: MemoryKind, privacy: PrivacyLevel) -> MemoryRecord {
        MemoryRecord(
            memoryID: MemoryID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
            eventID: EventID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!),
            correlationID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            scope: EventScope(projectID: projectID, sessionID: sessionID),
            source: MemorySource(subsystem: "tests", actor: "memory", label: "record"),
            kind: kind,
            privacyLevel: privacy,
            summary: "Record summary",
            content: "Record content",
            tags: ["runtime"],
            metadata: [:],
            relatedContext: [:],
            checksum: "sha256:test",
            createdAt: fixedDate
        )
    }
}
