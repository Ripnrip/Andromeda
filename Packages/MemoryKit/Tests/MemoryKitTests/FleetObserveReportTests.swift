/**
 * 🎭 FleetObserveReportTests - LaunchEntity × Health Join Rituals
 *
 * "Nightly idle must not scream red — but dead_man must.
 * Index-server KeepAlive green with /health dead must still crack the lantern."
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🌐 Fleet Observe Join Suite")
struct FleetObserveReportTests {

    private var mixedRedJSON: String {
        """
        {
          "status": "red",
          "checked_at": "2026-07-15T05:25:34Z",
          "last_success": "2026-07-08T07:41:47Z",
          "checks": {
            "capture_fresh":   {"ok": true,  "detail": "309 obs"},
            "sources":         {"ok": true,  "detail": "ok"},
            "notes_written":   {"ok": true,  "detail": "5 notes"},
            "graph_colored":   {"ok": true,  "detail": "ok"},
            "ladybug_query":   {"ok": false, "detail": "index-server down"},
            "letta_api":       {"ok": true,  "detail": "HTTP 200"},
            "git_committed":   {"ok": false, "detail": "16 uncommitted"},
            "anomaly":         {"ok": true,  "detail": "ok"},
            "dead_man":        {"ok": false, "detail": "last success 165h ago"}
          },
          "baselines": {}
        }
        """
    }

    private var studioGreenJSON: String {
        """
        {
          "status": "green",
          "checked_at": "2026-07-14T06:00:00Z",
          "last_success": "2026-07-14T02:34:10Z",
          "checks": {
            "capture_fresh": {"ok": true, "detail": "ok"},
            "sources": {"ok": true, "detail": "ok"},
            "notes_written": {"ok": true, "detail": "ok"},
            "graph_colored": {"ok": true, "detail": "ok"},
            "ladybug_query": {"ok": true, "detail": "HTTP 200"},
            "letta_api": {"ok": true, "detail": "HTTP 200"},
            "git_committed": {"ok": true, "detail": "ok"},
            "anomaly": {"ok": true, "detail": "ok"},
            "dead_man": {"ok": true, "detail": "last success 3h ago"}
          },
          "baselines": {}
        }
        """
    }

    private var lettaRedJSON: String {
        """
        {
          "status": "red",
          "checked_at": "2026-07-15T05:25:34Z",
          "last_success": "2026-07-14T02:34:10Z",
          "checks": {
            "capture_fresh": {"ok": true, "detail": "ok"},
            "sources": {"ok": true, "detail": "ok"},
            "notes_written": {"ok": true, "detail": "ok"},
            "graph_colored": {"ok": true, "detail": "ok"},
            "ladybug_query": {"ok": true, "detail": "HTTP 200"},
            "letta_api": {"ok": false, "detail": "connection refused"},
            "git_committed": {"ok": true, "detail": "ok"},
            "anomaly": {"ok": true, "detail": "ok"},
            "dead_man": {"ok": true, "detail": "last success 3h ago"}
          },
          "baselines": {}
        }
        """
    }

    /// 🧪 Hub roster with KeepAlives up and crons idle (exit 0) — override one label at a time.
    private func hubGreenObservations(
        overrides: [String: LaunchObservation] = [:]
    ) -> [String: LaunchObservation] {
        var base: [String: LaunchObservation] = [
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 1),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.claude-mem-worker": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            // HAB-42 habitat / Multica ghosts
            "com.multica.daemon": LaunchObservation(isLoaded: true, isRunning: true, pid: 3636),
            "com.multica.stack": LaunchObservation(isLoaded: true, isRunning: true, pid: 3637),
            "dev.agent-habitat.boot": LaunchObservation(isLoaded: true, isRunning: true, pid: 10),
            "com.local.multica-host-forwarder": LaunchObservation(isLoaded: true, isRunning: true, pid: 11),
            "com.tailscale.serve.hermes": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.local.fix-default-route": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ]
        for (label, observation) in overrides {
            base[label] = observation
        }
        return base
    }

    private func composeHub(
        observations: [String: LaunchObservation],
        healthJSON: String,
        indexServer: IndexServerHealthResult? = IndexServerHealthResult(
            ok: true,
            statusCode: 200,
            detail: "HTTP 200"
        )
    ) -> FleetObserveReport {
        let mock = MockLaunchctlObserver(observations: observations)
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        _ = registry.refresh()
        return FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: HealthSnapshotLoader.load(json: healthJSON),
            indexServer: indexServer
        )
    }

    @Test("🧾 launchctl list parse extracts PID + LastExitStatus")
    func testLaunchctlListParse() {
        let stdout = """
        {
            "PID" = 4242;
            "LastExitStatus" = 0;
            "Label" = "com.multibrain.letta";
        };
        """
        let obs = LaunchObservation.parse(launchctlListOutput: stdout)
        #expect(obs.isLoaded)
        #expect(obs.isRunning)
        #expect(obs.pid == 4242)
        #expect(obs.lastExitStatus == 0)
        #expect(obs.inferredStatus == .running)
    }

    @Test("🧾 launchctl list without PID is loaded idle (not running)")
    func testLaunchctlListParseIdleNoPID() {
        let stdout = """
        {
            "LastExitStatus" = 0;
            "Label" = "com.multibrain.nightly";
        };
        """
        let obs = LaunchObservation.parse(launchctlListOutput: stdout)
        #expect(obs.isLoaded)
        #expect(!obs.isRunning)
        #expect(obs.pid == nil)
        #expect(obs.lastExitStatus == 0)
        #expect(obs.inferredStatus == .stopped)
        #expect(!obs.exitedNonZero)
    }

    @Test("🧾 launchctl list non-zero exit without PID flags exitedNonZero")
    func testLaunchctlListParseNonZeroExitIdle() {
        let obs = LaunchObservation.parse(launchctlListOutput: """
        { "LastExitStatus" = 78; "Label" = "com.multibrain.nightly"; };
        """)
        #expect(!obs.isRunning)
        #expect(obs.exitedNonZero)
        #expect(obs.lastExitStatus == 78)
    }

    @Test("🌙 Cron idle with exit 0 is IDLE — not critical")
    func testNightlyIdleOkWhenHealthGreen() {
        let mock = MockLaunchctlObserver(observations: hubGreenObservations())
        let launchctl = mock
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: launchctl)
        _ = registry.refresh()

        let health = HealthSnapshotLoader.load(json: studioGreenJSON)
        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: launchctl,
            health: health,
            indexServer: IndexServerHealthResult(ok: true, statusCode: 200, detail: "HTTP 200")
        )

        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.attention == .idle)
        #expect(nightly?.why == nil)

        let ladybug = report.rows.first { $0.entity.slug == "svc.ladybug.serve" }
        #expect(ladybug?.attention == .ok)
        #expect(report.attentionRows.isEmpty)
        #expect(report.headlineWhy == nil)
    }

    @Test("🧾 LiveLaunchctlObserver maps MockLaunchctlListRunner stdout")
    func testLiveObserverUsesListRunner() {
        let runner = MockLaunchctlListRunner(outputs: [
            "com.multibrain.letta": """
            { "PID" = 4242; "LastExitStatus" = 15; };
            """,
            "com.multibrain.nightly": """
            { "LastExitStatus" = 0; };
            """,
        ])
        let observer = LiveLaunchctlObserver(runner: runner)
        let letta = observer.observe(label: "com.multibrain.letta")
        #expect(letta?.isRunning == true)
        #expect(letta?.pid == 4242)
        #expect(letta?.lastExitStatus == 15)
        let nightly = observer.observe(label: "com.multibrain.nightly")
        #expect(nightly?.isRunning == false)
        #expect(nightly?.lastExitStatus == 0)
        #expect(observer.observe(label: "com.multibrain.missing") == nil)
    }

    @Test("💀 dead_man fail paints job.nightly CRITICAL with why")
    func testDeadManJoinsNightly() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 1),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.claude-mem-worker": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: false),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        _ = registry.refresh()

        let health = HealthSnapshotLoader.load(json: mixedRedJSON)
        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: health
        )

        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.attention == .critical)
        #expect(nightly?.why?.contains("dead_man") == true)

        let ladybug = report.rows.first { $0.entity.slug == "svc.ladybug.serve" }
        #expect(ladybug?.attention == .critical)
        #expect(ladybug?.why?.contains("ladybug_query") == true)

        #expect(report.headlineWhy?.contains("dead_man") == true || report.headlineWhy?.contains("ladybug") == true)
        #expect(health.failureSummaries.contains(where: { $0.name == "dead_man" }))
    }

    @Test("🩺 Live /health fail overrides stale green ladybug check")
    func testLiveIndexProbeCritical() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 1),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.claude-mem-worker": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: false),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        _ = registry.refresh()

        let health = HealthSnapshotLoader.load(json: studioGreenJSON)
        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: health,
            indexServer: IndexServerHealthResult(
                ok: false,
                statusCode: nil,
                detail: "index-server down: connection refused"
            )
        )

        let ladybug = report.rows.first { $0.entity.slug == "svc.ladybug.serve" }
        #expect(ladybug?.attention == .critical)
        #expect(ladybug?.why?.contains("live /health") == true)
    }

    @Test("💥 Non-zero lastExit degrades cron without health fail")
    func testNonZeroLastExitDegraded() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.nightly": LaunchObservation(
                isLoaded: true,
                isRunning: false,
                lastExitStatus: 1
            ),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 1),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.claude-mem-worker": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: false),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        _ = registry.refresh()

        let health = HealthSnapshotLoader.load(json: studioGreenJSON)
        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: health,
            indexServer: IndexServerHealthResult(ok: true, statusCode: 200, detail: "ok")
        )

        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.attention == .degraded)
        #expect(nightly?.why?.contains("lastExit=1") == true)
    }

    @Test("♻️ KeepAlive running ignores stale non-zero LastExitStatus")
    func testRunningKeepAliveIgnoresStaleExit() {
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.index-server": LaunchObservation(
                isLoaded: true,
                isRunning: true,
                pid: 33705,
                lastExitStatus: 15
            ),
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 1),
            "com.multibrain.letta-bridge": LaunchObservation(isLoaded: true, isRunning: true, pid: 2),
            "com.multibrain.letta-shim": LaunchObservation(isLoaded: true, isRunning: true, pid: 3),
            "com.multibrain.nightly": LaunchObservation(isLoaded: true, isRunning: false, lastExitStatus: 0),
            "com.multibrain.health": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.claude-mem-worker": LaunchObservation(isLoaded: true, isRunning: false),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: false),
            "com.local.mac-mini-vnc-tunnel": LaunchObservation(isLoaded: true, isRunning: true, pid: 9),
        ])
        var registry = LaunchEntityRegistry(observingHostRole: .hub, launchctl: mock)
        _ = registry.refresh()

        let health = HealthSnapshotLoader.load(json: studioGreenJSON)
        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: health,
            indexServer: IndexServerHealthResult(ok: true, statusCode: 200, detail: "HTTP 200")
        )

        let ladybug = report.rows.first { $0.entity.slug == "svc.ladybug.serve" }
        #expect(ladybug?.attention == .ok)
        #expect(ladybug?.why == nil)
    }

    @Test("🛰️ Satellite skips index probe via skipped result")
    func testSatelliteIndexSkip() {
        let client = IndexServerHealthClient(observingHostRole: .satellite)
        let result = client.probe()
        #expect(result.skipped)
        #expect(result.ok)
        #expect(result.detail.contains("n/a"))
    }

    @Test("🧊 Isolated host also skips index probe (no Ladybug red)")
    func testIsolatedIndexSkip() {
        let client = IndexServerHealthClient(observingHostRole: .isolated)
        let result = client.probe()
        #expect(result.skipped)
        #expect(result.ok)
        #expect(result.detail.contains("n/a"))
    }

    @Test("🛰️ Skipped index probe never overrides green ladybug")
    func testSkippedIndexProbeIgnored() {
        let report = composeHub(
            observations: hubGreenObservations(),
            healthJSON: studioGreenJSON,
            indexServer: .skipped(reason: "n/a (satellite — no LadybugDB hub)")
        )
        let ladybug = report.rows.first { $0.entity.slug == "svc.ladybug.serve" }
        #expect(ladybug?.attention == .ok)
        #expect(ladybug?.why == nil)
    }

    @Test("🛰️ Satellite compose paints hub KeepAlives n/a — not KeepAlive-critical")
    func testSatelliteComposeHubServicesNotApplicable() {
        let mock = MockLaunchctlObserver(observations: hubGreenObservations(overrides: [
            // Confused live PID on satellite must not invent red KeepAlive.
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 4242),
            "com.multibrain.index-server": LaunchObservation(isLoaded: true, isRunning: true, pid: 4),
        ]))
        var registry = LaunchEntityRegistry(observingHostRole: .satellite, launchctl: mock)
        _ = registry.refresh()

        let report = FleetObserveComposer.compose(
            registry: registry,
            launchctl: mock,
            health: HealthSnapshotLoader.load(json: studioGreenJSON),
            indexServer: .skipped(reason: "n/a (satellite — no LadybugDB hub)")
        )

        let hubKeepAlives = [
            "svc.letta",
            "svc.letta.bridge",
            "svc.letta.shim",
            "svc.ladybug.serve",
            "svc.multica.daemon",
            "svc.multica.stack",
            "svc.habitat.boot",
        ]
        for slug in hubKeepAlives {
            let row = report.rows.first { $0.entity.slug == slug }
            #expect(row?.entity.status == .notApplicable)
            #expect(row?.attention == .notApplicable)
            #expect(row?.why == nil)
        }
        // Hub KeepAlives must not appear in attentionRows as KeepAlive-critical.
        #expect(report.attentionRows.allSatisfy { row in
            !hubKeepAlives.contains(row.entity.slug)
        })
    }

    @Test("🔴 KeepAlive service stopped is CRITICAL")
    func testKeepAliveDownCritical() {
        let report = composeHub(
            observations: hubGreenObservations(overrides: [
                "com.multibrain.letta": LaunchObservation(
                    isLoaded: true,
                    isRunning: false,
                    lastExitStatus: 0
                ),
            ]),
            healthJSON: studioGreenJSON
        )
        let letta = report.rows.first { $0.entity.slug == "svc.letta" }
        #expect(letta?.attention == .critical)
        #expect(letta?.why?.contains("KeepAlive not running") == true)
    }

    @Test("🧊 Tunnel KeepAlive down is CRITICAL")
    func testTunnelDownCritical() {
        let report = composeHub(
            observations: hubGreenObservations(overrides: [
                "com.local.mac-mini-vnc-tunnel": LaunchObservation(
                    isLoaded: true,
                    isRunning: false,
                    lastExitStatus: 0
                ),
            ]),
            healthJSON: studioGreenJSON
        )
        let tunnel = report.rows.first { $0.entity.slug == "tunnel.mac-mini-vnc" }
        #expect(tunnel?.attention == .critical)
        #expect(tunnel?.why?.contains("KeepAlive not running") == true)
    }

    @Test("📭 Unloaded hub cron is DEGRADED (agent missing)")
    func testUnloadedHubCronDegraded() {
        var observations = hubGreenObservations()
        observations.removeValue(forKey: "com.multibrain.nightly")
        let report = composeHub(observations: observations, healthJSON: studioGreenJSON)

        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.entity.status == .stopped)
        #expect(nightly?.attention == .degraded)
        #expect(nightly?.why?.contains("LaunchAgent not loaded") == true)
    }

    @Test("📜 Ops-only retro stays IDLE in compose")
    func testOpsOnlyIdleInCompose() {
        let report = composeHub(
            observations: hubGreenObservations(),
            healthJSON: studioGreenJSON
        )
        let retro = report.rows.first { $0.entity.slug == "job.weekly_retro" }
        #expect(retro?.entity.status == .stopped)
        #expect(retro?.attention == .idle)
        #expect(retro?.why == nil)
    }

    @Test("🧠 letta_api fail paints svc.letta CRITICAL")
    func testLettaApiJoinsLettaService() {
        let report = composeHub(
            observations: hubGreenObservations(),
            healthJSON: lettaRedJSON
        )
        let letta = report.rows.first { $0.entity.slug == "svc.letta" }
        #expect(letta?.attention == .critical)
        #expect(letta?.why?.contains("letta_api") == true)
        #expect(letta?.correlatedChecks.contains("letta_api") == true)

        let bridge = report.rows.first { $0.entity.slug == "svc.letta.bridge" }
        #expect(bridge?.attention == .critical)
    }

    @Test("💀 dead_man CRITICAL beats non-zero lastExit DEGRADED")
    func testHealthJoinBeatsLastExit() {
        let report = composeHub(
            observations: hubGreenObservations(overrides: [
                "com.multibrain.nightly": LaunchObservation(
                    isLoaded: true,
                    isRunning: false,
                    lastExitStatus: 1
                ),
            ]),
            healthJSON: mixedRedJSON,
            indexServer: nil
        )
        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.attention == .critical)
        #expect(nightly?.why?.contains("dead_man") == true)
        #expect(nightly?.why?.contains("lastExit") != true)
    }

    @Test("🛡️ Watchdog non-zero lastExit is DEGRADED while idle")
    func testWatchdogNonZeroLastExitDegraded() {
        let report = composeHub(
            observations: hubGreenObservations(overrides: [
                "com.multibrain.dreamcatcher": LaunchObservation(
                    isLoaded: true,
                    isRunning: false,
                    lastExitStatus: 2
                ),
            ]),
            healthJSON: studioGreenJSON
        )
        let dream = report.rows.first { $0.entity.slug == "river.dreamcatcher" }
        #expect(dream?.attention == .degraded)
        #expect(dream?.why?.contains("lastExit=2") == true)
    }

    @Test("♻️ Running cron ignores stale non-zero LastExitStatus")
    func testRunningCronIgnoresStaleExit() {
        let report = composeHub(
            observations: hubGreenObservations(overrides: [
                "com.multibrain.nightly": LaunchObservation(
                    isLoaded: true,
                    isRunning: true,
                    pid: 555,
                    lastExitStatus: 9
                ),
            ]),
            healthJSON: studioGreenJSON
        )
        let nightly = report.rows.first { $0.entity.slug == "job.nightly" }
        #expect(nightly?.attention == .ok)
        #expect(nightly?.why == nil)
    }
}
