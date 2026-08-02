import AndromedaDomain
import AndromedaJournal
import Foundation
import Testing

@Suite("AndromedaJournal")
struct EventJournalTests {
    @Test("replay preserves append order")
    func replayPreservesOrder() async throws {
        let journal = try InMemoryEventJournal()
        let first = makeEnvelope(
            eventUUID: "00000000-0000-0000-0000-000000000001",
            detail: "first"
        )
        let second = makeEnvelope(
            eventUUID: "00000000-0000-0000-0000-000000000002",
            detail: "second"
        )

        _ = try await journal.append(first, idempotencyKey: "key-1")
        _ = try await journal.append(second, idempotencyKey: "key-2")

        let replay = try await journal.replay(after: nil)

        #expect(replay.map(\.sequenceNumber) == [1, 2])
        #expect(replay.map(\.envelope.id) == [first.id, second.id])
    }

    @Test("duplicate idempotency keys do not duplicate canonical events")
    func idempotencyDedupes() async throws {
        let journal = try InMemoryEventJournal()
        let envelope = makeEnvelope(
            eventUUID: "00000000-0000-0000-0000-000000000003",
            detail: "dedupe"
        )

        let first = try await journal.append(envelope, idempotencyKey: "same-key")
        let second = try await journal.append(envelope, idempotencyKey: "same-key")
        let replay = try await journal.replay(after: nil)

        #expect(first.inserted)
        #expect(!second.inserted)
        #expect(replay.count == 1)
        #expect(second.sequenceNumber == first.sequenceNumber)
    }

    @Test("restart preserves history")
    func restartPreservesHistory() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let journalURL = directoryURL.appending(path: "runtime-journal.jsonl")

        let writer = try JSONLineEventJournal(fileURL: journalURL)
        _ = try await writer.append(
            makeEnvelope(
                eventUUID: "00000000-0000-0000-0000-000000000004",
                detail: "restart"
            ),
            idempotencyKey: "persisted-key"
        )

        let reloaded = try JSONLineEventJournal(fileURL: journalURL)
        let replay = try await reloaded.replay(after: nil)

        #expect(replay.count == 1)
        #expect(replay.first?.idempotencyKey == "persisted-key")
    }

    @Test("unsupported schema versions fail explicitly")
    func unsupportedVersionFails() async throws {
        let journal = try InMemoryEventJournal()
        let envelope: EventEnvelope<CanonicalEventPayload> = EventEnvelope(
            id: EventID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!),
            correlationID: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            occurredAt: Date(timeIntervalSince1970: 1_720_000_005),
            source: EventSource(subsystem: "tests", actor: "journal"),
            payload: .runtimeHeartbeat(RuntimeHeartbeatPayload(detail: "unsupported")),
            schemaVersion: 99
        )

        await #expect(throws: AndromedaRuntimeError.unsupportedSchemaVersion(99)) {
            _ = try await journal.append(envelope, idempotencyKey: "unsupported-key")
        }
    }

    @Test("concurrent appends keep a stable ordered journal")
    func concurrentAppendsKeepOrdering() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let journalURL = directoryURL.appending(path: "concurrent-runtime-journal.jsonl")
        let journal = try JSONLineEventJournal(fileURL: journalURL)

        let receipts = try await withThrowingTaskGroup(of: JournalAppendReceipt.self) { group in
            for index in 0..<25 {
                group.addTask {
                    try await journal.append(
                        makeEnvelope(
                            eventUUID: String(format: "00000000-0000-0000-0000-%012d", index + 10),
                            detail: "concurrent-\(index)"
                        ),
                        idempotencyKey: IdempotencyKey(rawValue: "concurrent-\(index)")
                    )
                }
            }

            var receipts: [JournalAppendReceipt] = []
            for try await receipt in group {
                receipts.append(receipt)
            }
            return receipts
        }

        let replay = try await journal.replay(after: nil)
        let orderedSequences = replay.map(\.sequenceNumber)

        #expect(receipts.count == 25)
        #expect(orderedSequences == Array(1...25).map(Int64.init))
        #expect(Set(replay.map(\.idempotencyKey.rawValue)).count == 25)
    }

    private func makeEnvelope(eventUUID: String, detail: String) -> EventEnvelope<CanonicalEventPayload> {
        EventEnvelope(
            id: EventID(rawValue: UUID(uuidString: eventUUID)!),
            correlationID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            occurredAt: Date(timeIntervalSince1970: 1_720_000_100),
            source: EventSource(
                subsystem: "tests",
                actor: "journal",
                scope: EventScope(
                    sessionID: SessionID(rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000000")!)
                )
            ),
            payload: .runtimeHeartbeat(RuntimeHeartbeatPayload(detail: detail))
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
