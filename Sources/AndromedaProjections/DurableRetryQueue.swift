import AndromedaDomain
import AndromedaMemory
import Foundation

/// A JSONL-backed retry queue for projection sink failures.
///
/// Entries are appended as single-line JSON objects. `retryPending` reads
/// every entry, attempts the associated sink, and rewrites the queue to
/// contain only entries that are still failing.
public actor DurableRetryQueue {
    public struct Entry: Codable, Sendable, Equatable {
        public let memoryRecord: MemoryRecord
        public let receipt: MemoryWriteReceipt
        public let enqueuedAt: Date

        public init(memoryRecord: MemoryRecord, receipt: MemoryWriteReceipt, enqueuedAt: Date) {
            self.memoryRecord = memoryRecord
            self.receipt = receipt
            self.enqueuedAt = enqueuedAt
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Append an entry to the durable queue.
    public func enqueue(_ entry: Entry) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(entry)
        guard let line = String(data: data, encoding: .utf8) else {
            throw DurableRetryQueueError.encodingFailed
        }
        let lineWithTerminator = line + "\n"
        guard let lineData = lineWithTerminator.data(using: .utf8) else {
            throw DurableRetryQueueError.encodingFailed
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } else {
            try lineData.write(to: fileURL, options: .atomic)
        }
    }

    /// Read every queued entry without modifying the file.
    public func pendingEntries() throws -> [Entry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DurableRetryQueueError.decodingFailed
        }

        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let lineData = Data(trimmed.utf8)
            let entry = try decoder.decode(Entry.self, from: lineData)
            entries.append(entry)
        }
        return entries
    }

    /// Replace the queue with the provided entries.
    ///
    /// Used after a retry pass to persist entries that remain failed.
    public func replace(with entries: [Entry]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !entries.isEmpty else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }

        var lines: [String] = []
        for entry in entries {
            let data = try encoder.encode(entry)
            guard let line = String(data: data, encoding: .utf8) else {
                throw DurableRetryQueueError.encodingFailed
            }
            lines.append(line)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(toFile: fileURL.path, atomically: true, encoding: .utf8)
    }
}

public enum DurableRetryQueueError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}
