/**
 * 🎭 The HealthSnapshotLoader - Cartographer of the Harbor Lanterns
 *
 * "We unseal the glass bottle of health.json with careful hands.
 * If the ink is smudged or the parchment torn, we raise the fog flag —
 * unknown — and refuse to paint a counterfeit sunrise."
 *
 * - The Enchanted Observability Alchemist
 */

import Foundation

/// 🌐 Loads and decodes DATA-CONTRACTS §9 `health.json` for Andromeda + n8n.
public enum HealthSnapshotLoader {

    /// 🏠 Canonical path on every host: `~/.multibrain/health.json`
    public static var defaultHealthURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".multibrain", isDirectory: true)
            .appendingPathComponent("health.json", isDirectory: false)
    }

    /// 🔮 Shared decoder — ISO8601 dates handled in `HealthSnapshot` Codable.
    private static let decoder = JSONDecoder()

    // MARK: - Public portals

    /// 📂 Read from disk. Missing / unreadable / corrupt → `.unknown` (never green).
    /// Emits `health.snapshot.load` span/event via `TelemetryHub` (fire-and-forget).
    public static func load(from url: URL = defaultHealthURL) -> HealthSnapshot {
        let started = Date()
        do {
            let mysticalData = try Data(contentsOf: url)
            let snapshot = load(data: mysticalData, emitTelemetry: false)
            emitLoadTelemetry(
                snapshot: snapshot,
                source: "file",
                started: started,
                pathLeaf: url.lastPathComponent
            )
            return snapshot
        } catch {
            // 🌩️ Temporary storm on the filesystem — fog flag, not fake green.
            let snapshot = HealthSnapshot.unknown
            emitLoadTelemetry(
                snapshot: snapshot,
                source: "file_missing",
                started: started,
                pathLeaf: url.lastPathComponent
            )
            return snapshot
        }
    }

    /// 🧪 Decode raw bytes (fixtures, n8n payloads, in-memory probes).
    public static func load(data: Data) -> HealthSnapshot {
        load(data: data, emitTelemetry: true)
    }

    /// 📜 Convenience for UTF-8 JSON strings (unit fixtures).
    public static func load(json: String) -> HealthSnapshot {
        guard let data = json.data(using: .utf8) else {
            let snapshot = HealthSnapshot.unknown
            emitLoadTelemetry(snapshot: snapshot, source: "json_empty", started: Date(), pathLeaf: nil)
            return snapshot
        }
        return load(data: data)
    }

    /// 🎯 Strict decode for callers that want the error (tests / diagnostics).
    /// Still never invents green on failure — throws instead.
    public static func decodeStrict(data: Data) throws -> HealthSnapshot {
        try decoder.decode(HealthSnapshot.self, from: data)
    }

    // MARK: - Internals

    private static func load(data: Data, emitTelemetry: Bool) -> HealthSnapshot {
        let started = Date()
        let snapshot: HealthSnapshot
        if data.isEmpty {
            snapshot = .unknown
        } else {
            do {
                snapshot = try decoder.decode(HealthSnapshot.self, from: data)
            } catch {
                // 💥 Corrupt JSON → unknown. The show must not pretend all is well.
                snapshot = .unknown
            }
        }
        if emitTelemetry {
            emitLoadTelemetry(snapshot: snapshot, source: "data", started: started, pathLeaf: nil)
        }
        return snapshot
    }

    /// ✨ Fire health.snapshot.load — never blocks Observe on a sleeping collector.
    private static func emitLoadTelemetry(
        snapshot: HealthSnapshot,
        source: String,
        started: Date,
        pathLeaf: String?
    ) {
        let ageSeconds: String = {
            guard let checkedAt = snapshot.checkedAt else { return "unknown" }
            return String(Int(Date().timeIntervalSince(checkedAt)))
        }()
        var attributes: [String: String] = [
            "health.status": snapshot.status.rawValue,
            "health.source": source,
            "health.check_count": String(snapshot.checks.count),
            "health.failing_count": String(snapshot.failingCheckNames.count),
            "health.age_seconds": ageSeconds,
            "duration_ms": String(Int(Date().timeIntervalSince(started) * 1000))
        ]
        if let pathLeaf {
            attributes["health.path_leaf"] = pathLeaf
        }
        let status: TelemetrySpanStatus = snapshot.status == .unknown ? .unset : .ok
        TelemetryHub.emitSpanSync(
            name: "health.snapshot.load",
            attributes: attributes,
            status: status
        )
    }
}
