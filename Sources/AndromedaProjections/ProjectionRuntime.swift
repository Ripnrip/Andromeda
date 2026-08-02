import AndromedaDomain
import AndromedaMemory
import Foundation

/// Outcome of a single retry attempt.
public struct ProjectionRetryOutcome: Sendable, Equatable {
    public let memoryID: MemoryID
    public let sinkID: String
    public let oldReceipt: MemoryWriteReceipt
    public let newReceipt: MemoryWriteReceipt

    public init(
        memoryID: MemoryID,
        sinkID: String,
        oldReceipt: MemoryWriteReceipt,
        newReceipt: MemoryWriteReceipt
    ) {
        self.memoryID = memoryID
        self.sinkID = sinkID
        self.oldReceipt = oldReceipt
        self.newReceipt = newReceipt
    }
}

/// Runtime that owns projection sinks and a durable retry queue.
///
/// `MemoryRuntime` depends on this object only through the
/// `MemoryProjectionRetryQueue` protocol, keeping the memory module free of
/// projection implementation details.
public actor ProjectionRuntime: MemoryProjectionRetryQueue {
    private let sinks: [any MemoryProjectionSink]
    private let queue: DurableRetryQueue

    public init(sinks: [any MemoryProjectionSink], queue: DurableRetryQueue) {
        self.sinks = sinks
        self.queue = queue
    }

    /// Persist a failed projection for later retry.
    public func enqueue(record: MemoryRecord, receipt: MemoryWriteReceipt) async throws {
        let entry = DurableRetryQueue.Entry(
            memoryRecord: record,
            receipt: receipt,
            enqueuedAt: Date()
        )
        try await queue.enqueue(entry)
    }

    /// Re-drive every pending projection through its original sink.
    ///
    /// Successfully retried entries are removed from the queue. Entries that
    /// still fail are rewritten with a fresh failure receipt.
    public func retryPending() async throws -> [ProjectionRetryOutcome] {
        let pending = try await queue.pendingEntries()
        var remaining: [DurableRetryQueue.Entry] = []
        var outcomes: [ProjectionRetryOutcome] = []

        for entry in pending {
            guard let sink = sinks.first(where: { $0.sinkID == entry.receipt.sinkID }) else {
                // No sink registered for this receipt; keep it queued so an
                // operator can diagnose the mismatch.
                remaining.append(entry)
                continue
            }

            do {
                let newReceipt = try await sink.write(record: entry.memoryRecord)
                outcomes.append(
                    ProjectionRetryOutcome(
                        memoryID: entry.memoryRecord.memoryID,
                        sinkID: sink.sinkID,
                        oldReceipt: entry.receipt,
                        newReceipt: newReceipt
                    )
                )
            } catch {
                let newReceipt = MemoryWriteReceipt(
                    memoryID: entry.memoryRecord.memoryID,
                    sinkID: sink.sinkID,
                    schemaVersion: sink.schemaVersion,
                    checksum: entry.memoryRecord.checksum,
                    status: .retryableFailure,
                    verification: .failed
                )
                remaining.append(
                    DurableRetryQueue.Entry(
                        memoryRecord: entry.memoryRecord,
                        receipt: newReceipt,
                        enqueuedAt: entry.enqueuedAt
                    )
                )
                outcomes.append(
                    ProjectionRetryOutcome(
                        memoryID: entry.memoryRecord.memoryID,
                        sinkID: sink.sinkID,
                        oldReceipt: entry.receipt,
                        newReceipt: newReceipt
                    )
                )
            }
        }

        try await queue.replace(with: remaining)
        return outcomes
    }

    /// Number of entries currently waiting in the durable queue.
    public func pendingCount() async throws -> Int {
        try await queue.pendingEntries().count
    }
}
