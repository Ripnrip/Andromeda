/**
 * OutboxLiveProjection — fail-open Realm-shaped live mirror of the JSON outbox (BIN-249).
 *
 * JSON seeds remain authority. This projection mirrors pending / delivered /
 * dead-letter state for operator awareness and never blocks retain success when
 * the live store is unavailable. Apple RealmSwift adapter is 📐 behind the same
 * protocol; this module ships a rebuildable in-process live projection that is
 * safe on CI Linux and macOS without importing Realm brands into clients.
 */

import Foundation

/// Snapshot of one projected outbox row for companion / health surfaces.
public struct OutboxProjectionRow: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let contentHash: String
    public let summary: String
    public let deliveryState: OutboxDeliveryState
    public let writeKind: CurtainWriteKind
    public let createdAt: Date
    public let isTombstone: Bool
    public let targetMemoryID: UUID?
    public let lastError: String?

    public init(from record: OutboxRecord) {
        self.id = record.id
        self.contentHash = record.contentHash
        self.summary = String(record.narrative.prefix(160))
        self.deliveryState = record.deliveryState
        self.writeKind = record.writeKind
        self.createdAt = record.createdAt
        self.isTombstone = record.isTombstone
        self.targetMemoryID = record.targetMemoryID
        self.lastError = record.lastError
    }
}

/// Fail-open live projection of the JSON outbox.
public protocol OutboxLiveProjection: Sendable {
    /// Human-readable projection name for health (never a client capability brand).
    var projectionID: String { get }
    /// Whether the last mutate attempt failed open.
    var lastFailureMessage: String? { get async }
    /// Upsert a row. Must not throw into retain success — failures are fail-open.
    func mirror(_ record: OutboxRecord) async
    /// Rebuild entire projection from JSON authority seeds.
    func rebuild(from records: [OutboxRecord]) async
    /// Current projected rows.
    func snapshot() async -> [OutboxProjectionRow]
    /// Count of projected rows by delivery state.
    func countsByState() async -> [OutboxDeliveryState: Int]
}

/// Null projection used when live mirroring is disabled.
public actor NullOutboxLiveProjection: OutboxLiveProjection {
    public let projectionID = "outbox.live.null"
    public private(set) var lastFailureMessage: String?

    public init() {}

    public func mirror(_ record: OutboxRecord) async {}
    public func rebuild(from records: [OutboxRecord]) async {}
    public func snapshot() async -> [OutboxProjectionRow] { [] }
    public func countsByState() async -> [OutboxDeliveryState: Int] {
        Dictionary(uniqueKeysWithValues: OutboxDeliveryState.allCases.map { ($0, 0) })
    }
}

/// In-process Realm-shaped live projection (rebuildable, fail-open).
///
/// Named `RealmOutboxLiveProjection` to match BIN-249's contract; it does **not**
/// import RealmSwift. Clients never see this type name — only queue insights.
public actor RealmOutboxLiveProjection: OutboxLiveProjection {
    public let projectionID = "outbox.live.realm_shaped"
    public private(set) var lastFailureMessage: String?

    private var rows: [UUID: OutboxProjectionRow] = [:]
    private var forceFailOpen: Bool

    public init(forceFailOpen: Bool = false) {
        self.forceFailOpen = forceFailOpen
    }

    /// Test seam: simulate projection unavailability.
    public func setForceFailOpen(_ value: Bool) {
        forceFailOpen = value
        if value {
            lastFailureMessage = "Forced fail-open: live projection unavailable"
        }
    }

    public func mirror(_ record: OutboxRecord) async {
        if forceFailOpen {
            lastFailureMessage = "Forced fail-open: live projection unavailable"
            return
        }
        rows[record.id] = OutboxProjectionRow(from: record)
        lastFailureMessage = nil
    }

    public func rebuild(from records: [OutboxRecord]) async {
        if forceFailOpen {
            lastFailureMessage = "Forced fail-open: rebuild skipped"
            return
        }
        rows = Dictionary(uniqueKeysWithValues: records.map { ($0.id, OutboxProjectionRow(from: $0)) })
        lastFailureMessage = nil
    }

    public func snapshot() async -> [OutboxProjectionRow] {
        rows.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func countsByState() async -> [OutboxDeliveryState: Int] {
        var counts: [OutboxDeliveryState: Int] = [:]
        for state in OutboxDeliveryState.allCases {
            counts[state] = 0
        }
        for row in rows.values {
            counts[row.deliveryState, default: 0] += 1
        }
        return counts
    }
}
