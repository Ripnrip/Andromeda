/**
 * 🎭 The HealthSnapshotTests - Observatory Calibration Rituals
 *
 * "We light studio lanterns, dim satellite beacons to honest n/a,
 * shatter the glass into corrupt fog — and prove the console
 * never paints a false green over broken parchment."
 *
 * - The Spellbinding Museum Director of Telemetry Verification
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🩺 Health Snapshot / Agent Telemetry (BIN-27)")
struct HealthSnapshotTests {

    // MARK: - Fixtures (no live ~/.multibrain required)

    /// 🟢 Studio hub — all nine checks pass.
    private var studioGreenJSON: String {
        """
        {
          "status": "green",
          "checked_at": "2026-07-14T06:00:00Z",
          "last_success": "2026-07-14T02:34:10Z",
          "checks": {
            "capture_fresh":   {"ok": true,  "detail": "412 obs in last 24h"},
            "sources":         {"ok": true,  "detail": "claude-mem reachable"},
            "notes_written":   {"ok": true,  "detail": "6 notes stamped 2026-07-14"},
            "graph_colored":   {"ok": true,  "detail": "20 colorGroups in graph.json"},
            "ladybug_query":   {"ok": true,  "detail": "HTTP 200 from http://127.0.0.1:8286/health"},
            "letta_api":       {"ok": true,  "detail": "HTTP 200 from http://127.0.0.1:8283/v1/health"},
            "git_committed":   {"ok": true,  "detail": "vault clean & committed"},
            "anomaly":         {"ok": true,  "detail": "counts within 7d baseline"},
            "dead_man":        {"ok": true,  "detail": "last success 3h ago"}
          },
          "baselines": {"notes_7d_avg": 5.4, "obs_7d_avg": 380}
        }
        """
    }

    /// 🛰️ Book satellite — hub services honest n/a; must not force red.
    private var satelliteHonestJSON: String {
        """
        {
          "status": "green",
          "checked_at": "2026-07-14T06:00:00Z",
          "last_success": "2026-07-14T02:34:10Z",
          "checks": {
            "capture_fresh":   {"ok": true,  "detail": "88 obs in last 24h"},
            "sources":         {"ok": true,  "detail": "claude-mem reachable"},
            "notes_written":   {"ok": true,  "detail": "2 notes stamped 2026-07-14"},
            "graph_colored":   {"ok": null, "status": "n/a", "detail": "graphify_nightly off; no graph.json"},
            "ladybug_query":   {"ok": null, "status": "n/a", "detail": "n/a (satellite — no LadybugDB hub)"},
            "letta_api":       {"ok": null, "status": "n/a", "detail": "n/a (satellite — no Letta hub)"},
            "git_committed":   {"ok": true,  "detail": "vault clean & committed"},
            "anomaly":         {"ok": true,  "detail": "counts within 7d baseline"},
            "dead_man":        {"ok": true,  "detail": "last success 3h ago"}
          },
          "baselines": {"notes_7d_avg": 2.1, "obs_7d_avg": 90}
        }
        """
    }

    /// 🔴 Explicit failures present — null/n/a still excluded from failing set.
    private var mixedRedJSON: String {
        """
        {
          "status": "red",
          "checked_at": "2026-07-15T05:25:34Z",
          "last_success": "2026-07-08T07:41:47Z",
          "checks": {
            "capture_fresh":   {"ok": true,  "detail": "309 obs in last 24h"},
            "sources":         {"ok": true,  "detail": "claude-mem reachable"},
            "notes_written":   {"ok": true,  "detail": "5 notes stamped 2026-07-15"},
            "graph_colored":   {"ok": true,  "detail": "20 colorGroups in graph.json"},
            "ladybug_query":   {"ok": false, "detail": "index-server down"},
            "letta_api":       {"ok": null, "status": "n/a", "detail": "n/a (satellite — no Letta hub)"},
            "git_committed":   {"ok": false, "detail": "16 uncommitted change(s)"},
            "anomaly":         {"ok": true,  "detail": "counts within 7d baseline"},
            "dead_man":        {"ok": false, "detail": "last success 165h ago"}
          },
          "baselines": {"notes_7d_avg": 0.0, "obs_7d_avg": 4.66}
        }
        """
    }

    // MARK: - Studio green

    @Test("🟢 Studio green fixture parses §9 shape with nine checks")
    func testStudioGreenFixture() {
        let snapshot = HealthSnapshotLoader.load(json: studioGreenJSON)

        #expect(snapshot.status == .green)
        #expect(snapshot.isGreen)
        #expect(snapshot.checks.count == 9)
        #expect(snapshot.failingCheckNames.isEmpty)
        #expect(snapshot.notApplicableCheckNames.isEmpty)
        #expect(snapshot.baselines["notes_7d_avg"] == 5.4)
        #expect(snapshot.baselines["obs_7d_avg"] == 380)
        #expect(snapshot.checkedAt != nil)
        #expect(snapshot.lastSuccess != nil)
        #expect(snapshot.derivedStatusFromChecks == .green)
    }

    // MARK: - Satellite honesty

    @Test("🛰️ Satellite n/a checks do not appear as failures and do not force red")
    func testSatelliteHonestyNullAndNA() {
        let snapshot = HealthSnapshotLoader.load(json: satelliteHonestJSON)

        #expect(snapshot.status == .green, "Headline stays green when only hub checks are n/a")
        #expect(snapshot.failingCheckNames.isEmpty, "Null/n/a must never join the failing set")

        let na = snapshot.notApplicableCheckNames
        #expect(na == ["graph_colored", "ladybug_query", "letta_api"])

        #expect(snapshot.checks["ladybug_query"]?.isNotApplicable == true)
        #expect(snapshot.checks["letta_api"]?.ok == nil)
        #expect(snapshot.checks["letta_api"]?.contributesFailure == false)

        #expect(snapshot.derivedStatusFromChecks == .green,
                "Derived rollup must ignore n/a — satellite honesty is a love language 🛰️")
    }

    @Test("🛰️ ok:null alone (without status field) is still notApplicable")
    func testNullOkWithoutStatusField() {
        let json = """
        {
          "status": "green",
          "checked_at": "2026-07-14T06:00:00Z",
          "last_success": null,
          "checks": {
            "ladybug_query": {"ok": null, "detail": "skipped"}
          },
          "baselines": {}
        }
        """
        let snapshot = HealthSnapshotLoader.load(json: json)
        #expect(snapshot.status == .green)
        #expect(snapshot.lastSuccess == nil)
        #expect(snapshot.checks["ladybug_query"]?.isNotApplicable == true)
        #expect(snapshot.failingCheckNames.isEmpty)
        #expect(snapshot.derivedStatusFromChecks == .green)
    }

    // MARK: - Failures

    @Test("🔴 Only ok:false contributes failures; n/a siblings stay out of the red list")
    func testMixedFailuresExcludeNA() {
        let snapshot = HealthSnapshotLoader.load(json: mixedRedJSON)

        #expect(snapshot.status == .red)
        #expect(snapshot.failingCheckNames == ["dead_man", "git_committed", "ladybug_query"])
        #expect(snapshot.notApplicableCheckNames == ["letta_api"])
        #expect(snapshot.derivedStatusFromChecks == .red)
        #expect(snapshot.needsAttention)
    }

    // MARK: - Corrupt → unknown (never fake green)

    @Test("💥 Corrupt JSON yields unknown — never a forged green")
    func testCorruptJSONIsUnknownNotGreen() {
        let snapshots = [
            HealthSnapshotLoader.load(json: "{not json at all"),
            HealthSnapshotLoader.load(json: ""),
            HealthSnapshotLoader.load(json: "null"),
            HealthSnapshotLoader.load(json: "[1,2,3]"),
            HealthSnapshotLoader.load(data: Data()),
            HealthSnapshotLoader.load(data: Data([0xFF, 0xFE, 0xFD])),
        ]

        for snapshot in snapshots {
            #expect(snapshot.status == .unknown, "Corrupt payload must be unknown")
            #expect(!snapshot.isGreen, "Never fake green over shattered glass")
            #expect(snapshot.needsAttention)
        }
    }

    @Test("🔮 Missing status field decodes as unknown (fail closed)")
    func testMissingStatusIsUnknown() {
        let json = """
        {
          "checked_at": "2026-07-14T06:00:00Z",
          "checks": {
            "capture_fresh": {"ok": true, "detail": "ok"}
          }
        }
        """
        let snapshot = HealthSnapshotLoader.load(json: json)
        #expect(snapshot.status == .unknown)
        #expect(!snapshot.isGreen)
    }

    @Test("🔮 Garbage status string maps to unknown, not green")
    func testGarbageStatusString() {
        let json = """
        {
          "status": "sparkly-unicorn",
          "checks": {}
        }
        """
        let snapshot = HealthSnapshotLoader.load(json: json)
        #expect(snapshot.status == .unknown)
    }

    @Test("📂 Missing file path loads as unknown (no live home required)")
    func testMissingFileIsUnknown() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("memorykit-health-missing-\(UUID().uuidString).json")
        let snapshot = HealthSnapshotLoader.load(from: missing)
        #expect(snapshot.status == .unknown)
        #expect(!snapshot.isGreen)
    }

    @Test("📂 Fixture file round-trip via temp path (still no ~/.multibrain)")
    func testLoadFromTempFixtureFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memorykit-health-fixture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try studioGreenJSON.data(using: .utf8)!.write(to: url)
        let snapshot = HealthSnapshotLoader.load(from: url)
        #expect(snapshot.status == .green)
        #expect(snapshot.checks.count == 9)
    }

    // MARK: - Yellow + encode

    @Test("🟡 Yellow headline parses and still needsAttention")
    func testYellowStatus() {
        let json = """
        {
          "status": "yellow",
          "checked_at": "2026-07-14T06:00:00Z",
          "last_success": "2026-07-14T02:34:10Z",
          "checks": {
            "git_committed": {"ok": false, "detail": "3 uncommitted change(s)"}
          },
          "baselines": {}
        }
        """
        let snapshot = HealthSnapshotLoader.load(json: json)
        #expect(snapshot.status == .yellow)
        #expect(snapshot.needsAttention)
        #expect(snapshot.failingCheckNames == ["git_committed"])
    }

    @Test("💎 Unknown factory is never green")
    func testUnknownFactory() {
        #expect(HealthSnapshot.unknown.status == .unknown)
        #expect(!HealthSnapshot.unknown.isGreen)
        #expect(HealthSnapshot.unknown.checks.isEmpty)
        #expect(HealthSnapshot.unknown.derivedStatusFromChecks == .unknown)
    }
}
