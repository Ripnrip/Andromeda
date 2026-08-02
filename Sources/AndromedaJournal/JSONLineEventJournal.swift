import AndromedaDomain
import Foundation

/// JSONL-backed append-only journal that survives process restart and preserves append order.
public actor JSONLineEventJournal: EventJournal {
    private let fileURL: URL
    private let supportedSchemaVersions: Set<EventSchemaVersion>
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var records: [PersistedEvent]
    private var recordsByKey: [IdempotencyKey: PersistedEvent]

    public init(
        fileURL: URL,
        supportedSchemaVersions: Set<EventSchemaVersion> = [.current]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        try Self.prepareStorage(at: fileURL)
        let loadedState = try Self.loadFromDisk(
            fileURL: fileURL,
            decoder: decoder,
            supportedSchemaVersions: supportedSchemaVersions
        )

        self.fileURL = fileURL
        self.supportedSchemaVersions = supportedSchemaVersions
        self.encoder = encoder
        self.decoder = decoder
        self.records = loadedState.records
        self.recordsByKey = loadedState.recordsByKey
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
        let encoded = try encoder.encode(record)
        try appendLine(encoded)
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

    private static func loadFromDisk(
        fileURL: URL,
        decoder: JSONDecoder,
        supportedSchemaVersions: Set<EventSchemaVersion>
    ) throws -> (records: [PersistedEvent], recordsByKey: [IdempotencyKey: PersistedEvent]) {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return ([], [:]) }

        guard let text = String(data: data, encoding: .utf8) else {
            throw AndromedaRuntimeError.journalCorrupted("Journal file is not valid UTF-8 JSONL")
        }

        let lines = text.split(whereSeparator: \.isNewline)
        var records: [PersistedEvent] = []
        var recordsByKey: [IdempotencyKey: PersistedEvent] = [:]

        for line in lines where !line.isEmpty {
            let record = try decoder.decode(PersistedEvent.self, from: Data(line.utf8))
            try Self.validate(record.envelope.schemaVersion, supportedSchemaVersions: supportedSchemaVersions)
            let expectedSequence = Int64(records.count + 1)
            guard record.sequenceNumber == expectedSequence else {
                throw AndromedaRuntimeError.journalCorrupted(
                    "Journal sequence gap at line \(expectedSequence); found \(record.sequenceNumber)"
                )
            }
            if let existing = recordsByKey[record.idempotencyKey] {
                throw AndromedaRuntimeError.journalCorrupted(
                    "Duplicate idempotency key \(record.idempotencyKey.rawValue) for events \(existing.envelope.id) and \(record.envelope.id)"
                )
            }
            records.append(record)
            recordsByKey[record.idempotencyKey] = record
        }

        return (records, recordsByKey)
    }

    private func appendLine(_ data: Data) throws {
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            try handle.synchronize()
        } catch {
            throw AndromedaRuntimeError.journalIOFailed("Failed to append event journal line: \(error.localizedDescription)")
        }
    }

    private static func validate(
        _ version: EventSchemaVersion,
        supportedSchemaVersions: Set<EventSchemaVersion>
    ) throws {
        guard supportedSchemaVersions.contains(version) else {
            throw AndromedaRuntimeError.unsupportedSchemaVersion(version.rawValue)
        }
    }

    private static func prepareStorage(at fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }
}
