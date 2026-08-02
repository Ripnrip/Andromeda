import AndromedaDomain
import AndromedaMemory
import Foundation
import Testing

@testable import AndromedaProjections

@Suite("AndromedaProjections.DurableRetryQueue")
struct DurableRetryQueueTests {
    @Test("persists entries across queue restarts")
    func persistsAcrossRestarts() async throws {
        let fileURL = try makeQueueFile()
        let queue = DurableRetryQueue(fileURL: fileURL)
        let record = makeRecord()
        let receipt = makeFailureReceipt(for: record, sinkID: "sink.flaky")

        try await queue.enqueue(.init(memoryRecord: record, receipt: receipt, enqueuedAt: Date()))

        let restartedQueue = DurableRetryQueue(fileURL: fileURL)
        let pending = try await restartedQueue.pendingEntries()

        #expect(pending.count == 1)
        #expect(pending.first?.memoryRecord.memoryID == record.memoryID)
        #expect(pending.first?.receipt.sinkID == receipt.sinkID)
    }

    @Test("retry flips a failed receipt to committed when the sink succeeds")
    func retrySuccessFlipsReceipt() async throws {
        let fileURL = try makeQueueFile()
        let queue = DurableRetryQueue(fileURL: fileURL)
        let record = makeRecord()
        let failureReceipt = makeFailureReceipt(for: record, sinkID: "sink.recoverable")
        try await queue.enqueue(.init(memoryRecord: record, receipt: failureReceipt, enqueuedAt: Date()))

        let flakySink = FlakySink(sinkID: "sink.recoverable", failNext: false)
        let runtime = ProjectionRuntime(sinks: [flakySink], queue: queue)
        let outcomes = try await runtime.retryPending()

        #expect(outcomes.count == 1)
        #expect(outcomes.first?.oldReceipt.status == .retryableFailure)
        #expect(outcomes.first?.newReceipt.status == .committed)
        #expect(try await runtime.pendingCount() == 0)
    }

    @Test("keeps still-failing entries after retry")
    func keepsStillFailingEntries() async throws {
        let fileURL = try makeQueueFile()
        let queue = DurableRetryQueue(fileURL: fileURL)
        let record = makeRecord()
        let failureReceipt = makeFailureReceipt(for: record, sinkID: "sink.broken")
        try await queue.enqueue(.init(memoryRecord: record, receipt: failureReceipt, enqueuedAt: Date()))

        let brokenSink = FlakySink(sinkID: "sink.broken", failNext: true)
        let runtime = ProjectionRuntime(sinks: [brokenSink], queue: queue)
        let outcomes = try await runtime.retryPending()

        #expect(outcomes.count == 1)
        #expect(outcomes.first?.newReceipt.status == .retryableFailure)
        #expect(try await runtime.pendingCount() == 1)
    }

    private func makeQueueFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("retry.jsonl")
    }

    private func makeRecord() -> MemoryRecord {
        MemoryRecord(
            memoryID: MemoryID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3")!),
            eventID: EventID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3")!),
            correlationID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc3")!,
            scope: EventScope(
                projectID: ProjectID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
                sessionID: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
            ),
            source: MemorySource(subsystem: "tests", actor: "projection", label: "retry"),
            kind: .note,
            privacyLevel: .project,
            summary: "Retry queue entry",
            content: "This memory needs a retry.",
            tags: ["retry"],
            metadata: [:],
            relatedContext: [:],
            checksum: "sha256:ghi789",
            createdAt: Date(timeIntervalSince1970: 1_722_000_000)
        )
    }

    private func makeFailureReceipt(for record: MemoryRecord, sinkID: String) -> MemoryWriteReceipt {
        MemoryWriteReceipt(
            memoryID: record.memoryID,
            sinkID: sinkID,
            schemaVersion: "sink.v1",
            checksum: record.checksum,
            status: .retryableFailure,
            verification: .failed
        )
    }
}

private actor FlakySink: MemoryProjectionSink {
    let sinkID: String
    let schemaVersion: String = "sink.v1"
    var failNext: Bool

    init(sinkID: String, failNext: Bool) {
        self.sinkID = sinkID
        self.failNext = failNext
    }

    nonisolated func accepts(_ record: MemoryRecord) -> Bool { true }

    func write(record: MemoryRecord) async throws -> MemoryWriteReceipt {
        if failNext {
            throw AndromedaRuntimeError.operationalStoreFailed("Injected failure.")
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
