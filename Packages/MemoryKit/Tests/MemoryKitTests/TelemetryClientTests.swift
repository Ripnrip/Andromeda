/**
 * 🎭 The TelemetryClientTests - Observatory Calibration Rituals
 *
 * "We scribble sparks into JSONL, then read them back like tea leaves —
 * proving the diary exists even when the collector is offstage napping."
 *
 * - The Spellbinding Museum Director of Telemetry Verification
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🔭 Observability Spine / TelemetryClient (day-1)")
struct TelemetryClientTests {

    /// 💎 FileJSONL round-trip — emit N events, file exists, decode matches.
    @Test("💎 FileJSONL round-trip writes and reads N events")
    func fileJSONLRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memorykit-telemetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let client = FileJSONLTelemetryClient(directory: dir, fileName: "proof.jsonl")
        let count = 5
        for i in 0..<count {
            await client.emit(
                TelemetryEvent(
                    name: "proof.tick",
                    attributes: ["i": String(i), "suite": "observability-spine"]
                )
            )
        }

        #expect(FileManager.default.fileExists(atPath: client.fileURL.path))
        let events = try client.readAllEvents()
        #expect(events.count == count)
        #expect(events.allSatisfy { $0.name == "proof.tick" })
        #expect(events.map { $0.attributes["i"] } == ["0", "1", "2", "3", "4"])
    }

    /// 🌟 Span start/end land as two JSONL records with shared span id.
    @Test("🌟 FileJSONL span lifecycle shares span id")
    func fileJSONLSpanLifecycle() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memorykit-span-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let client = FileJSONLTelemetryClient(directory: dir)
        let handle = await client.startSpan("registry.scan", attributes: ["registry.kind": "mcp"])
        await client.endSpan(handle, status: .ok, attributes: ["mcp.duplicate_count": "0"])

        let events = try client.readAllEvents()
        #expect(events.count == 2)
        #expect(events[0].kind == .spanStart)
        #expect(events[1].kind == .spanEnd)
        #expect(events[0].spanId == handle.spanId)
        #expect(events[1].spanId == handle.spanId)
        #expect(events[1].status == .ok)
        #expect(events[1].attributes["mcp.duplicate_count"] == "0")
    }

    /// 🌐 OTLP stub posts JSON — mocked transport, no live collector required.
    @Test("🌐 OTLPHTTPExporter posts mocked OTLP payload")
    func otlpHTTPExporterMocked() async throws {
        final class Box: @unchecked Sendable {
            var bodies: [Data] = []
            var urls: [URL] = []
        }
        let box = Box()
        let exporter = OTLPHTTPExporter(
            endpoint: URL(string: "http://127.0.0.1:4318/v1/traces")!,
            postHandler: { url, data in
                box.urls.append(url)
                box.bodies.append(data)
                return (200, Data("{}".utf8))
            }
        )

        let handle = await exporter.startSpan("health.snapshot.load", attributes: [
            "health.status": "green"
        ])
        await exporter.endSpan(
            handle,
            status: TelemetrySpanStatus.ok,
            attributes: ["health.age_seconds": "12"]
        )

        #expect(box.bodies.count == 1)
        #expect(box.urls.first?.path == "/v1/traces")

        let json = try JSONSerialization.jsonObject(with: box.bodies[0]) as? [String: Any]
        let resourceSpans = json?["resourceSpans"] as? [[String: Any]]
        #expect(resourceSpans?.count == 1)

        let scopeSpans = resourceSpans?.first?["scopeSpans"] as? [[String: Any]]
        let spans = scopeSpans?.first?["spans"] as? [[String: Any]]
        #expect(spans?.first?["name"] as? String == "health.snapshot.load")
    }

    /// 🩺 HealthSnapshotLoader emits via TelemetryHub into FileJSONL.
    @Test("🩺 HealthSnapshotLoader emits health.snapshot.load event")
    func healthLoaderEmitsTelemetry() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memorykit-health-tel-\(UUID().uuidString)", isDirectory: true)
        defer {
            TelemetryHub.install(nil)
            try? FileManager.default.removeItem(at: dir)
        }

        let fileClient = FileJSONLTelemetryClient(directory: dir, fileName: "health-load.jsonl")
        TelemetryHub.install(fileClient)

        let json = """
        {"status":"green","checked_at":"2026-07-15T12:00:00Z","checks":{"vault_dir":{"ok":true}},"baselines":{}}
        """
        let snapshot = HealthSnapshotLoader.load(json: json)
        #expect(snapshot.status == .green)

        // ⏳ Fire-and-forget Task — give the hub a beat to flush.
        try await Task.sleep(nanoseconds: 200_000_000)

        let events = try fileClient.readAllEvents()
        #expect(!events.isEmpty)
        #expect(events.contains { $0.name == "health.snapshot.load" })
    }
}
