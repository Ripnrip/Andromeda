/**
 * 🎭 LaunchEntityRosterViewTests - Visible Playbill Quality Ritual
 *
 * "We poke every roster face — loading, empty, hub-full, satellite-na —
 * until the marquee is loud enough that silent watchdogs have nowhere to hide."
 *
 * - The Theatrical QA Virtuoso of Fleet Observability
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("🎪 Launch Entity Roster View Suite")
@MainActor
struct LaunchEntityRosterViewTests {

    @Test("📜 Roster states include loading/empty/hub-full/satellite-na")
    func testStateVocabulary() {
        let states = LaunchEntityRosterState.allCases
        #expect(states.count == 4)
        #expect(states.contains(.loading))
        #expect(states.contains(.empty))
        #expect(states.contains(.hubFull))
        #expect(states.contains(.satelliteNA))
        #expect(LaunchEntityRosterState.hubFull.rawValue == "hub-full")
        #expect(LaunchEntityRosterState.satelliteNA.rawValue == "satellite-na")
    }

    @Test("✨ Default model awakens loading with empty cast")
    func testDefaultModel() {
        let model = LaunchEntityRosterModel()
        #expect(model.state == .loading)
        #expect(model.entities.isEmpty)
        #expect(model.reduceMotion == false)
        #expect(model.accessibilityLabel.contains("Loading"))
    }

    @Test("🌟 apply(registry:) maps hub → hubFull with Mini still visible")
    func testApplyHubRegistry() {
        let sink = RecordingLaunchEntityTelemetrySink()
        let registry = LaunchEntityRegistry(
            observingHostRole: .hub,
            launchctl: NullLaunchctlObserver(),
            telemetry: sink
        ).observingRefreshed()

        let model = LaunchEntityRosterModel()
        model.apply(registry: registry)

        #expect(model.state == .hubFull)
        #expect(model.entities.count == 16) // 9 multibrain + 6 HAB-42 + Mini
        #expect(model.entities.contains { $0.hostRole == .isolated })
        #expect(model.lastTelemetry?.isolatedMiniFlagged == true)
    }

    @Test("🛰️ apply(registry:) maps satellite → satelliteNA")
    func testApplySatelliteRegistry() {
        let registry = LaunchEntityRegistry(
            observingHostRole: .satellite,
            launchctl: NullLaunchctlObserver()
        ).observingRefreshed()

        let model = LaunchEntityRosterModel()
        model.apply(registry: registry)
        #expect(model.state == .satelliteNA)
        #expect(model.entities.contains { $0.status == .notApplicable })
    }

    @Test("🌙 Empty registry presents empty state")
    func testEmptyRegistry() {
        let registry = LaunchEntityRegistry(
            observingHostRole: .hub,
            entities: []
        )
        let model = LaunchEntityRosterModel()
        model.apply(registry: registry)
        #expect(model.state == .empty)
        #expect(model.entities.isEmpty)
    }

    @Test("🌊 Fixtures produce deterministic hub + satellite casts")
    func testFixtures() {
        let hub = LaunchEntityRosterFixtures.hubFullEntities()
        #expect(hub.count == 4)
        #expect(hub.contains { $0.hostRole == .isolated })
        #expect(LaunchEntityRosterFixtures.hubFullTelemetry().isolatedMiniFlagged)

        let sat = LaunchEntityRosterFixtures.satelliteNAEntities()
        #expect(sat.contains { $0.status == .notApplicable })
        #expect(LaunchEntityRosterFixtures.satelliteTelemetry().notApplicable >= 2)
    }

    @Test("🎭 LaunchEntityRosterView constructs for every state")
    func testViewConstructsAllStates() {
        for state in LaunchEntityRosterState.allCases {
            let model = LaunchEntityRosterFixtures.model(state, reduceMotion: true)
            let view = LaunchEntityRosterView(model: model, honorSystemReduceMotion: false)
            _ = view.body
            #expect(model.state == state)
        }
    }

    @Test("💎 Reduce-motion fixture freezes motion flag")
    func testReduceMotionFixture() {
        let model = LaunchEntityRosterFixtures.model(.hubFull, reduceMotion: true)
        #expect(model.reduceMotion == true)
        #expect(model.state == .hubFull)
    }
}
