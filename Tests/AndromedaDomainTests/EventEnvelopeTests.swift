import AndromedaDomain
import Foundation
import Testing

@Suite("AndromedaDomain.EventEnvelope")
struct EventEnvelopeTests {
    @Test("envelope encoding round-trips")
    func roundTrip() throws {
        let envelope: EventEnvelope<CanonicalEventPayload> = EventEnvelope(
            id: EventID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            causationID: EventID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!),
            correlationID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            occurredAt: Date(timeIntervalSince1970: 1_720_000_000),
            source: EventSource(
                subsystem: "tests",
                actor: "domain",
                scope: EventScope(
                    projectID: ProjectID(rawValue: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
                )
            ),
            payload: .memoryNoted(
                MemoryNotedPayload(
                    memoryID: MemoryID(rawValue: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!),
                    summary: "round-trip"
                )
            )
        )

        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(EventEnvelope<CanonicalEventPayload>.self, from: encoded)

        #expect(decoded == envelope)
    }
}
