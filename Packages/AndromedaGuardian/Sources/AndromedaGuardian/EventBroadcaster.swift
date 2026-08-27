import Foundation
import OSLog

// MARK: - SSE frame (typed)

/// One server-sent-event frame as a VALUE — event name and data stay typed
/// until the wire format is derived. No call site concatenates strings; the
/// `Codable` payload is the same `SweepReport` the JSONL sink writes.
public struct SSEFrame: Sendable, Equatable {
    public enum Event: String, Sendable {
        case sweep
    }

    public let event: Event
    public let json: String

    public init(event: Event, json: String) {
        self.event = event
        self.json = json
    }

    /// Encode one report as one frame.
    public init(report: SweepReport) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(report)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw SSEFrameError.encodingFailed
        }
        self.event = .sweep
        self.json = json
    }

    /// The wire format — derived, single source. SSE lines cannot contain
    /// raw newlines; JSON encoding guarantees none.
    public var wire: String { "event: \(event.rawValue)\ndata: \(json)\n\n" }
}

public enum SSEFrameError: Error, Sendable {
    case encodingFailed
}

// MARK: - Sweep-event broadcast (the SSE seam)

/// Broadcasts sweep reports to any number of async subscribers.
///
/// Doubles as a `TelemetrySink`, so production wiring is one line:
/// `CompositeTelemetrySink(sinks: [JSONLTelemetrySink(), broadcaster])`.
public actor GuardianEventBroadcaster: TelemetrySink {

    /// Per-subscriber buffer depth. Bounded on purpose: slow consumers drop
    /// the oldest reports rather than backpressure the reaper — telemetry
    /// must never delay a kill decision. 64 ≈ a full day at the 15-min
    /// LaunchAgent cadence, or a busy hour of interactive sweeps.
    public static let bufferDepth = 64

    /// One subscription's handle — cancels itself when dropped.
    public struct Subscription: Sendable {
        public let id: UUID
        fileprivate let continuation: AsyncStream<SweepReport>.Continuation
        public let stream: AsyncStream<SweepReport>
    }

    private var continuations: [UUID: AsyncStream<SweepReport>.Continuation] = [:]

    public init() {}

    /// Number of live subscribers (observability surface — instance state:
    /// each broadcaster owns its own subscriber set).
    public var subscriberCount: Int { continuations.count }

    /// Subscribe to future sweep reports. The stream ends when the
    /// continuation is released (subscriber cancelled) — unsubscribe by
    /// dropping the task consuming it.
    public func subscribe() -> AsyncStream<SweepReport> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(Self.bufferDepth)) { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    /// Chained consumption: hand a handler, get a cancellable task.
    /// `.subscribe { report in … }` — Combine/Rx-flavored sugar over the
    /// same AsyncStream primitive (the stream stays the primitive; this is
    /// the ergonomic front door).
    @discardableResult
    public func subscribe(_ handler: @escaping @Sendable (SweepReport) -> Void) -> Task<Void, Never> {
        Task {
            for await report in subscribe() {
                handler(report)
            }
        }
    }

    /// TelemetrySink conformance: fan one report out to every subscriber —
    /// a pure reduction over the continuation table, no accumulated state.
    public func record(_ report: SweepReport) {
        continuations.values.forEach { $0.yield(report) }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}

// MARK: - SSE mapping

extension GuardianEventBroadcaster {

    /// Map a report stream to an SSE frame stream — the name says map, the
    /// implementation is one. Ready to hand to an HTTP body writer.
    public static func mapToSSEFrames(
        _ reports: AsyncStream<SweepReport>
    ) -> AsyncThrowingStream<SSEFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await report in reports {
                        continuation.yield(try SSEFrame(report: report))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
