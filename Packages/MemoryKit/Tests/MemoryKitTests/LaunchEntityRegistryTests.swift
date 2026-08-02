/**
 * 🎭 LaunchEntityRegistryTests - The Roster Quality Assurance Ritual
 *
 * "We summon the catalog under studio lights, poke a mock launchctl,
 * and ensure the Mini tunnel never sneaks into the hive chorus.
 * Kickstart stays in the prop closet — Observe only."
 *
 * - The Theatrical QA Virtuoso of Fleet Observability
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("🚀 LaunchEntity Registry Suite")
struct LaunchEntityRegistryTests {

    // MARK: - Catalog seeds

    @Test("📜 Catalog seeds known com.multibrain.* entities")
    func testCatalogSeedsMultibrainEntities() {
        let registry = LaunchEntityRegistry(observingHostRole: .hub)
        let labels = Set(registry.multibrainEntities().map(\.label))

        let expected: Set<String> = [
            "com.multibrain.nightly",
            "com.multibrain.health",
            "com.multibrain.letta",
            "com.multibrain.letta-bridge",
            "com.multibrain.letta-shim",
            "com.multibrain.index-server",
            "com.multibrain.claude-mem-worker",
            "com.multibrain.dreamcatcher",
            "com.multibrain.retro",
        ]

        #expect(labels == expected)
        #expect(registry.all().count == 16) // 9 multibrain + 6 HAB-42 habitat/Multica + Mini tunnel
    }

    @Test("👻 HAB-42 habitat ghosts are seeded (Multica + agent-habitat lane)")
    func testHabitatGhostEntitiesSeeded() throws {
        let registry = LaunchEntityRegistry(observingHostRole: .hub)

        let daemon = try #require(registry.entity(slug: "svc.multica.daemon"))
        #expect(daemon.label == "com.multica.daemon")
        #expect(daemon.kind == .service)
        #expect(daemon.schedule == .keepAlive)
        #expect(daemon.hostRole == .hub)

        let stack = try #require(registry.entity(slug: "svc.multica.stack"))
        #expect(stack.label == "com.multica.stack")
        #expect(stack.kind == .service)
        #expect(stack.schedule == .keepAlive)
        #expect(stack.hostRole == .hub)

        let boot = try #require(registry.entity(slug: "svc.habitat.boot"))
        #expect(boot.label == "dev.agent-habitat.boot")
        #expect(boot.kind == .service)
        #expect(boot.schedule == .keepAlive)
        #expect(boot.hostRole == .hub)
        #expect(boot.purpose.lowercased().contains("habitat"))

        let forwarder = try #require(registry.entity(slug: "svc.multica.host_forwarder"))
        #expect(forwarder.label == "com.local.multica-host-forwarder")
        #expect(forwarder.kind == .tunnel)
        #expect(forwarder.schedule == .keepAlive)
        #expect(forwarder.hostRole == .hub)
        #expect(forwarder.purpose.lowercased().contains("socat") || forwarder.purpose.lowercased().contains("3636"))

        let serve = try #require(registry.entity(slug: "svc.tailscale.serve_reassert"))
        #expect(serve.label == "com.tailscale.serve.hermes")
        #expect(serve.kind == .cron)
        #expect(serve.schedule == .interval(seconds: 300))
        #expect(serve.hostRole == .hub)

        let route = try #require(registry.entity(slug: "watchdog.fix_default_route"))
        #expect(route.label == "com.local.fix-default-route")
        #expect(route.kind == .watchdog)
        #expect(route.schedule == .interval(seconds: 30))
        #expect(route.hostRole == .hub)

        // Catalog is idempotent — slug lookup stays unique.
        let slugs = registry.all().map(\.slug)
        #expect(Set(slugs).count == slugs.count)
        #expect(registry.entity(label: "com.local.multica-host-forwarder")?.slug == "svc.multica.host_forwarder")
    }

    @Test("👁️ HAB-42 Multica hub services observe-only (no kickstart; satellite → n/a)")
    func testHabitatMulticaServicesObserveOnly() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multica.daemon": LaunchObservation(isLoaded: true, isRunning: true, pid: 3636),
            "com.multica.stack": LaunchObservation(isLoaded: true, isRunning: true, pid: 3637),
            "dev.agent-habitat.boot": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
            "com.local.multica-host-forwarder": LaunchObservation(isLoaded: true, isRunning: false),
        ])

        var hub = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        hub.refreshStatuses()

        #expect(hub.entity(slug: "svc.multica.daemon")?.status == .running)
        #expect(hub.entity(slug: "svc.multica.stack")?.status == .running)
        #expect(hub.entity(slug: "svc.habitat.boot")?.status == .running)
        #expect(hub.entity(slug: "svc.multica.host_forwarder")?.status == .stopped)

        let satellite = LaunchEntityRegistry(observingHostRole: .satellite, launchctl: mock)
            .observingRefreshed()
        #expect(satellite.entity(slug: "svc.multica.daemon")?.status == .notApplicable)
        #expect(satellite.entity(slug: "svc.multica.stack")?.status == .notApplicable)
        #expect(satellite.entity(slug: "svc.habitat.boot")?.status == .notApplicable)
        // Tunnel is not gated as hub-only *service* — still observes stopped/running honestly.
        #expect(satellite.entity(slug: "svc.multica.host_forwarder")?.status == .stopped)
    }

    @Test("🌙 Nightly is cron @ 02:30 hub dream batch")
    func testNightlyEntityShape() throws {
        let registry = LaunchEntityRegistry()
        let nightly = try #require(registry.entity(slug: "job.nightly"))

        #expect(nightly.label == "com.multibrain.nightly")
        #expect(nightly.kind == .cron)
        #expect(nightly.hostRole == .hub)
        #expect(nightly.schedule == .calendar(hour: 2, minute: 30, weekday: nil))
        #expect(nightly.schedule.displaySummary == "daily 02:30")
        #expect(nightly.plistPath.contains("com.multibrain.nightly.plist"))
        #expect(nightly.isOpsOnly == false)
    }

    @Test("🛡️ Dreamcatcher + claude-mem-worker are visible watchdogs")
    func testWatchdogsAreVisible() throws {
        let registry = LaunchEntityRegistry()
        let dreamcatcher = try #require(registry.entity(slug: "river.dreamcatcher"))
        let worker = try #require(registry.entity(slug: "river.claude-mem.worker"))

        #expect(dreamcatcher.kind == .watchdog)
        #expect(dreamcatcher.schedule == .interval(seconds: 1800))
        #expect(worker.kind == .watchdog)
        #expect(worker.schedule == .interval(seconds: 60))
        #expect(dreamcatcher.purpose.lowercased().contains("dream"))
        #expect(worker.purpose.lowercased().contains("capture") || worker.purpose.lowercased().contains("worker"))
    }

    @Test("📜 Retro is ops-only template (not installed)")
    func testRetroOpsOnly() throws {
        let registry = LaunchEntityRegistry()
        let retro = try #require(registry.entity(slug: "job.weekly_retro"))

        #expect(retro.isOpsOnly == true)
        #expect(retro.schedule == .opsTemplateOnly)
        #expect(retro.plistPath.contains("/ops/com.multibrain.retro.plist"))
        #expect(retro.hostRole == .hub)
    }

    @Test("🧊 Mac Mini tunnel is isolated / non-hive")
    func testMacMiniTunnelIsolated() throws {
        let registry = LaunchEntityRegistry()
        let mini = try #require(registry.entity(slug: "tunnel.mac-mini-vnc"))

        #expect(mini.hostRole == .isolated)
        #expect(mini.kind == .tunnel)
        #expect(mini.label == "com.local.mac-mini-vnc-tunnel")
        #expect(registry.isolatedEntities().map(\.slug) == ["tunnel.mac-mini-vnc"])
        #expect(registry.hiveEntities().allSatisfy { $0.hostRole != .isolated })
        #expect(registry.hiveEntities().contains { $0.slug == "tunnel.mac-mini-vnc" } == false)
    }

    // MARK: - Observe (mock launchctl)

    @Test("👁️ Mock launchctl maps running / stopped without kickstart")
    func testMockLaunchctlObserveOnly() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 4242),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: true, pid: 99),
        ])

        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        registry.refreshStatuses()

        #expect(registry.entity(slug: "job.nightly")?.status == .stopped)
        #expect(registry.entity(slug: "svc.letta")?.status == .running)
        #expect(registry.entity(slug: "river.dreamcatcher")?.status == .running)
        // Ops-only never flips to running even if somehow observed.
        #expect(registry.entity(slug: "job.weekly_retro")?.status == .stopped)
    }

    @Test("🛰️ Satellite honesty — hub services report n/a")
    func testSatelliteHubServicesNotApplicable() {
        let mock = MockLaunchctlObserver(observations: [
            // Even if a confused observer returns something, host-role gate wins for services.
            "com.multibrain.letta": LaunchObservation(isLoaded: false, isRunning: false),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: true, pid: 7),
        ])

        let registry = LaunchEntityRegistry(observingHostRole: .satellite, launchctl: mock)
            .observingRefreshed()

        #expect(registry.entity(slug: "svc.letta")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.letta.bridge")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.letta.shim")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.ladybug.serve")?.status == .notApplicable)
        // Health cron is hub-seeded but not a hub-only *service* — may still observe.
        #expect(registry.entity(slug: "job.health")?.status == .running)
    }

    @Test("🛰️ Satellite with live PID still marks hub KeepAlives n/a")
    func testSatelliteRunningPIDStillNotApplicable() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 4242),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multica.daemon": LaunchObservation(isLoaded: true, isRunning: true, pid: 3636),
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
        ])

        let registry = LaunchEntityRegistry(observingHostRole: .satellite, launchctl: mock)
            .observingRefreshed()

        #expect(registry.entity(slug: "svc.letta")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.letta.bridge")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.letta.shim")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.ladybug.serve")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.multica.daemon")?.status == .notApplicable)
        // Hub cron labels are still observable off-hub (not service-gated).
        #expect(registry.entity(slug: "job.nightly")?.status == .stopped)
    }

    @Test("🧊 Isolated host also marks hub KeepAlives n/a")
    func testIsolatedHostHubServicesNotApplicable() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multica.stack": LaunchObservation(isLoaded: true, isRunning: true, pid: 3637),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ])

        let registry = LaunchEntityRegistry(observingHostRole: .isolated, launchctl: mock)
            .observingRefreshed()

        #expect(registry.entity(slug: "svc.letta")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.ladybug.serve")?.status == .notApplicable)
        #expect(registry.entity(slug: "svc.multica.stack")?.status == .notApplicable)
        #expect(registry.entity(slug: "tunnel.mac-mini-vnc")?.status == .running)
    }

    @Test("🧊 Isolated observer does not invent hive membership")
    func testIsolatedHostKeepsMiniIsolated() throws {
        let registry = LaunchEntityRegistry(observingHostRole: .isolated)
        let mini = try #require(registry.entity(slug: "tunnel.mac-mini-vnc"))
        #expect(mini.hostRole == .isolated)
        #expect(registry.hiveEntities().contains { $0.hostRole == .isolated } == false)
    }

    @Test("📜 Ops-only stays stopped even when mock claims running")
    func testOpsOnlyIgnoresRunningObservation() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.retro": LaunchObservation(isLoaded: true, isRunning: true, pid: 999),
        ])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        registry.refreshStatuses()
        #expect(registry.entity(slug: "job.weekly_retro")?.status == .stopped)
    }

    @Test("📭 Missing observation resolves to stopped on hub")
    func testMissingObservationStoppedOnHub() {
        let mock = MockLaunchctlObserver(observations: [:])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        registry.refreshStatuses()

        #expect(registry.entity(slug: "job.nightly")?.status == .stopped)
        #expect(registry.entity(slug: "svc.letta")?.status == .stopped)
        #expect(registry.entity(slug: "river.dreamcatcher")?.status == .stopped)
    }

    @Test("🔍 Lookup by launchd label")
    func testEntityLookupByLabel() throws {
        let registry = LaunchEntityRegistry()
        let bySlug = try #require(registry.entity(slug: "svc.ladybug.serve"))
        let byLabel = try #require(registry.entity(label: "com.multibrain.index-server"))
        #expect(bySlug == byLabel)
        #expect(registry.entity(label: "com.multibrain.does-not-exist") == nil)
    }

    @Test("🌙 Null observer leaves entities stopped (no fake green)")
    func testNullObserverNeverFakesRunning() {
        let registry = LaunchEntityRegistry(
            observingHostRole: .hub,
            launchctl: NullLaunchctlObserver()
        ).observingRefreshed()

        for entity in registry.multibrainEntities() where !entity.isOpsOnly {
            #expect(entity.status == .stopped || entity.status == .notApplicable)
            #expect(entity.status != .running)
        }
    }

    @Test("🎭 Entity identity + Codable round-trip")
    func testEntityCodableRoundTrip() throws {
        let original = LaunchEntity(
            slug: "job.nightly",
            label: "com.multibrain.nightly",
            kind: .cron,
            plistPath: "/tmp/com.multibrain.nightly.plist",
            schedule: .calendar(hour: 2, minute: 30, weekday: nil),
            status: .running,
            hostRole: .hub,
            purpose: "Dream batch"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LaunchEntity.self, from: data)
        #expect(decoded == original)
        #expect(decoded.id == "job.nightly")
    }

    @Test("📜 Schedule display summaries")
    func testScheduleDisplaySummaries() {
        #expect(LaunchSchedule.interval(seconds: 60).displaySummary == "every 1m")
        #expect(LaunchSchedule.interval(seconds: 1800).displaySummary == "every 30m")
        #expect(LaunchSchedule.interval(seconds: 3600).displaySummary == "every 1h")
        #expect(LaunchSchedule.keepAlive.displaySummary == "KeepAlive")
        #expect(LaunchSchedule.calendar(hour: 8, minute: 0, weekday: 1).displaySummary == "Mon 08:00")
        #expect(LaunchSchedule.opsTemplateOnly.displaySummary.contains("ops"))
    }
}
