import AndromedaDomain
import Foundation

/// The canonical persisted event plus journal ordering metadata.
public struct PersistedEvent: Codable, Sendable, Equatable {
    public let sequenceNumber: Int64
    public let idempotencyKey: IdempotencyKey
    public let envelope: EventEnvelope<CanonicalEventPayload>

    public init(
        sequenceNumber: Int64,
        idempotencyKey: IdempotencyKey,
        envelope: EventEnvelope<CanonicalEventPayload>
    ) {
        self.sequenceNumber = sequenceNumber
        self.idempotencyKey = idempotencyKey
        self.envelope = envelope
    }
}

/// Receipt describing whether an append created a new canonical fact or reused an idempotent prior write.
public struct JournalAppendReceipt: Sendable, Equatable {
    public let eventID: EventID
    public let sequenceNumber: Int64
    public let idempotencyKey: IdempotencyKey
    public let inserted: Bool

    public init(eventID: EventID, sequenceNumber: Int64, idempotencyKey: IdempotencyKey, inserted: Bool) {
        self.eventID = eventID
        self.sequenceNumber = sequenceNumber
        self.idempotencyKey = idempotencyKey
        self.inserted = inserted
    }
}

/// Storage-independent protocol for the canonical append-only journal.
public protocol EventJournal: Sendable {
    func append(
        _ envelope: EventEnvelope<CanonicalEventPayload>,
        idempotencyKey: IdempotencyKey
    ) async throws -> JournalAppendReceipt

    func replay(after sequenceNumber: Int64?) async throws -> [PersistedEvent]
}
