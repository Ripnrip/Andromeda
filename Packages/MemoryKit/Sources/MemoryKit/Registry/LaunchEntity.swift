/**
 * 🎭 The LaunchEntity - The Visible Daemon Roster
 *
 * "What once lurked as silent launchd spirits behind the curtain
 * now steps into the spotlight with a name, a schedule, and a host.
 * No more orphaned watchdogs humming unpaid soliloquies in the dark."
 *
 * - The Spellbinding Museum Director of Fleet Observability
 */

import Foundation

// MARK: - Kind / Status / Host

/// 🌟 What sort of launchd creature is this — cron, watchdog, KeepAlive service, or tunnel?
public enum LaunchEntityKind: String, Sendable, Codable, CaseIterable, Equatable {
    case cron
    case watchdog
    case service
    case tunnel
}

/// 🌟 Runtime posture as seen from Andromeda's Observe spine.
/// Satellite honesty: hub-only jobs report `notApplicable` off-hub — never fake red.
public enum LaunchEntityStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case running
    case stopped
    /// Hub-only entity observed on a satellite / isolated lane — honest absence, not failure.
    case notApplicable = "n/a"
}

/// 🌟 Which machine lane owns this entity in the hive map.
public enum HostRole: String, Sendable, Codable, CaseIterable, Equatable {
    /// Studio Phase-2 hub (Letta / Ladybug / index-server / retro).
    case hub
    /// Book / iPhone / iMac satellites — recall + contribute; hub checks stay n/a.
    case satellite
    /// Mac Mini (and similar) — isolated lane; never hive Letta/Ladybug here.
    case isolated
}

// MARK: - Schedule

/// 🌟 Human-readable launchd timing — calendar, interval, KeepAlive, or ops-template-only.
public enum LaunchSchedule: Sendable, Codable, Equatable {
    /// `StartCalendarInterval` — weekday nil means every day (0=Sun … 6=Sat when set).
    case calendar(hour: Int, minute: Int, weekday: Int?)
    /// `StartInterval` in seconds.
    case interval(seconds: Int)
    /// `KeepAlive` / RunAtLoad long-lived process.
    case keepAlive
    /// Present in ops/ catalog but not loaded as a live agent.
    case opsTemplateOnly
    case unknown

    /// 🎨 A short stage note for console / n8n labels.
    public var displaySummary: String {
        switch self {
        case let .calendar(hour, minute, weekday):
            let time = String(format: "%02d:%02d", hour, minute)
            if let weekday {
                let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let day = names.indices.contains(weekday) ? names[weekday] : "d\(weekday)"
                return "\(day) \(time)"
            }
            return "daily \(time)"
        case let .interval(seconds):
            if seconds >= 3600, seconds % 3600 == 0 {
                return "every \(seconds / 3600)h"
            }
            if seconds >= 60, seconds % 60 == 0 {
                return "every \(seconds / 60)m"
            }
            return "every \(seconds)s"
        case .keepAlive:
            return "KeepAlive"
        case .opsTemplateOnly:
            return "ops template (not installed)"
        case .unknown:
            return "unknown"
        }
    }
}

// MARK: - Observation snapshot

/// 🌟 Read-only glimpse from launchctl — never a kickstart wand.
public struct LaunchObservation: Sendable, Equatable {
    public let isLoaded: Bool
    public let isRunning: Bool
    public let pid: Int?
    /// 🧾 `LastExitStatus` from `launchctl list` when present (nil = unknown / unloaded parse).
    public let lastExitStatus: Int?

    public init(
        isLoaded: Bool,
        isRunning: Bool,
        pid: Int? = nil,
        lastExitStatus: Int? = nil
    ) {
        self.isLoaded = isLoaded
        self.isRunning = isRunning
        self.pid = pid
        self.lastExitStatus = lastExitStatus
    }

    /// ✨ Map raw launchctl facts into a console status (caller applies host-role n/a).
    public var inferredStatus: LaunchEntityStatus {
        if isRunning { return .running }
        if isLoaded { return .stopped }
        return .stopped
    }

    /// 💥 Non-zero last exit — cron/watchdog yellow signal even when idle.
    public var exitedNonZero: Bool {
        guard let lastExitStatus else { return false }
        return lastExitStatus != 0
    }

    /**
     * 🧾 Parse NeXTSTEP-ish stdout from `launchctl list <label>`.
     *
     * Loaded agents always yield an observation (`isLoaded == true`).
     * Running = PID present. Unloaded labels never reach this parser
     * (caller returns nil when launchctl exits non-zero).
     */
    public static func parse(launchctlListOutput text: String) -> LaunchObservation {
        let pid = extractInt(key: "PID", from: text)
        let lastExit = extractInt(key: "LastExitStatus", from: text)
        return LaunchObservation(
            isLoaded: true,
            isRunning: pid != nil,
            pid: pid,
            lastExitStatus: lastExit
        )
    }

    /// 🧮 Pull an integer value for a NeXTSTEP dict key, e.g. `"PID" = 1234;`.
    public static func extractInt(key: String, from text: String) -> Int? {
        let pattern = "\"\(key)\"\\s*=\\s*(-?\\d+)\\s*;"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges >= 2,
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[range])
    }
}

// MARK: - Attention (why yellow / red)

/// 🌟 Operator-facing attention beyond bare running/stopped — cron idle is OK.
public enum LaunchEntityAttention: String, Sendable, Codable, CaseIterable, Equatable {
    /// 💚 Healthy running service, or healthy idle cron (exit 0 / no health fail).
    case ok
    /// 🌙 Expected idle posture (loaded cron/watchdog between runs).
    case idle
    /// ⚠️ Soft fail — non-zero exit or yellow health join.
    case degraded
    /// 🔴 Hard fail — KeepAlive down, correlated health check failing, or live probe red.
    case critical
    /// 🛰️ Honest skip off-hub.
    case notApplicable = "n/a"
}

// MARK: - Entity

/**
 * 🎭 LaunchEntity — one LaunchAgent / cron / watchdog as a first-class Swift citizen.
 *
 * Stable slug + kind + plist home + schedule + status + host role.
 * Mutations (kickstart/bootstrap) stay out of scope for BIN-26 — Observe first.
 */
public struct LaunchEntity: Sendable, Equatable, Identifiable, Codable {
    public var id: String { slug }

    /// Stable catalog id (e.g. `job.nightly`, `river.dreamcatcher`).
    public let slug: String
    /// launchd Label (e.g. `com.multibrain.nightly`).
    public let label: String
    public let kind: LaunchEntityKind
    /// Expected plist path (repo `ops/` and/or `~/Library/LaunchAgents/`).
    public let plistPath: String
    public let schedule: LaunchSchedule
    public var status: LaunchEntityStatus
    public let hostRole: HostRole
    /// Short purpose for the console roster (no silent watchdogs).
    public let purpose: String
    /// When true, entity lives in ops/ only — not expected under LaunchAgents yet.
    public let isOpsOnly: Bool

    public init(
        slug: String,
        label: String,
        kind: LaunchEntityKind,
        plistPath: String,
        schedule: LaunchSchedule,
        status: LaunchEntityStatus = .stopped,
        hostRole: HostRole,
        purpose: String,
        isOpsOnly: Bool = false
    ) {
        self.slug = slug
        self.label = label
        self.kind = kind
        self.plistPath = plistPath
        self.schedule = schedule
        self.status = status
        self.hostRole = hostRole
        self.purpose = purpose
        self.isOpsOnly = isOpsOnly
    }
}
