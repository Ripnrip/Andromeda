import Foundation
import OSLog

// MARK: - Sweep-event broadcast (the SSE seam)
//
// The package speaks typed streams; the HTTP surface maps them to
// `text/event-stream` frames (GatewayRouter already serves SSE — the
// guardian plugs into the same lane). Subscribers get every sweep report
// as it lands; slow consumers drop reports rather than block the guardian
// (telemetry must never backpressure the reaper).

/// Broadcasts sweep reports to any number of async subscribers.
///
/// Doubles as a `TelemetrySink`, so production wiring is one line:
/// `CompositeTelemetrySink(sinks: [JSONLTelemetrySink(), broadcaster])`.
public actor GuardianEventBroadcaster: TelemetrySink {

    /// One subscription's buffered stream (bounded — drops oldest on overflow).
    public struct Subscription: Sendable {
        public let id: UUID
        fileprivate let continuation: AsyncStream<SweepReport>.Continuation
        public let stream: AsyncStream<SweepReport>
    }

    private var continuations: [UUID: AsyncStream<SweepReport>.Continuation] = [:]

    public init() {}

    /// Number of live subscribers (observability surface).
    public var subscriberCount: Int { continuations.count }

    /// Subscribe to future sweep reports. The stream ends when the
    /// continuation is released (subscriber cancelled) — unsubscribe by
    /// dropping the task consuming it.
    public func subscribe() -> AsyncStream<SweepReport> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    /// TelemetrySink conformance: fan one report out to every subscriber.
    public func record(_ report: SweepReport) {
        for continuation in continuations.values {
            continuation.yield(report)
        }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}

// MARK: - SSE framing
//
// `text/event-stream` wire format, as data. The HTTP route maps a
// subscription's stream through `GuardianEventBroadcaster.sseFrames`.

extension GuardianEventBroadcaster {

    /// Encode one report as one SSE frame (`data: <json>\n\n`).
    public static func sseFrame(_ report: SweepReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(report)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw SSEFrameError.encodingFailed
        }
        // SSE lines must not contain raw newlines inside the payload — JSON
        // encoding guarantees none.
        return "event: sweep\ndata: \(json)\n\n"
    }

    /// Map a report stream to an SSE frame stream, ready to hand to an
    /// HTTP body writer.
    public static func sseFrames(_ reports: AsyncStream<SweepReport>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await report in reports {
                        continuation.yield(try sseFrame(report))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public enum SSEFrameError: Error, Sendable {
        case encodingFailed
    }
}
