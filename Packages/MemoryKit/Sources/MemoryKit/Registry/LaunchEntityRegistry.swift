/**
 * 🎭 The LaunchEntityRegistry - The Fleet Roster Curator
 *
 * "We pin every multibrain LaunchAgent to the playbill —
 * hub KeepAlives, satellite cron, and the isolated Mini tunnel —
 * then peek at launchctl with polite eyes, never a kickstart dagger."
 *
 * - The Cosmic Process Orchestrator of Andromeda Observe
 */

import Foundation

// MARK: - launchctl observer (read-only)

/// 🌟 Injectable launchctl peek — production wraps `launchctl print`; tests mock.
public protocol LaunchctlObserving: Sendable {
    /// Return nil when the observer cannot speak for this label (unknown / error).
    func observe(label: String) -> LaunchObservation?
}

/// 🌙 Default observer that refuses live launchctl — keeps unit tests hermetic.
/// Wire a real adapter at the Andromeda console boundary later.
public struct NullLaunchctlObserver: LaunchctlObserving {
    public init() {}

    public func observe(label: String) -> LaunchObservation? {
        _ = label
        return nil
    }
}

/// 🧪 In-memory mock for Swift Testing — no destructive kickstart, ever.
public struct MockLaunchctlObserver: LaunchctlObserving {
    private let observations: [String: LaunchObservation]

    public init(observations: [String: LaunchObservation] = [:]) {
        self.observations = observations
    }

    public func observe(label: String) -> LaunchObservation? {
        observations[label]
    }
}

// MARK: - Registry

/**
 * 🎭 LaunchEntityRegistry — seed the known `com.multibrain.*` catalog,
 * observe statuses read-only, and keep Mac Mini tunnel marked isolated / non-hive.
 */
public struct LaunchEntityRegistry: Sendable {
    /// Machine role we are observing from (affects hub-only → n/a on satellites).
    public let observingHostRole: HostRole
    private let launchctl: any LaunchctlObserving
    private let telemetry: any LaunchEntityTelemetrySinking
    private var seeded: [LaunchEntity]

    /// 🌟 Last telemetry pulse from `refresh()` — nil until the first refresh.
    public private(set) var lastTelemetry: LaunchEntityRefreshTelemetry?

    /// 🌟 The Grand Ignition — catalog seeds + optional mock launchctl + telemetry sink.
    public init(
        observingHostRole: HostRole = .hub,
        launchctl: any LaunchctlObserving = NullLaunchctlObserver(),
        telemetry: any LaunchEntityTelemetrySinking = NullLaunchEntityTelemetrySink(),
        entities: [LaunchEntity]? = nil
    ) {
        self.observingHostRole = observingHostRole
        self.launchctl = launchctl
        self.telemetry = telemetry
        self.seeded = entities ?? Self.catalogSeeds()
        self.lastTelemetry = nil
    }

    // MARK: Catalog

    /// 📜 Canonical seed list from ANDROMEDA-SURFACE-AREA §G + Mini isolated lane.
    public static func catalogSeeds(
        launchAgentsDirectory: String = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath,
        opsDirectory: String = "/Users/admin/Developer/multibrain/ops"
    ) -> [LaunchEntity] {
        let live: (String) -> String = { label in
            "\(launchAgentsDirectory)/\(label).plist"
        }
        let ops: (String) -> String = { label in
            "\(opsDirectory)/\(label).plist"
        }

        return [
            LaunchEntity(
                slug: "job.nightly",
                label: "com.multibrain.nightly",
                kind: .cron,
                plistPath: live("com.multibrain.nightly"),
                schedule: .calendar(hour: 2, minute: 30, weekday: nil),
                hostRole: .hub,
                purpose: "Dream batch — consolidate.py via run-nightly.sh"
            ),
            LaunchEntity(
                slug: "job.health",
                label: "com.multibrain.health",
                kind: .cron,
                plistPath: live("com.multibrain.health"),
                schedule: .interval(seconds: 3600),
                hostRole: .hub,
                purpose: "Hourly healthcheck + Telegram alert gate"
            ),
            LaunchEntity(
                slug: "svc.letta",
                label: "com.multibrain.letta",
                kind: .service,
                plistPath: live("com.multibrain.letta"),
                schedule: .keepAlive,
                hostRole: .hub,
                purpose: "Letta Librarian API :8283 (Studio hub only)"
            ),
            LaunchEntity(
                slug: "svc.letta.bridge",
                label: "com.multibrain.letta-bridge",
                kind: .service,
                plistPath: live("com.multibrain.letta-bridge"),
                schedule: .keepAlive,
                hostRole: .hub,
                purpose: "Letta bridge :8284"
            ),
            LaunchEntity(
                slug: "svc.letta.shim",
                label: "com.multibrain.letta-shim",
                kind: .service,
                plistPath: live("com.multibrain.letta-shim"),
                schedule: .keepAlive,
                hostRole: .hub,
                purpose: "Letta z.ai Anthropic shim :8285"
            ),
            LaunchEntity(
                slug: "svc.ladybug.serve",
                label: "com.multibrain.index-server",
                kind: .service,
                plistPath: live("com.multibrain.index-server"),
                schedule: .keepAlive,
                hostRole: .hub,
                purpose: "Ladybug index-server :8286"
            ),
            LaunchEntity(
                slug: "river.claude-mem.worker",
                label: "com.multibrain.claude-mem-worker",
                kind: .watchdog,
                plistPath: live("com.multibrain.claude-mem-worker"),
                schedule: .interval(seconds: 60),
                hostRole: .hub,
                purpose: "Capture river ensure-worker (no silent watchdog)"
            ),
            LaunchEntity(
                slug: "river.dreamcatcher",
                label: "com.multibrain.dreamcatcher",
                kind: .watchdog,
                plistPath: live("com.multibrain.dreamcatcher"),
                schedule: .interval(seconds: 1800),
                hostRole: .hub,
                purpose: "Idle-session dream census every 30m (Haiku spend gate)"
            ),
            LaunchEntity(
                slug: "job.weekly_retro",
                label: "com.multibrain.retro",
                kind: .cron,
                plistPath: ops("com.multibrain.retro"),
                schedule: .opsTemplateOnly,
                status: .stopped,
                hostRole: .hub,
                purpose: "Weekly retro Mon 08:00 — ops template, not installed",
                isOpsOnly: true
            ),
            // 🛰️ Isolated lane — do NOT hive. Mac Mini VNC tunnel stays off the hive mind.
            LaunchEntity(
                slug: "tunnel.mac-mini-vnc",
                label: "com.local.mac-mini-vnc-tunnel",
                kind: .tunnel,
                plistPath: live("com.local.mac-mini-vnc-tunnel"),
                schedule: .keepAlive,
                hostRole: .isolated,
                purpose: "Mac Mini VNC tunnel — isolated / non-hive"
            ),
        ]
    }

    // MARK: Query

    /// 🌟 Full roster as last observed / seeded.
    public func all() -> [LaunchEntity] {
        seeded
    }

    /// 🔍 Lookup by stable slug.
    public func entity(slug: String) -> LaunchEntity? {
        seeded.first { $0.slug == slug }
    }

    /// 🔍 Lookup by launchd label.
    public func entity(label: String) -> LaunchEntity? {
        seeded.first { $0.label == label }
    }

    /// 🐝 Hive-facing entities (hub + satellite) — excludes isolated Mini lane.
    public func hiveEntities() -> [LaunchEntity] {
        seeded.filter { $0.hostRole != .isolated }
    }

    /// 🧊 Isolated / non-hive entities (Mac Mini tunnel et al.).
    public func isolatedEntities() -> [LaunchEntity] {
        seeded.filter { $0.hostRole == .isolated }
    }

    /// 📜 Known `com.multibrain.*` labels only (excludes adjacent tunnels).
    public func multibrainEntities() -> [LaunchEntity] {
        seeded.filter { $0.label.hasPrefix("com.multibrain.") }
    }

    // MARK: Observe

    /**
     * 👁️ Refresh statuses from the injected launchctl observer (no telemetry).
     *
     * Rules:
     * - Ops-only templates stay stopped (never pretend running).
     * - Hub-owned services observed from satellite/isolated → `.notApplicable`.
     * - Missing observation → stopped (or n/a when host role forbids the job).
     * - Never kickstarts, bootstraps, or unloads.
     */
    public mutating func refreshStatuses() {
        seeded = seeded.map { entity in
            var updated = entity
            updated.status = resolveStatus(for: entity)
            return updated
        }
    }

    /**
     * 🌐 Day-1 Observe refresh — statuses + telemetry pulse.
     *
     * Emits counts by status and flags the isolated Mini lane when present.
     * Prefer this over `refreshStatuses` at console / health boundaries.
     */
    @discardableResult
    public mutating func refresh() -> LaunchEntityRefreshTelemetry {
        refreshStatuses()
        let pulse = LaunchEntityRefreshTelemetry.summarize(
            entities: seeded,
            observingHostRole: observingHostRole
        )
        lastTelemetry = pulse
        telemetry.emit(pulse)
        print("🎉 ✨ LAUNCH ENTITY REFRESH MASTERPIECE COMPLETE! \(pulse.displaySummary)")
        return pulse
    }

    /// 🌟 Immutable refresh + telemetry (friendlier for Sendable call sites).
    public func observingRefreshed() -> LaunchEntityRegistry {
        var copy = self
        _ = copy.refresh()
        return copy
    }

    // MARK: Internals

    /// 🎨 Resolve Observe status for one entity without mutating launchd.
    private func resolveStatus(for entity: LaunchEntity) -> LaunchEntityStatus {
        // Ops templates are catalog-visible but not live agents.
        if entity.isOpsOnly || entity.schedule == .opsTemplateOnly {
            return .stopped
        }

        // Satellite honesty: hub-only KeepAlive stack is n/a off-hub.
        if entity.hostRole == .hub,
           observingHostRole != .hub,
           entity.kind == .service {
            return .notApplicable
        }

        // Isolated entities are visible but never part of hive health coloring.
        if entity.hostRole == .isolated, observingHostRole == .hub {
            // Still observe if present on Studio (tunnel may run here); don't force n/a.
        }

        guard let observation = launchctl.observe(label: entity.label) else {
            // No signal — honest stopped (or n/a if this host shouldn't run it).
            if entity.hostRole == .hub, observingHostRole == .satellite, entity.kind == .service {
                return .notApplicable
            }
            return .stopped
        }

        return observation.inferredStatus
    }
}
