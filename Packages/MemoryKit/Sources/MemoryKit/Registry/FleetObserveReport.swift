/**
 * 🎭 The FleetObserveReport - LaunchEntity × Health Join
 *
 * "Running is not the whole story. Nightly idle with a dead_man fail
 * is still a cracked lantern. We join launchctl facts to health.json
 * (and an optional :8286 knock) so operators see *why* yellow/red."
 *
 * - The Spellbinding Museum Director of Fleet Observability
 */

import Foundation

// MARK: - Row

/// 🌟 One catalog entity with attention + human why.
public struct FleetObserveRow: Sendable, Equatable, Identifiable {
    public var id: String { entity.slug }

    public let entity: LaunchEntity
    public let observation: LaunchObservation?
    public let attention: LaunchEntityAttention
    /// 📜 Operator-facing why (nil when attention is ok / idle / n/a).
    public let why: String?
    /// 🔗 Correlated `health.json` check names (e.g. `dead_man`, `ladybug_query`).
    public let correlatedChecks: [String]

    public init(
        entity: LaunchEntity,
        observation: LaunchObservation?,
        attention: LaunchEntityAttention,
        why: String?,
        correlatedChecks: [String]
    ) {
        self.entity = entity
        self.observation = observation
        self.attention = attention
        self.why = why
        self.correlatedChecks = correlatedChecks
    }
}

// MARK: - Report

/// 🌌 Full Observe pulse: roster rows + health headline + optional live Ladybug probe.
public struct FleetObserveReport: Sendable, Equatable {
    public let observingHostRole: HostRole
    public let health: HealthSnapshot
    public let rows: [FleetObserveRow]
    public let indexServer: IndexServerHealthResult?
    public let telemetry: LaunchEntityRefreshTelemetry?

    public init(
        observingHostRole: HostRole,
        health: HealthSnapshot,
        rows: [FleetObserveRow],
        indexServer: IndexServerHealthResult? = nil,
        telemetry: LaunchEntityRefreshTelemetry? = nil
    ) {
        self.observingHostRole = observingHostRole
        self.health = health
        self.rows = rows
        self.indexServer = indexServer
        self.telemetry = telemetry
    }

    /// 🚨 Rows that need operator eyes (degraded / critical).
    public var attentionRows: [FleetObserveRow] {
        rows.filter { $0.attention == .degraded || $0.attention == .critical }
    }

    /// 📜 Joined why lines for hive chrome (all failing attentions).
    public var failureSummaries: [String] {
        attentionRows.compactMap(\.why)
    }

    /// 🎯 Single headline for menu bar (first critical, else first degraded, else health).
    public var headlineWhy: String? {
        if let critical = attentionRows.first(where: { $0.attention == .critical })?.why {
            return critical
        }
        if let degraded = attentionRows.first(where: { $0.attention == .degraded })?.why {
            return degraded
        }
        return health.failureSummaries.first.map { "\($0.name): \($0.detail)" }
            ?? health.failingCheckNames.first
    }

    /// 🔴 True when any row is critical or health needs attention.
    public var needsAttention: Bool {
        !attentionRows.isEmpty || health.needsAttention
    }
}

// MARK: - Composer

/// 🎨 Join LaunchEntityRegistry + HealthSnapshot (+ optional live index probe).
public enum FleetObserveComposer {

    /// 🗺️ Slug → health check names that color this entity.
    public static let correlation: [String: [String]] = [
        "job.nightly": ["dead_man"],
        "svc.ladybug.serve": ["ladybug_query"],
        "svc.letta": ["letta_api"],
        "svc.letta.bridge": ["letta_api"],
        "svc.letta.shim": ["letta_api"],
    ]

    /**
     * 🌟 Compose an Observe report.
     *
     * - Uses registry statuses already refreshed (or refreshes if you pass a fresh registry).
     * - Re-peeks launchctl for lastExit / pid detail.
     * - Joins health checks; live index probe can override/augment ladybug why.
     */
    public static func compose(
        registry: LaunchEntityRegistry,
        launchctl: any LaunchctlObserving,
        health: HealthSnapshot,
        indexServer: IndexServerHealthResult? = nil
    ) -> FleetObserveReport {
        let rows: [FleetObserveRow] = registry.all().map { entity in
            let observation = launchctl.observe(label: entity.label)
            let checks = correlation[entity.slug] ?? []
            let (attention, why) = resolveAttention(
                entity: entity,
                observation: observation,
                health: health,
                correlatedChecks: checks,
                indexServer: entity.slug == "svc.ladybug.serve" ? indexServer : nil
            )
            return FleetObserveRow(
                entity: entity,
                observation: observation,
                attention: attention,
                why: why,
                correlatedChecks: checks
            )
        }

        return FleetObserveReport(
            observingHostRole: registry.observingHostRole,
            health: health,
            rows: rows,
            indexServer: indexServer,
            telemetry: registry.lastTelemetry
        )
    }

    /// 🚀 One-shot: Live launchctl + health.json (+ optional live :8286).
    public static func observeLive(
        observingHostRole: HostRole = .hub,
        health: HealthSnapshot = HealthSnapshotLoader.load(),
        launchctl: any LaunchctlObserving = LiveLaunchctlObserver(),
        indexProbe: (any IndexServerHealthProbing)? = nil
    ) -> FleetObserveReport {
        var registry = LaunchEntityRegistry(
            observingHostRole: observingHostRole,
            launchctl: launchctl
        )
        _ = registry.refresh()

        let probe: IndexServerHealthResult? = {
            if let indexProbe { return indexProbe.probe() }
            if observingHostRole == .hub {
                return IndexServerHealthClient(observingHostRole: observingHostRole).probe()
            }
            return nil
        }()

        return compose(
            registry: registry,
            launchctl: launchctl,
            health: health,
            indexServer: probe
        )
    }

    // MARK: - Attention resolution

    private static func resolveAttention(
        entity: LaunchEntity,
        observation: LaunchObservation?,
        health: HealthSnapshot,
        correlatedChecks: [String],
        indexServer: IndexServerHealthResult?
    ) -> (LaunchEntityAttention, String?) {
        if entity.status == .notApplicable {
            return (.notApplicable, nil)
        }
        if entity.isOpsOnly || entity.schedule == .opsTemplateOnly {
            return (.idle, nil)
        }

        // 🔗 Health join — explicit ok == false only.
        for name in correlatedChecks {
            if let check = health.check(name), check.isFailing {
                let detail = check.detail ?? name
                return (.critical, "\(entity.slug): \(name) — \(detail)")
            }
        }

        // 🩺 Live Ladybug probe can contradict a stale green health.json.
        if let indexServer, !indexServer.skipped, !indexServer.ok {
            return (.critical, "\(entity.slug): live /health — \(indexServer.detail)")
        }

        // 💥 Non-zero last exit while idle (cron finished red).
        // KeepAlive may retain a prior LastExitStatus after restart — ignore when PID is live.
        if let observation, observation.exitedNonZero, !observation.isRunning {
            let code = observation.lastExitStatus.map(String.init) ?? "?"
            return (.degraded, "\(entity.slug): lastExit=\(code)")
        }

        // 🔴 KeepAlive / service expected running but isn't.
        if entity.kind == .service || entity.kind == .tunnel {
            if entity.status != .running {
                return (.critical, "\(entity.slug): KeepAlive not running")
            }
            return (.ok, nil)
        }

        // 🌙 Cron / watchdog: loaded + idle between runs is healthy.
        if entity.kind == .cron || entity.kind == .watchdog {
            if entity.status == .running {
                return (.ok, nil)
            }
            if observation?.isLoaded == true {
                return (.idle, nil)
            }
            // Unloaded cron on hub is degraded (agent missing).
            if entity.hostRole == .hub {
                return (.degraded, "\(entity.slug): LaunchAgent not loaded")
            }
            return (.idle, nil)
        }

        return entity.status == .running ? (.ok, nil) : (.idle, nil)
    }
}
