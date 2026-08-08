/**
 * JSONOutboxAuthority — durable memory write authority (BIN-248).
 *
 * Retain acceptance is atomic JSONL enqueue. Downstream delivery is async and
 * may fail without rolling back the outbox row. Replay rebuilds projections
 * from these seeds without depending on backend availability.
 */

import CryptoKit
import Foundation

/// Delivery lifecycle for an outbox row.
public enum OutboxDeliveryState: String, Sendable, Codable, CaseIterable, Equatable {
    case pending
    case delivered
    case deadLetter
}

/// One durable retain (or forget) intake record.
public struct OutboxRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let contentHash: String
    public let narrative: String
    public let project: String
    public let agent: String
    public let provenance: String
    public let visibility: String
    public let tags: [String]
    public let writeKind: CurtainWriteKind
    public let createdAt: Date
    public var deliveryState: OutboxDeliveryState
    public var lastError: String?
    public var deliveredAt: Date?
    /// When set, this row is a forget tombstone for `targetMemoryID`.
    public var targetMemoryID: UUID?
    public var isTombstone: Bool

    public init(
        id: UUID = UUID(),
        contentHash: String,
        narrative: String,
        project: String,
        agent: String,
        provenance: String,
        visibility: String,
        tags: [String],
        writeKind: CurtainWriteKind,
        createdAt: Date = Date(),
        deliveryState: OutboxDeliveryState = .pending,
        lastError: String? = nil,
        deliveredAt: Date? = nil,
        targetMemoryID: UUID? = nil,
        isTombstone: Bool = false
    ) {
        self.id = id
        self.contentHash = contentHash
        self.narrative = narrative
        self.project = project
        self.agent = agent
        self.provenance = provenance
        self.visibility = visibility
        self.tags = tags
        self.writeKind = writeKind
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.lastError = lastError
        self.deliveredAt = deliveredAt
        self.targetMemoryID = targetMemoryID
        self.isTombstone = isTombstone
    }
}

public enum JSONOutboxError: Error, LocalizedError, Sendable, Equatable {
    case emptyNarrative
    case encodingFailed
    case decodingFailed
    case missingDirectory

    public var errorDescription: String? {
        switch self {
        case .emptyNarrative: return "Cannot retain an empty narrative into the JSON outbox."
        case .encodingFailed: return "Failed to encode an outbox record."
        case .decodingFailed: return "Failed to decode an outbox seed line."
        case .missingDirectory: return "Outbox directory could not be created."
        }
    }
}

/// Actor-owned JSONL outbox — the durable write authority for Andromida retain.
public actor JSONOutboxAuthority {
    public let directoryURL: URL
    public let seedsURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cache: [OutboxRecord]

    /// Create an outbox rooted at `directoryURL` (creates on first retain).
    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        self.seedsURL = directoryURL.appendingPathComponent("outbox-seeds.jsonl", isDirectory: false)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.cache = []

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.cache = try Self.loadSeeds(from: seedsURL, decoder: decoder)
    }

    /// In-memory outbox for tests (still writes when a temp directory is provided).
    public static func makeTemporary() throws -> JSONOutboxAuthority {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("andromida-outbox-\(UUID().uuidString)", isDirectory: true)
        return try JSONOutboxAuthority(directoryURL: url)
    }

    /// SHA-256 content hash used as the cross-projection join key.
    public nonisolated static func contentHash(for narrative: String) -> String {
        let digest = SHA256.hash(data: Data(narrative.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    /// Atomically accept a retain into the durable outbox (authority).
    @discardableResult
    public func retain(
        narrative: String,
        project: String,
        agent: String,
        provenance: String,
        visibility: String = "private",
        tags: [String] = [],
        writeKind: CurtainWriteKind = .episodic,
        id: UUID = UUID()
    ) throws -> OutboxRecord {
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JSONOutboxError.emptyNarrative }

        let record = OutboxRecord(
            id: id,
            contentHash: Self.contentHash(for: trimmed),
            narrative: trimmed,
            project: project,
            agent: agent,
            provenance: provenance,
            visibility: visibility,
            tags: tags,
            writeKind: writeKind,
            createdAt: Date(),
            deliveryState: .pending
        )
        try append(record)
        return record
    }

    /// Atomically accept a forget tombstone into the durable outbox.
    @discardableResult
    public func forget(targetMemoryID: UUID, reason: String, agent: String, project: String) throws -> OutboxRecord {
        let narrative = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "forget:\(targetMemoryID.uuidString)"
            : reason
        let record = OutboxRecord(
            id: UUID(),
            contentHash: Self.contentHash(for: "tombstone:\(targetMemoryID.uuidString):\(narrative)"),
            narrative: narrative,
            project: project,
            agent: agent,
            provenance: "memory_forget",
            visibility: "internal",
            tags: ["tombstone"],
            writeKind: .forgetTombstone,
            createdAt: Date(),
            deliveryState: .pending,
            targetMemoryID: targetMemoryID,
            isTombstone: true
        )
        try append(record)
        return record
    }

    /// All durable seeds in append order (authority snapshot).
    public func allRecords() -> [OutboxRecord] {
        cache
    }

    public func records(in state: OutboxDeliveryState) -> [OutboxRecord] {
        cache.filter { $0.deliveryState == state }
    }

    public func tombstoneIDs() -> Set<UUID> {
        Set(cache.filter(\.isTombstone).compactMap(\.targetMemoryID))
    }

    /// Mark delivery outcome without removing the durable seed.
    public func mark(_ id: UUID, state: OutboxDeliveryState, error: String? = nil) throws {
        guard let index = cache.firstIndex(where: { $0.id == id }) else { return }
        cache[index].deliveryState = state
        cache[index].lastError = error
        cache[index].deliveredAt = state == .delivered ? Date() : cache[index].deliveredAt
        try rewriteSeeds()
    }

    /// Pending rows eligible for backend fan-out / replay.
    public func pendingForReplay() -> [OutboxRecord] {
        cache.filter { $0.deliveryState == .pending || $0.deliveryState == .deadLetter }
    }

    /// Counts by delivery state for health / companion surfaces.
    public func countsByState() -> [OutboxDeliveryState: Int] {
        var counts: [OutboxDeliveryState: Int] = [:]
        for state in OutboxDeliveryState.allCases {
            counts[state] = 0
        }
        for record in cache {
            counts[record.deliveryState, default: 0] += 1
        }
        return counts
    }

    private func append(_ record: OutboxRecord) throws {
        let data = try encoder.encode(record)
        guard var line = String(data: data, encoding: .utf8) else {
            throw JSONOutboxError.encodingFailed
        }
        line.append("\n")
        guard let lineData = line.data(using: .utf8) else {
            throw JSONOutboxError.encodingFailed
        }

        if FileManager.default.fileExists(atPath: seedsURL.path) {
            let handle = try FileHandle(forWritingTo: seedsURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } else {
            try lineData.write(to: seedsURL, options: .atomic)
        }
        cache.append(record)
    }

    private func rewriteSeeds() throws {
        guard !cache.isEmpty else {
            if FileManager.default.fileExists(atPath: seedsURL.path) {
                try FileManager.default.removeItem(at: seedsURL)
            }
            return
        }
        var lines: [String] = []
        for record in cache {
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw JSONOutboxError.encodingFailed
            }
            lines.append(line)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: seedsURL, atomically: true, encoding: .utf8)
    }

    private static func loadSeeds(from url: URL, decoder: JSONDecoder) throws -> [OutboxRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONOutboxError.decodingFailed
        }
        var records: [OutboxRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let record = try decoder.decode(OutboxRecord.self, from: Data(trimmed.utf8))
            records.append(record)
        }
        return records
    }
}
