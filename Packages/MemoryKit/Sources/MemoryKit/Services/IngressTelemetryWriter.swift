import Foundation

/// Wraps a `LettaMemoryWriting` backend and emits a span plus a sealed event
/// for every write. The receipt only returns after the backend's commit and
/// verify legs, so a successful event means both happened — this wrapper does
/// not invent a separate verify timestamp it cannot observe.
///
/// Attributes stay free of fact bodies and titles. Failures carry an error
/// code, never git stderr (which can echo file contents).
public actor IngressTelemetryWriter: LettaMemoryWriting {
    /// Span and event name on the fleet telemetry stream.
    public static let eventName = "memory.ingress.write"

    private let writer: any LettaMemoryWriting
    private let telemetry: any TelemetryClient

    /// - Parameters:
    ///   - writer: The ingress backend (git-backed in production).
    ///   - telemetry: Sink for write/commit/verify outcomes. No-op is legal in tests.
    public init(writer: any LettaMemoryWriting, telemetry: any TelemetryClient) {
        self.writer = writer
        self.telemetry = telemetry
    }

    /// Writes the fact, then records outcome `committed`, `unchanged`, or `failed`.
    public func write(_ fact: LettaMemoryFact, to agentID: String) async throws -> LettaMemoryReceipt {
        let span = await telemetry.startSpan(
            Self.eventName,
            attributes: [
                "agent_id": agentID,
                "visibility": fact.visibility.rawValue,
                "phase": "write",
            ]
        )
        do {
            let receipt = try await writer.write(fact, to: agentID)
            let outcome = receipt.unchanged ? "unchanged" : "committed"
            // IDs + outcome only — never relative_path, source, slug, body, or git stderr.
            await telemetry.endSpan(
                span,
                status: .ok,
                attributes: [
                    "phase": "sealed",
                    "outcome": outcome,
                    "unchanged": receipt.unchanged ? "true" : "false",
                ]
            )
            await telemetry.emit(
                TelemetryEvent(
                    name: Self.eventName,
                    attributes: [
                        "agent_id": agentID,
                        "visibility": fact.visibility.rawValue,
                        "phase": "sealed",
                        "outcome": outcome,
                        "span.id": span.spanId,
                    ],
                    spanId: span.spanId,
                    status: .ok
                )
            )
            return receipt
        } catch {
            let code = Self.errorCode(error)
            await telemetry.endSpan(
                span,
                status: .error,
                attributes: [
                    "phase": "failed",
                    "outcome": "failed",
                    "error_code": code,
                ]
            )
            await telemetry.emit(
                TelemetryEvent(
                    name: Self.eventName,
                    attributes: [
                        "agent_id": agentID,
                        "phase": "failed",
                        "outcome": "failed",
                        "error_code": code,
                        "span.id": span.spanId,
                    ],
                    spanId: span.spanId,
                    status: .error
                )
            )
            throw error
        }
    }

    /// Maps ingress failures to a stable code. Unknown errors stay `unknown`
    /// so stderr and fact text never land in the telemetry attributes.
    private static func errorCode(_ error: Error) -> String {
        guard let ingress = error as? LettaIngressError else { return "unknown" }
        switch ingress {
        case .memfsMissing: return "memfs_missing"
        case .emptyTitle: return "empty_title"
        case .emptyBody: return "empty_body"
        case .slugInvalid: return "slug_invalid"
        case .gitFailed: return "git_failed"
        case .verificationFailed: return "verification_failed"
        case .titleUnsafeForFrontmatter: return "title_unsafe"
        case .agentIDInvalid: return "agent_id_invalid"
        }
    }
}
