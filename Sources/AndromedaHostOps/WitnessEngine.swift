import Foundation

// MARK: - Check result

/// The outcome of a single witness check cycle for one target.
public struct WitnessCheckResult: Sendable, Equatable {
    public let targetLabel: String
    public let previousStatus: WitnessHealthStatus
    public let currentStatus: WitnessHealthStatus
    public let transition: WitnessTransitionEvent?
    public let probeReason: String
    public let consecutiveFailures: Int
    public let notified: Bool

    public var didTransition: Bool { transition != nil }
}

// MARK: - Witness engine

/// The core state machine for the external fleet witness.
///
/// ## Transition rules
///
/// | From | Probe | Consecutive failures | To | Event | Notify |
/// |-----|-------|---------------------|-----|-------|--------|
/// | unknown | success | 0 | healthy | established | no |
/// | unknown | failure | < threshold | unknown | none | no |
/// | unknown | failure | ≥ threshold | failed | alert | yes |
/// | healthy | success | 0 | healthy | none | no |
/// | healthy | failure | < threshold | healthy | none | no |
/// | healthy | failure | ≥ threshold | failed | alert | yes |
/// | failed | success | 0 | healthy | recovery | yes |
/// | failed | failure | any | failed | none | no |
///
/// Steady-state probes (same status) never produce events or notifications.
public struct WitnessEngine: Sendable {
    private let probe: any WitnessProbing
    private let store: any WitnessStoring
    private let notifier: any WitnessNotifying
    private let dateProvider: @Sendable () -> Date

    public init(
        probe: any WitnessProbing,
        store: any WitnessStoring,
        notifier: any WitnessNotifying = NoOpWitnessNotifier(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.probe = probe
        self.store = store
        self.notifier = notifier
        self.dateProvider = dateProvider
    }

    /// Run a single check cycle for one target. Loads durable state, probes,
    /// applies transition logic, persists state, logs transitions, and
    /// notifies on alert/recovery (never on initial establishment).
    public func check(
        target: WitnessTarget,
        configuration: WitnessConfiguration
    ) async throws -> WitnessCheckResult {
        let statePath = configuration.stateFilePath(for: target)
        let logPath = configuration.logFilePath(for: target)

        // Load durable state — missing file yields fresh initial state;
        // corrupt file throws and surfaces.
        var state = try await store.loadState(targetLabel: target.label, path: statePath)
        let previousStatus = state.status

        // Probe
        let probeResult = await probe.probe(target: target)
        let now = dateProvider()

        state.lastCheckedAt = now
        state.totalChecks += 1

        // Update failure counters
        if probeResult.isSuccessful {
            state.consecutiveFailures = 0
        } else {
            state.consecutiveFailures += 1
            state.totalFailures += 1
        }

        // Determine new status and whether a transition occurred
        let transition = try await computeTransition(
            previousStatus: previousStatus,
            probeResult: probeResult,
            state: &state,
            target: target,
            configuration: configuration,
            now: now
        )

        // Queue the journal record and notification before any external I/O.
        // Atomic state persistence closes the crash window between deciding a
        // transition and recording/delivering it.
        if let transition {
            state.pendingTransitions.append(transition)
            if transition.kind != .established {
                state.pendingNotifications.append(transition)
            }
        }

        // Persist both outboxes atomically before journal or network I/O.
        try await store.saveState(state, path: statePath)

        // Flush journal entries in order. A crash after append but before queue
        // removal can duplicate a line; event UUIDs let readers deduplicate it.
        while let event = state.pendingTransitions.first {
            try await store.appendTransition(event, path: logPath)
            state.pendingTransitions.removeFirst()
            try await store.saveState(state, path: statePath)
        }

        // Deliver queued transitions in order. Stop on the first failure so a
        // later recovery cannot overtake an undelivered outage alert.
        var deliveredCount = 0
        for event in state.pendingNotifications {
            guard await notifier.notify(event: event) else { break }
            deliveredCount += 1
        }
        if deliveredCount > 0 {
            state.pendingNotifications.removeFirst(deliveredCount)
            try await store.saveState(state, path: statePath)
        }

        let notified = transition.map { event in
            event.kind != .established && !state.pendingNotifications.contains(event)
        } ?? false

        return WitnessCheckResult(
            targetLabel: target.label,
            previousStatus: previousStatus,
            currentStatus: state.status,
            transition: transition,
            probeReason: probeResult.reason,
            consecutiveFailures: state.consecutiveFailures,
            notified: notified
        )
    }

    /// Run a check cycle for all targets in the configuration.
    public func checkAll(configuration: WitnessConfiguration) async throws -> [WitnessCheckResult] {
        var results: [WitnessCheckResult] = []
        for target in configuration.targets {
            let result = try await check(target: target, configuration: configuration)
            results.append(result)
        }
        return results
    }

    // MARK: - Transition logic

    private func computeTransition(
        previousStatus: WitnessHealthStatus,
        probeResult: WitnessProbeResult,
        state: inout WitnessTargetState,
        target: WitnessTarget,
        configuration: WitnessConfiguration,
        now: Date
    ) async throws -> WitnessTransitionEvent? {
        switch previousStatus {
        case .unknown:
            if probeResult.isSuccessful {
                // unknown → healthy: establish baseline, no alert
                state.status = .healthy
                state.lastTransitionAt = now
                state.lastReason = probeResult.reason
                return WitnessTransitionEvent(
                    kind: .established,
                    targetLabel: target.label,
                    owner: configuration.owner,
                    host: configuration.host,
                    fromStatus: .unknown,
                    toStatus: .healthy,
                    reason: probeResult.reason,
                    timestamp: now,
                    consecutiveFailures: 0
                )
            } else {
                // unknown → failed only after threshold
                if state.consecutiveFailures >= configuration.failureThreshold {
                    state.status = .failed
                    state.lastTransitionAt = now
                    state.lastReason = probeResult.reason
                    return WitnessTransitionEvent(
                        kind: .alert,
                        targetLabel: target.label,
                        owner: configuration.owner,
                        host: configuration.host,
                        fromStatus: .unknown,
                        toStatus: .failed,
                        reason: probeResult.reason,
                        timestamp: now,
                        consecutiveFailures: state.consecutiveFailures
                    )
                }
                // Stay unknown, no event
                state.lastReason = probeResult.reason
                return nil
            }

        case .healthy:
            if probeResult.isSuccessful {
                // Steady state — no event
                state.lastReason = probeResult.reason
                return nil
            } else {
                // healthy → failed only after threshold
                if state.consecutiveFailures >= configuration.failureThreshold {
                    state.status = .failed
                    state.lastTransitionAt = now
                    state.lastReason = probeResult.reason
                    return WitnessTransitionEvent(
                        kind: .alert,
                        targetLabel: target.label,
                        owner: configuration.owner,
                        host: configuration.host,
                        fromStatus: .healthy,
                        toStatus: .failed,
                        reason: probeResult.reason,
                        timestamp: now,
                        consecutiveFailures: state.consecutiveFailures
                    )
                }
                // Stay healthy, no event (below threshold)
                state.lastReason = probeResult.reason
                return nil
            }

        case .failed:
            if probeResult.isSuccessful {
                // failed → healthy: recovery, one success resets
                state.status = .healthy
                state.lastTransitionAt = now
                state.lastReason = probeResult.reason
                state.totalRecoveries += 1
                return WitnessTransitionEvent(
                    kind: .recovery,
                    targetLabel: target.label,
                    owner: configuration.owner,
                    host: configuration.host,
                    fromStatus: .failed,
                    toStatus: .healthy,
                    reason: probeResult.reason,
                    timestamp: now,
                    consecutiveFailures: 0
                )
            } else {
                // Steady state failed — no event
                state.lastReason = probeResult.reason
                return nil
            }
        }
    }
}

// MARK: - Status rendering

/// Human-readable status report for `andromeda-runtime witness status`.
public struct WitnessStatusReport: Sendable, Equatable {
    public let owner: String
    public let host: String
    public let generatedAt: Date
    public let targetSummaries: [TargetSummary]

    public struct TargetSummary: Sendable, Equatable {
        public let label: String
        public let url: String
        public let status: WitnessHealthStatus
        public let consecutiveFailures: Int
        public let lastCheckedAt: Date?
        public let lastTransitionAt: Date?
        public let lastReason: String?
        public let totalChecks: Int
        public let totalFailures: Int
        public let totalRecoveries: Int
        public let pendingTransitions: Int
        public let pendingNotifications: Int
    }

    /// Renders a phone-skimmable status block.
    public func render() -> String {
        var lines: [String] = [
            "Andromeda Witness — Status",
            "Owner: \(owner)",
            "Host: \(host)",
            "Generated: \(ISO8601DateFormatter().string(from: generatedAt))",
            "",
        ]
        for summary in targetSummaries {
            let mark: String
            switch summary.status {
            case .healthy: mark = "[healthy]"
            case .failed: mark = "[FAILED]"
            case .unknown: mark = "[unknown]"
            }
            lines.append("\(mark) \(summary.label)")
            lines.append("  URL: \(summary.url)")
            lines.append("  Status: \(summary.status.rawValue)")
            lines.append("  Consecutive failures: \(summary.consecutiveFailures)")
            if let lastChecked = summary.lastCheckedAt {
                lines.append("  Last check: \(ISO8601DateFormatter().string(from: lastChecked))")
            } else {
                lines.append("  Last check: never")
            }
            if let lastTransition = summary.lastTransitionAt {
                lines.append("  Last transition: \(ISO8601DateFormatter().string(from: lastTransition))")
            }
            if let reason = summary.lastReason {
                lines.append("  Last reason: \(reason)")
            }
            lines.append("  Total checks: \(summary.totalChecks), failures: \(summary.totalFailures), recoveries: \(summary.totalRecoveries)")
            lines.append("  Pending journal entries: \(summary.pendingTransitions)")
            lines.append("  Pending notifications: \(summary.pendingNotifications)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Status reader

/// Reads durable state for all targets and produces a `WitnessStatusReport`.
public struct WitnessStatusReader: Sendable {
    private let store: any WitnessStoring
    private let dateProvider: @Sendable () -> Date

    public init(
        store: any WitnessStoring,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.dateProvider = dateProvider
    }

    public func readStatus(configuration: WitnessConfiguration) async throws -> WitnessStatusReport {
        var summaries: [WitnessStatusReport.TargetSummary] = []
        for target in configuration.targets {
            let statePath = configuration.stateFilePath(for: target)
            let state = try await store.loadState(targetLabel: target.label, path: statePath)
            summaries.append(
                WitnessStatusReport.TargetSummary(
                    label: target.label,
                    url: target.url,
                    status: state.status,
                    consecutiveFailures: state.consecutiveFailures,
                    lastCheckedAt: state.lastCheckedAt,
                    lastTransitionAt: state.lastTransitionAt,
                    lastReason: state.lastReason,
                    totalChecks: state.totalChecks,
                    totalFailures: state.totalFailures,
                    totalRecoveries: state.totalRecoveries,
                    pendingTransitions: state.pendingTransitions.count,
                    pendingNotifications: state.pendingNotifications.count
                )
            )
        }
        return WitnessStatusReport(
            owner: configuration.owner,
            host: configuration.host,
            generatedAt: dateProvider(),
            targetSummaries: summaries
        )
    }
}

// MARK: - Log reader

/// Reads recent transition events for log display.
public struct WitnessLogReader: Sendable {
    private let store: any WitnessStoring

    public init(store: any WitnessStoring) {
        self.store = store
    }

    public func readLog(
        target: WitnessTarget,
        configuration: WitnessConfiguration,
        limit: Int = 50
    ) async throws -> [WitnessTransitionEvent] {
        let logPath = configuration.logFilePath(for: target)
        return try await store.readTransitions(path: logPath, limit: limit)
    }

    /// Reads logs for all targets, merged and sorted by timestamp.
    public func readAllLogs(
        configuration: WitnessConfiguration,
        limit: Int = 50
    ) async throws -> [WitnessTransitionEvent] {
        var allEvents: [WitnessTransitionEvent] = []
        for target in configuration.targets {
            let logPath = configuration.logFilePath(for: target)
            let events = try await store.readTransitions(path: logPath, limit: limit)
            allEvents.append(contentsOf: events)
        }
        return allEvents.sorted { $0.timestamp < $1.timestamp }
    }

    /// Renders transition events as a human-readable log.
    public static func renderLog(_ events: [WitnessTransitionEvent]) -> String {
        guard !events.isEmpty else {
            return "No transition events recorded."
        }
        var lines: [String] = ["Andromeda Witness — Transition Log", ""]
        for event in events {
            let kindMark: String
            switch event.kind {
            case .established: kindMark = "ESTABLISHED"
            case .alert: kindMark = "ALERT"
            case .recovery: kindMark = "RECOVERY"
            }
            lines.append(
                "[\(ISO8601DateFormatter().string(from: event.timestamp))] \(kindMark) \(event.targetLabel): \(event.fromStatus.rawValue) → \(event.toStatus.rawValue) — \(event.reason) (failures: \(event.consecutiveFailures))"
            )
        }
        return lines.joined(separator: "\n")
    }
}
