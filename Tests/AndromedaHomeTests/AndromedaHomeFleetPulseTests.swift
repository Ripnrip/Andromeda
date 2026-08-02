/**
 * ✅ AndromedaHome fleet pulse — composer headline in chrome, no roster (HAB-74)
 */

import AndromedaHomeCore
import MemoryKit
import Testing

@Suite("AndromedaHome fleet pulse")
@MainActor
struct AndromedaHomeFleetPulseTests {

    @Test("Healthy report maps to green chrome headline without roster")
    func healthyHeadline() {
        let health = HealthSnapshot(
            status: .green,
            checks: [
                "dead_man": HealthCheck(ok: true, detail: "last success 3h ago"),
            ]
        )
        let report = FleetObserveReport(
            observingHostRole: .hub,
            health: health,
            rows: []
        )
        let model = AndromedaHomeModel()
        model.apply(report: report)

        #expect(AndromedaHomeModel.menuStatus(from: report) == .green)
        #expect(model.fleetStatus == .green)
        #expect(model.fleetAttentionCount == 0)
        #expect(model.fleetDetail == "Fleet pulse green · 0 attention(s)")
        #expect(model.commandCenter.healthStatus == .healthy)
    }

    @Test("Critical joined why becomes home fleetDetail headline")
    func criticalHeadlineWhy() {
        let entity = LaunchEntity(
            slug: "job.nightly",
            label: "com.multibrain.nightly",
            kind: .cron,
            plistPath: "~/Library/LaunchAgents/com.multibrain.nightly.plist",
            schedule: .calendar(hour: 2, minute: 30, weekday: nil),
            status: .stopped,
            hostRole: .hub,
            purpose: "Nightly consolidate"
        )
        let row = FleetObserveRow(
            entity: entity,
            observation: nil,
            attention: .critical,
            why: "job.nightly: dead_man — last success 165h ago",
            correlatedChecks: ["dead_man"]
        )
        let health = HealthSnapshot(
            status: .red,
            checks: [
                "dead_man": HealthCheck(ok: false, detail: "last success 165h ago"),
            ]
        )
        let report = FleetObserveReport(
            observingHostRole: .hub,
            health: health,
            rows: [row]
        )
        let model = AndromedaHomeModel()
        model.apply(report: report)

        #expect(AndromedaHomeModel.menuStatus(from: report) == .red)
        #expect(model.fleetStatus == .red)
        #expect(model.fleetAttentionCount == 1)
        #expect(model.fleetDetail == "job.nightly: dead_man — last success 165h ago")
        #expect(model.commandCenter.healthStatus == .unhealthy("job.nightly: dead_man — last success 165h ago"))
    }

    @Test("Health-only failure still surfaces headlineWhy when rows empty")
    func healthOnlyHeadline() {
        let health = HealthSnapshot(
            status: .yellow,
            checks: [
                "git_committed": HealthCheck(ok: false, detail: "16 uncommitted"),
            ]
        )
        let report = FleetObserveReport(
            observingHostRole: .hub,
            health: health,
            rows: []
        )
        let model = AndromedaHomeModel()
        model.apply(report: report)

        #expect(model.fleetStatus == .yellow)
        #expect(model.fleetDetail == "git_committed: 16 uncommitted")
    }
}
