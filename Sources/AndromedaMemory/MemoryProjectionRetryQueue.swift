import Foundation

/// Allows `MemoryRuntime` to hand failed projection receipts to a durable
/// retry mechanism without depending on the concrete projection target.
public protocol MemoryProjectionRetryQueue: Sendable {
    /// Enqueue a record for later retry.
    ///
    /// The receipt carries the sink that failed and the checksum that must
    /// be written. The queue is responsible for durably recording the entry
    /// and redriving it later.
    func enqueue(record: MemoryRecord, receipt: MemoryWriteReceipt) async throws
}
