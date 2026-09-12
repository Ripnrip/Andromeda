import AndromedaDomain
import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import AndromedaProjections
@testable import AndromedaServer
import Foundation
import Testing

/// Gate-2 proof for the production adapter: the dispatcher drives the REAL
/// ProjectionRuntime (not a fixture) over a retry queue file, exactly the
/// code path `serve`'s periodic loop runs — and the state source reports the
/// backlog the dispatcher then drains.
@Suite("AndromedaServer.ControlPlaneRuntimeAdapter")
struct ControlPlaneRuntimeAdapterTests {
    /// Sink that succeeds — entries drain on first retry.
    private actor ReliableSink: MemoryProjectionSink {
        nonisolated let sinkID = "control.test.sink"
        nonisolated let schemaVersion = "control.test.v1"

        nonisolated func accepts(_ record: MemoryRecord) -> Bool {
            true
        }

        func write(record: MemoryRecord) async throws -> MemoryWriteReceipt {
            MemoryWriteReceipt(
                memoryID: record.memoryID,
                sinkID: sinkID,
                schemaVersion: schemaVersion,
                checksum: record.checksum,
                status: .committed,
                verification: .pending
            )
        }
    }

    private struct Rig {
        let directory: URL
        let queue: DurableRetryQueue
        let projections: ProjectionRuntime
        let state: ControlPlaneRuntimeState
        let actions: ControlPlaneRuntimeActions
    }

    private func makeRig() throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = DurableRetryQueue(
            fileURL: directory.appendingPathComponent("retry.jsonl")
        )
        let projections = ProjectionRuntime(sinks: [ReliableSink()], queue: queue)
        let configuration = AndromedaRuntimeConfiguration()
        return try Rig(
            directory: directory,
            queue: queue,
            projections: projections,
            state: ControlPlaneRuntimeState(
                configuration: configuration,
                memoryRuntime: Self.emptyMemoryRuntime(directory: directory),
                projectionRuntime: projections
            ),
            actions: ControlPlaneRuntimeActions(projectionRuntime: projections)
        )
    }

    /// A real MemoryRuntime over an empty journal — snapshot's memory count
    /// reads zero without touching fixture shortcuts.
    private static func emptyMemoryRuntime(directory: URL) throws -> MemoryRuntime {
        let journal = try JSONLineEventJournal(
            fileURL: directory.appendingPathComponent("journal.jsonl")
        )
        let store = try SQLiteMemoryOperationalStore(
            databaseURL: directory.appendingPathComponent("memories.sqlite3")
        )
        return MemoryRuntime(journal: journal, operationalStore: store)
    }

    @Test("state reports the backlog the dispatcher drains — one source of truth")
    func stateMatchesDispatch() async throws {
        let rig = try makeRig()
        let record = Self.makeRecord()
        try await rig.queue.enqueue(.init(memoryRecord: record, receipt: Self.failureReceipt(for: record), enqueuedAt: Date()))

        // Before: backlog visible in state.
        let before = try await rig.state.snapshot()
        #expect(before.counts.projectionBacklog == 1)

        // Dispatch drains it — same ProjectionRuntime object.
        let outcome = await rig.actions.dispatch(.drainProjections)
        #expect(outcome.status == .ok)
        #expect(outcome.detail.contains("recovered 1"))

        // After: backlog is zero in state.
        let after = try await rig.state.snapshot()
        #expect(after.counts.projectionBacklog == 0)
        #expect(after.counts.memories == 0)
        #expect(after.surfaces.contains("http"))
    }

    @Test("drain on an empty queue is ok with zero attempted")
    func drainEmptyQueue() async throws {
        let rig = try makeRig()
        let outcome = await rig.actions.dispatch(.drainProjections)
        #expect(outcome.status == .ok)
        #expect(outcome.detail.contains("attempted 0"))
    }

    @Test("snapshot counts memories from the journal")
    func snapshotCountsMemories() async throws {
        let rig = try makeRig()
        let runtime = try Self.emptyMemoryRuntime(directory: rig.directory)
        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(
                    projectID: ProjectID(rawValue: #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
                    sessionID: SessionID(rawValue: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")))
                ),
                source: MemorySource(subsystem: "tests", actor: "server", label: "control"),
                content: "Control-plane adapter count proof.",
                kind: .workflow,
                privacyLevel: .project,
                tags: ["control-plane"],
                metadata: [:],
                idempotencyKey: "control-adapter-1"
            )
        )

        let state = ControlPlaneRuntimeState(
            configuration: AndromedaRuntimeConfiguration(),
            memoryRuntime: runtime,
            projectionRuntime: rig.projections
        )
        let snapshot = try await state.snapshot()
        #expect(snapshot.counts.memories == 1)
    }

    @Test("snapshot never mutates the operational store (read-only count proof)")
    func snapshotIsReadOnly() async throws {
        // Codex P1 + Cursor MEDIUM regression: the first implementation
        // counted via rebuildOperationalStoreFromJournal(), which DELETEs
        // every row before replay — a read route mutating the hot store and
        // racing concurrent recalls. The fix counts via recordCount(); this
        // test proves a second runtime sharing the same journal+store sees
        // its records intact after a snapshot.
        let rig = try makeRig()
        let runtime = try Self.emptyMemoryRuntime(directory: rig.directory)
        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(
                    projectID: ProjectID(rawValue: #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
                    sessionID: SessionID(rawValue: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")))
                ),
                source: MemorySource(subsystem: "tests", actor: "server", label: "control"),
                content: "Read-only snapshot proof.",
                kind: .workflow,
                privacyLevel: .project,
                tags: ["control-plane"],
                metadata: [:],
                idempotencyKey: "control-readonly-1"
            )
        )

        let state = ControlPlaneRuntimeState(
            configuration: AndromedaRuntimeConfiguration(),
            memoryRuntime: runtime,
            projectionRuntime: rig.projections
        )
        let before = try await runtime.operationalRecordCount()
        _ = try await state.snapshot()
        let after = try await runtime.operationalRecordCount()

        #expect(before == 1)
        #expect(after == 1, "snapshot must not mutate the operational store")
    }

    // MARK: - Fixtures

    private static func makeRecord() -> MemoryRecord {
        MemoryRecord(
            memoryID: MemoryID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4")!),
            eventID: EventID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4")!),
            correlationID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc4")!,
            scope: EventScope(
                projectID: ProjectID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
                sessionID: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
            ),
            source: MemorySource(subsystem: "tests", actor: "control-plane", label: "adapter"),
            kind: .note,
            privacyLevel: .project,
            summary: "Control plane adapter test",
            content: "Entry enqueued for the drain proof.",
            tags: ["control-plane"],
            metadata: [:],
            relatedContext: [:],
            checksum: "sha256:ctrl1",
            createdAt: Date(timeIntervalSince1970: 1_757_600_000)
        )
    }

    private static func failureReceipt(for record: MemoryRecord) -> MemoryWriteReceipt {
        MemoryWriteReceipt(
            memoryID: record.memoryID,
            sinkID: "control.test.sink",
            schemaVersion: "control.test.v1",
            checksum: record.checksum,
            status: .retryableFailure,
            verification: .failed
        )
    }
}
