import AndromedaDomain
import Foundation

/// Actor-backed in-memory journal used by unit tests and runtime stubs without filesystem state.
public actor InMemoryEventJournal: EventJournal {
    private let supportedSchemaVersions: Set<EventSchemaVersion>
    private var records: [PersistedEvent]
    private var recordsByKey: [IdempotencyKey: PersistedEvent]

    public init(
        supportedSchemaVersions: Set<EventSchemaVersion> = [.current],
        seedRecords: [PersistedEvent] = []
    ) throws {
        self.supportedSchemaVersions = supportedSchemaVersions
        self.records = []
        self.recordsByKey = [:]
        for record in seedRecords {
            try Self.validate(record.envelope.schemaVersion, supportedSchemaVersions: supportedSchemaVersions)
            records.append(record)
            recordsByKey[record.idempotencyKey] = record
        }
    }

    public func append(
        _ envelope: EventEnvelope<CanonicalEventPayload>,
        idempotencyKey: IdempotencyKey
    ) async throws -> JournalAppendReceipt {
        try Self.validate(envelope.schemaVersion, supportedSchemaVersions: supportedSchemaVersions)
        if let existing = recordsByKey[idempotencyKey] {
            if existing.envelope.id != envelope.id {
                throw AndromedaRuntimeError.duplicateIdempotencyConflict(
                    key: idempotencyKey,
                    existingEventID: existing.envelope.id
                )
            }
            return JournalAppendReceipt(
                eventID: existing.envelope.id,
                sequenceNumber: existing.sequenceNumber,
                idempotencyKey: idempotencyKey,
                inserted: false
            )
        }

        let record = PersistedEvent(
            sequenceNumber: Int64(records.count + 1),
            idempotencyKey: idempotencyKey,
            envelope: envelope
        )
        records.append(record)
        recordsByKey[idempotencyKey] = record
        return JournalAppendReceipt(
            eventID: envelope.id,
            sequenceNumber: record.sequenceNumber,
            idempotencyKey: idempotencyKey,
            inserted: true
        )
    }

    public func replay(after sequenceNumber: Int64? = nil) async throws -> [PersistedEvent] {
        guard let sequenceNumber else { return records }
        return records.filter { $0.sequenceNumber > sequenceNumber }
    }

    private static func validate(
        _ version: EventSchemaVersion,
        supportedSchemaVersions: Set<EventSchemaVersion>
    ) throws {
        guard supportedSchemaVersions.contains(version) else {
            throw AndromedaRuntimeError.unsupportedSchemaVersion(version.rawValue)
        }
    }
}
