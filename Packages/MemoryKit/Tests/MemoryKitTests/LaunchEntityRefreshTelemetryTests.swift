/**
 * 🎭 LaunchEntityRefreshTelemetryTests - Day-One Pulse Quality Ritual
 *
 * "We count the cast after every curtain call — running, stopped, n/a —
 * and make sure the Mini tunnel raises the isolated flag every time."
 *
 * - The Theatrical QA Virtuoso of Fleet Observability
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("📡 Launch Entity Refresh Telemetry Suite")
struct LaunchEntityRefreshTelemetryTests {

    @Test("🌐 refresh() emits status counts + isolated Mini flag")
    func testRefreshEmitsTelemetryWithIsolatedMini() {
        let sink = RecordingLaunchEntityTelemetrySink()
        let mock = MockLaunchctlObserver(observations: [
            "com.multibrain.letta": LaunchObservation(isLoaded: true, isRunning: true, pid: 42),
            "com.multibrain.dreamcatcher": LaunchObservation(isLoaded: true, isRunning: true, pid: 7),
        ])

        var registry = LaunchEntityRegistry(
            observingHostRole: .hub,
            launchctl: mock,
            telemetry: sink
        )
        let pulse = registry.refresh()

        #expect(sink.events.count == 1)
        #expect(pulse.total == 16) // 9 multibrain + 6 HAB-42 + Mini
        #expect(pulse.running == 2)
        #expect(pulse.stopped >= 1)
        #expect(pulse.isolatedMiniFlagged == true)
        #expect(pulse.isolatedCount == 1)
        #expect(pulse.observingHostRole == .hub)
        #expect(registry.lastTelemetry == pulse)
        #expect(pulse.displaySummary.contains("isolatedMini=flagged"))
    }

    @Test("🛰️ Satellite refresh tallies n/a hub services")
    func testSatelliteRefreshCountsNotApplicable() {
        let sink = RecordingLaunchEntityTelemetrySink()
        var registry = LaunchEntityRegistry(
            observingHostRole: .satellite,
            launchctl: NullLaunchctlObserver(),
            telemetry: sink
        )
        let pulse = registry.refresh()

        // letta, bridge, shim, index-server + multica.daemon/stack + habitat.boot
        #expect(pulse.notApplicable >= 7)
        #expect(pulse.isolatedMiniFlagged == true)
        #expect(sink.lastEvent?.notApplicable == pulse.notApplicable)
    }

    @Test("🌙 refreshStatuses alone does not emit telemetry")
    func testRefreshStatusesIsSilent() {
        let sink = RecordingLaunchEntityTelemetrySink()
        var registry = LaunchEntityRegistry(
            observingHostRole: .hub,
            launchctl: NullLaunchctlObserver(),
            telemetry: sink
        )
        registry.refreshStatuses()
        #expect(sink.events.isEmpty)
        #expect(registry.lastTelemetry == nil)
    }

    @Test("🧮 Summarize empty roster flags Mini absent")
    func testSummarizeEmpty() {
        let pulse = LaunchEntityRefreshTelemetry.summarize(
            entities: [],
            observingHostRole: .hub
        )
        #expect(pulse.total == 0)
        #expect(pulse.isolatedMiniFlagged == false)
        #expect(pulse.displaySummary.contains("isolatedMini=absent"))
    }
}
