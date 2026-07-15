/**
 * 🎭 The LaunchEntityRefreshTelemetry - Day-One Roster Pulse
 *
 * "Every refresh of the launchd playbill stamps a ticket:
 * how many agents bow running, how many sleep stopped,
 * how many satellites whisper n/a — and whether the Mini
 * tunnel still lurks in its isolated wings."
 *
 * - The Cosmic Observability Maestro of Andromeda Observe
 */

import Foundation

// MARK: - Event

/**
 * 🌟 Crystallized counts emitted after `LaunchEntityRegistry.refresh`.
 *
 * Day-1 Observe telemetry — no kickstart, no spend, just honest tallies
 * so the console (and future n8n) can never pretend the roster is empty.
 */
public struct LaunchEntityRefreshTelemetry: Sendable, Equatable, Codable {
    /// 🛰️ Host role the registry was observing from.
    public let observingHostRole: HostRole
    /// 📜 Total entities in the refreshed roster.
    public let total: Int
    /// 🟢 Count of `.running`
    public let running: Int
    /// 🌙 Count of `.stopped`
    public let stopped: Int
    /// 🛰️ Count of `.notApplicable` (honest satellite skips)
    public let notApplicable: Int
    /// 🧊 True when at least one `hostRole == .isolated` entity is present (Mini lane).
    public let isolatedMiniFlagged: Bool
    /// 🧊 How many isolated-lane entities appear in the roster.
    public let isolatedCount: Int

    public init(
        observingHostRole: HostRole,
        total: Int,
        running: Int,
        stopped: Int,
        notApplicable: Int,
        isolatedMiniFlagged: Bool,
        isolatedCount: Int
    ) {
        self.observingHostRole = observingHostRole
        self.total = total
        self.running = running
        self.stopped = stopped
        self.notApplicable = notApplicable
        self.isolatedMiniFlagged = isolatedMiniFlagged
        self.isolatedCount = isolatedCount
    }

    /// 🧮 Summarize a refreshed entity list into day-1 telemetry.
    public static func summarize(
        entities: [LaunchEntity],
        observingHostRole: HostRole
    ) -> LaunchEntityRefreshTelemetry {
        var running = 0
        var stopped = 0
        var notApplicable = 0
        for entity in entities {
            switch entity.status {
            case .running: running += 1
            case .stopped: stopped += 1
            case .notApplicable: notApplicable += 1
            }
        }
        let isolated = entities.filter { $0.hostRole == .isolated }
        return LaunchEntityRefreshTelemetry(
            observingHostRole: observingHostRole,
            total: entities.count,
            running: running,
            stopped: stopped,
            notApplicable: notApplicable,
            isolatedMiniFlagged: !isolated.isEmpty,
            isolatedCount: isolated.count
        )
    }

    /// 🎨 Compact stage note for console footers / logs.
    public var displaySummary: String {
        var parts = [
            "total=\(total)",
            "running=\(running)",
            "stopped=\(stopped)",
            "n/a=\(notApplicable)",
        ]
        if isolatedMiniFlagged {
            parts.append("isolatedMini=flagged(\(isolatedCount))")
        } else {
            parts.append("isolatedMini=absent")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sink

/// 🌟 Injectable telemetry sink — production logs; tests record.
public protocol LaunchEntityTelemetrySinking: Sendable {
    func emit(_ event: LaunchEntityRefreshTelemetry)
}

/// 🌙 Silent sink — hermetic tests that only care about status resolution.
public struct NullLaunchEntityTelemetrySink: LaunchEntityTelemetrySinking {
    public init() {}

    public func emit(_ event: LaunchEntityRefreshTelemetry) {
        _ = event
    }
}

/// 📜 Print sink — day-1 console / LaunchAgent visibility breadcrumb.
public struct PrintingLaunchEntityTelemetrySink: LaunchEntityTelemetrySinking {
    public init() {}

    public func emit(_ event: LaunchEntityRefreshTelemetry) {
        print("🌐 ✨ LAUNCH ENTITY REFRESH TELEMETRY! \(event.displaySummary)")
        if event.isolatedMiniFlagged {
            print("🧊 ⚠️ Isolated Mini lane flagged — non-hive, do not color hive health")
        }
    }
}

/**
 * 🧪 Recording sink for Swift Testing — captures every refresh pulse.
 *
 * Uses a lock so concurrent refresh calls in tests stay coherent.
 * Not an actor — keeps `LaunchEntityRegistry` value-type friendly. 🎪
 */
public final class RecordingLaunchEntityTelemetrySink: LaunchEntityTelemetrySinking, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [LaunchEntityRefreshTelemetry] = []

    public init() {}

    public func emit(_ event: LaunchEntityRefreshTelemetry) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    /// 💎 Snapshot of all emitted events (oldest → newest).
    public var events: [LaunchEntityRefreshTelemetry] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    /// 🌟 Most recent emission, if any.
    public var lastEvent: LaunchEntityRefreshTelemetry? {
        events.last
    }

    /// 🧹 Clear the scroll for a fresh act.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _events.removeAll()
    }
}
