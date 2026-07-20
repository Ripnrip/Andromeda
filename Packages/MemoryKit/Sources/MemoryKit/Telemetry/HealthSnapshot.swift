/**
 * 🎭 The HealthSnapshot - Observatory of the Fleet Pulse
 *
 * "Nine lanterns on the harbor wall — some blaze green, some flicker amber,
 * some sleep honestly as n/a on a satellite shore. We read the sky as written,
 * never paint a false dawn over a shattered glass."
 *
 * - The Spellbinding Museum Director of Observability
 */

import Foundation

// MARK: - Headline Status

/// 🌟 Fleet `health.json` headline — green / yellow / red / unknown.
///
/// Distinct from TCA `HealthStatus` (per-service connection pulse: healthy/unhealthy).
/// Named `FleetHealthStatus` so console + n8n share one vocabulary without collision.
public enum FleetHealthStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case green
    case yellow
    case red
    /// 🔮 Unreadable / corrupt / missing — never masquerades as green.
    case unknown

    /// 🎨 Decode unknown strings (and missing values) as `.unknown`, never `.green`.
    public init(rawValueOrUnknown raw: String?) {
        guard let raw, let parsed = FleetHealthStatus(rawValue: raw.lowercased()) else {
            self = .unknown
            return
        }
        self = parsed
    }
}

// MARK: - Individual Check

/**
 * 🩺 One lantern on the health wall (`checks.<name>`).
 *
 * `ok` may be `true` | `false` | `null`. When `status == "n/a"` (or `ok == nil`),
 * the check is intentionally skipped — Phase-1 satellite or feature-gated —
 * and must **not** contribute red. See `docs/DATA-CONTRACTS.md` §9.
 */
public struct HealthCheck: Sendable, Codable, Equatable {
    /// 🚦 `true` pass · `false` fail · `nil` not applicable / skipped
    public let ok: Bool?
    /// 📜 Human-readable detail from the probe
    public let detail: String?
    /// 🛰️ Explicit skip marker (`"n/a"`) when present
    public let status: String?

    public init(ok: Bool?, detail: String? = nil, status: String? = nil) {
        self.ok = ok
        self.detail = detail
        self.status = status
    }

    /// 🌙 Honest skip — satellite hub absence or gated feature; never a failure.
    public var isNotApplicable: Bool {
        if let status, status.lowercased() == "n/a" {
            return true
        }
        return ok == nil
    }

    /// 💥 Explicit failure only — literal `ok == false`. Null / n/a never fail.
    public var isFailing: Bool { ok == false }

    /// 🎯 Alias for console / alert fingerprinting — same satellite-honest rule.
    public var contributesFailure: Bool { isFailing }
}

// MARK: - Snapshot

/**
 * 🌌 Crystallized `~/.multibrain/health.json` for Andromeda console + future n8n.
 *
 * Faithful decode of DATA-CONTRACTS §9. Corrupt payloads become `.unknown`
 * via `HealthSnapshotLoader` — never a forged green.
 */
public struct HealthSnapshot: Sendable, Codable, Equatable {
    public let status: FleetHealthStatus
    public let checkedAt: Date?
    public let lastSuccess: Date?
    public let checks: [String: HealthCheck]
    public let baselines: [String: Double]

    enum CodingKeys: String, CodingKey {
        case status
        case checkedAt = "checked_at"
        case lastSuccess = "last_success"
        case checks
        case baselines
    }

    public init(
        status: FleetHealthStatus,
        checkedAt: Date? = nil,
        lastSuccess: Date? = nil,
        checks: [String: HealthCheck] = [:],
        baselines: [String: Double] = [:]
    ) {
        self.status = status
        self.checkedAt = checkedAt
        self.lastSuccess = lastSuccess
        self.checks = checks
        self.baselines = baselines
    }

    /// 🔮 The fog-of-war snapshot — used when JSON is corrupt or unreadable.
    public static let unknown = HealthSnapshot(status: .unknown)

    // MARK: Satellite-honest derived views

    /// 🛰️ Checks that are honest skips (null ok and/or status n/a).
    public var notApplicableCheckNames: [String] {
        checks
            .filter { $0.value.isNotApplicable }
            .map(\.key)
            .sorted()
    }

    /// 🚨 Names where `ok == false` — null/n/a never appear here.
    public var failingCheckNames: [String] {
        checks
            .filter { $0.value.contributesFailure }
            .map(\.key)
            .sorted()
    }

    /// 💚 True only for an explicitly green headline (never for unknown).
    public var isGreen: Bool { status == .green }

    /// 🔴 True when the headline is red/yellow **or** unknown (must not fake green).
    public var needsAttention: Bool {
        switch status {
        case .red, .yellow, .unknown: return true
        case .green: return false
        }
    }

    /**
     * 🧮 Recompute a satellite-honest rollup from checks alone.
     *
     * Only `ok == false` contributes red. Null / n/a contribute nothing
     * (they do not force red). Empty checks → unknown (never fake green).
     */
    public var derivedStatusFromChecks: FleetHealthStatus {
        guard !checks.isEmpty else { return .unknown }
        if checks.values.contains(where: { $0.contributesFailure }) {
            return .red
        }
        // ✨ All remaining are pass or n/a — harbor is clear.
        return .green
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status)
        self.status = FleetHealthStatus(rawValueOrUnknown: rawStatus)

        self.checkedAt = try Self.decodeOptionalISO8601(from: container, forKey: .checkedAt)
        self.lastSuccess = try Self.decodeOptionalISO8601(from: container, forKey: .lastSuccess)
        self.checks = try container.decodeIfPresent([String: HealthCheck].self, forKey: .checks) ?? [:]
        self.baselines = try container.decodeIfPresent([String: Double].self, forKey: .baselines) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status.rawValue, forKey: .status)
        if let checkedAt {
            try container.encode(Self.iso8601String(from: checkedAt), forKey: .checkedAt)
        }
        if let lastSuccess {
            try container.encode(Self.iso8601String(from: lastSuccess), forKey: .lastSuccess)
        } else {
            try container.encodeNil(forKey: .lastSuccess)
        }
        try container.encode(checks, forKey: .checks)
        try container.encode(baselines, forKey: .baselines)
    }

    // MARK: - ISO8601 helpers (health.json uses `YYYY-MM-DDTHH:MM:SSZ`)

    /// 🕰️ Build a fresh formatter per call — ISO8601DateFormatter is not Sendable.
    private static func makeISO8601() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func decodeOptionalISO8601(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }
        let raw = try container.decode(String.self, forKey: key)
        return makeISO8601().date(from: raw)
    }

    private static func iso8601String(from date: Date) -> String {
        makeISO8601().string(from: date)
    }
}
