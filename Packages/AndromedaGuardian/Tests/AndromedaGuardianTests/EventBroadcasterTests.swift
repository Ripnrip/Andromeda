import AndromedaGuardian
import Foundation
import Testing

/// Broadcast + SSE seam coverage: subscribers receive every recorded sweep,
/// termination cleans up, and the SSE frame is a well-formed
/// `text/event-stream` payload carrying the full report.
@Suite("GuardianEventBroadcaster")
struct EventBroadcasterTests {

    /// A minimal report fixture.
    private func report(id: UUID = UUID()) -> SweepReport {
        SweepReport(
            sweepID: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_001),
            censusSize: 900,
            pressure: .normal,
            decisions: [],
            outcomes: [],
            condemnedRSSBytes: 0,
            dryRun: true
        )
    }

    @Test("subscriber receives every recorded report")
    func fanOut() async {
        let broadcaster = GuardianEventBroadcaster()
        let stream = await broadcaster.subscribe()

        let expected = [report(), report(), report()]
        for item in expected {
            await broadcaster.record(item)
        }

        var received: [SweepReport] = []
        var iterator = stream.makeAsyncIterator()
        for _ in expected {
            if let next = await iterator.next() {
                received.append(next)
            }
        }
        #expect(received == expected)
    }

    @Test("two subscribers each receive the same reports")
    func multiSubscriber() async {
        let broadcaster = GuardianEventBroadcaster()
        let first = await broadcaster.subscribe()
        let second = await broadcaster.subscribe()
        #expect(await broadcaster.subscriberCount == 2)

        let item = report()
        await broadcaster.record(item)

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next() == item)
        #expect(await secondIterator.next() == item)
    }

    @Test("SSE frame carries the full report as one data line")
    func sseFrameShape() throws {
        let item = report()
        let frame = try GuardianEventBroadcaster.sseFrame(item)

        #expect(frame.hasPrefix("event: sweep\n"))
        #expect(frame.hasSuffix("\n\n"))
        // Exactly one data line; SSE forbids raw newlines inside payloads.
        let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.filter { $0.hasPrefix("data: ") }.count == 1)

        // The data payload decodes back to the same report.
        guard let dataLine = lines.first(where: { $0.hasPrefix("data: ") }) else {
            Issue.record("missing data line")
            return
        }
        let json = String(dataLine.dropFirst("data: ".count))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SweepReport.self, from: Data(json.utf8))
        #expect(decoded == item)
    }

    @Test("sseFrames maps a report stream to frames and terminates cleanly")
    func sseFramesMapping() async throws {
        let broadcaster = GuardianEventBroadcaster()
        let reports = await broadcaster.subscribe()
        let frames = GuardianEventBroadcaster.sseFrames(reports)

        let expected = [report(), report()]
        let producer = Task {
            for item in expected { await broadcaster.record(item) }
        }

        var received: [String] = []
        var iterator = frames.makeAsyncIterator()
        _ = await producer.value
        for _ in expected {
            if let frame = try await iterator.next() {
                received.append(frame)
            }
        }
        #expect(received.count == 2)
        #expect(received.allSatisfy { $0.hasPrefix("event: sweep\n") })
    }
}
