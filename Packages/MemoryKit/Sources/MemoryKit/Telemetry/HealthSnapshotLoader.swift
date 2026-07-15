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
    public static func load(from url: URL = defaultHealthURL) -> HealthSnapshot {
        do {
            let mysticalData = try Data(contentsOf: url)
            return load(data: mysticalData)
        } catch {
            // 🌩️ Temporary storm on the filesystem — fog flag, not fake green.
            return .unknown
        }
    }

    /// 🧪 Decode raw bytes (fixtures, n8n payloads, in-memory probes).
    public static func load(data: Data) -> HealthSnapshot {
        guard !data.isEmpty else {
            return .unknown
        }
        do {
            return try decoder.decode(HealthSnapshot.self, from: data)
        } catch {
            // 💥 Corrupt JSON → unknown. The show must not pretend all is well.
            return .unknown
        }
    }

    /// 📜 Convenience for UTF-8 JSON strings (unit fixtures).
    public static func load(json: String) -> HealthSnapshot {
        guard let data = json.data(using: .utf8) else {
            return .unknown
        }
        return load(data: data)
    }

    /// 🎯 Strict decode for callers that want the error (tests / diagnostics).
    /// Still never invents green on failure — throws instead.
    public static func decodeStrict(data: Data) throws -> HealthSnapshot {
        try decoder.decode(HealthSnapshot.self, from: data)
    }
}
