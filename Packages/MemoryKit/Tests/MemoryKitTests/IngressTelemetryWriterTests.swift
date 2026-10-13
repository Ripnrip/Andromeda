import Foundation
@testable import MemoryKit
import Testing

/// Records telemetry without touching disk so ingress tests stay hermetic.
private actor RecordingTelemetry: TelemetryClient {
    private(set) var events: [TelemetryEvent] = []

    func emit(_ event: TelemetryEvent) async {
        events.append(event)
    }

    func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        let handle = TelemetrySpanHandle(name: name, attributes: attributes)
        events.append(
            TelemetryEvent(
                name: name,
                kind: .spanStart,
                attributes: attributes,
                spanId: handle.spanId
            )
        )
        return handle
    }

    func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {
        events.append(
            TelemetryEvent(
                name: handle.name,
                kind: .spanEnd,
                attributes: attributes,
                spanId: handle.spanId,
                status: status
            )
        )
    }
}

/// Stand-in backend. Records the fact so tests can prove the body never reaches telemetry.
private struct StubIngressWriter: LettaMemoryWriting {
    var receipt: LettaMemoryReceipt?
    var thrown: LettaIngressError?

    func write(_ fact: LettaMemoryFact, to agentID: String) async throws -> LettaMemoryReceipt {
        if let thrown { throw thrown }
        return receipt ?? LettaMemoryReceipt(
            agentID: agentID,
            relativePath: "system/knowledge/\(fact.slug).md",
            commitSHA: "abc123",
            contentHash: "sha256:dead",
            unchanged: false
        )
    }
}

@Suite("MemoryKit.IngressTelemetryWriter")
struct IngressTelemetryWriterTests {
    /// A sealed write must emit ok telemetry that names the path and never the body.
    @Test("committed write emits sealed outcome without the fact body")
    func committedWriteOmitsBody() async throws {
        let telemetry = RecordingTelemetry()
        let writer = IngressTelemetryWriter(
            writer: StubIngressWriter(),
            telemetry: telemetry
        )
        let fact = LettaMemoryFact(
            title: "Relay port",
            body: "secret-body-should-not-leak",
            visibility: .internal,
            source: "test"
        )
        let receipt = try await writer.write(fact, to: "agent-abc")
        #expect(receipt.relativePath == "system/knowledge/relay-port.md")

        let events = await telemetry.events
        let blob = events.map { $0.attributes.values.joined(separator: " ") }.joined(separator: " ")
        #expect(!blob.contains("secret-body-should-not-leak"))
        #expect(events.contains { $0.kind == .spanEnd && $0.status == .ok })
        #expect(events.contains { $0.attributes["outcome"] == "committed" })
        #expect(events.contains { $0.attributes["phase"] == "sealed" })
    }

    /// Idempotent rewrites stay observable instead of looking like silence.
    @Test("unchanged receipt is an explicit unchanged outcome")
    func unchangedIsExplicit() async throws {
        let telemetry = RecordingTelemetry()
        let writer = IngressTelemetryWriter(
            writer: StubIngressWriter(
                receipt: LettaMemoryReceipt(
                    agentID: "agent-abc",
                    relativePath: "system/knowledge/relay-port.md",
                    commitSHA: "abc123",
                    contentHash: "sha256:dead",
                    unchanged: true
                )
            ),
            telemetry: telemetry
        )
        _ = try await writer.write(
            LettaMemoryFact(title: "Relay port", body: "same", visibility: .private, source: "test"),
            to: "agent-abc"
        )
        let events = await telemetry.events
        #expect(events.contains { $0.attributes["outcome"] == "unchanged" })
        #expect(!events.contains { $0.status == .error })
    }

    /// Failures emit an error code, not git stderr.
    @Test("git failure telemetry carries error_code and not stderr")
    func failureCodeOmitsStderr() async throws {
        let telemetry = RecordingTelemetry()
        let writer = IngressTelemetryWriter(
            writer: StubIngressWriter(thrown: .gitFailed(step: "commit", stderr: "secret-stderr-blob")),
            telemetry: telemetry
        )
        await #expect(throws: LettaIngressError.self) {
            try await writer.write(
                LettaMemoryFact(title: "Nope", body: "x", visibility: .internal, source: "test"),
                to: "agent-abc"
            )
        }
        let events = await telemetry.events
        let blob = events.map { $0.attributes.values.joined(separator: " ") }.joined(separator: " ")
        #expect(!blob.contains("secret-stderr-blob"))
        #expect(events.contains { $0.attributes["error_code"] == "git_failed" })
        #expect(events.contains { $0.status == .error })
    }

    /// The hosted roster entry must not pretend to be a LaunchAgent.
    @Test("hosted ingress entity is not a LaunchAgent plist")
    func hostedEntityIsNotLaunchd() {
        let entity = LaunchEntity.hostedMemoryIngress()
        #expect(entity.label == "com.andromeda.memory-ingress")
        #expect(entity.plistPath == "hosted:andromeda-runtime")
        #expect(!entity.plistPath.contains("LaunchAgents"))
        #expect(entity.isOpsOnly)
        #expect(entity.kind == .service)
    }
}
