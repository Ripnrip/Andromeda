import AndromedaHostOps
import AndromedaPowerKit
import Foundation
import Testing

@Suite("PowerLeaseCoordinator")
struct PowerLeaseCoordinatorTests {

    // MARK: - Reference counting

    @Test("reference counting keeps system awake until final lease releases")
    func referenceCounting() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        let render = await coordinator.acquire(
            owner: "video-agent",
            reason: "Render",
            requirements: [.preventSystemSleep]
        )
        let upload = await coordinator.acquire(
            owner: "testflight-agent",
            reason: "Upload",
            requirements: [.preventSystemSleep]
        )

        var status = await coordinator.status()
        #expect(status.activeLeases.count == 2)
        #expect(status.preventSystemSleep == true)

        await coordinator.release(render)
        status = await coordinator.status()
        #expect(status.activeLeases.count == 1)
        #expect(status.preventSystemSleep == true)

        await coordinator.release(upload)
        status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
        #expect(status.preventSystemSleep == false)
    }

    // MARK: - Display aggregation

    @Test("display requirement aggregates across leases and clears when released")
    func displayAggregation() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        let render = await coordinator.acquire(
            owner: "video-agent",
            reason: "Render",
            requirements: [.preventSystemSleep]
        )
        _ = await coordinator.acquire(
            owner: "ui-agent",
            reason: "Drive Simulator",
            requirements: [.preventSystemSleep, .preventDisplaySleep]
        )

        var status = await coordinator.status()
        #expect(status.preventSystemSleep == true)
        #expect(status.preventDisplaySleep == true)

        // Releasing the display-driving lease should clear display assertion
        // but system sleep should stay inhibited while render remains.
        let uiLease = status.activeLeases.first { $0.owner == "ui-agent" }!
        await coordinator.release(uiLease)

        status = await coordinator.status()
        #expect(status.preventSystemSleep == true)
        #expect(status.preventDisplaySleep == false)

        await coordinator.release(render)
    }

    // MARK: - Duplicate release safety

    @Test("releasing the same lease twice is a no-op")
    func duplicateReleaseSafety() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        let lease = await coordinator.acquire(
            owner: "agent",
            reason: "test",
            requirements: [.preventSystemSleep]
        )

        await coordinator.release(lease)
        await coordinator.release(lease) // must not crash or double-decrement

        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
    }

    // MARK: - Release all

    @Test("releaseAll clears every lease and allows sleep")
    func releaseAllBehavior() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        _ = await coordinator.acquire(owner: "a", reason: "r1", requirements: [.preventSystemSleep])
        _ = await coordinator.acquire(owner: "b", reason: "r2", requirements: [.preventSystemSleep])

        await coordinator.releaseAll()

        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
        #expect(status.preventSystemSleep == false)
    }

    // MARK: - Event recording

    @Test("event log captures acquire and release events")
    func eventRecording() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        let lease = await coordinator.acquire(
            owner: "video-agent",
            reason: "Render",
            requirements: [.preventSystemSleep]
        )
        await coordinator.release(lease)

        let events = await coordinator.eventLog()
        // Should have: acquired, assertionChanged, released, assertionChanged
        #expect(events.count >= 3)
        #expect(events.contains { $0.kind == .acquired })
        #expect(events.contains { $0.kind == .released })
        #expect(events.contains { $0.kind == .assertionChanged })
    }

    // MARK: - Doctor summary

    @Test("doctor section shows zero leases when idle")
    func doctorIdleSummary() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())
        let section = await coordinator.doctorSection()
        #expect(section.contains("0"))
        #expect(section.contains("ProcessInfo"))
    }

    @Test("doctor section shows active owners when leases held")
    func doctorActiveSummary() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())
        _ = await coordinator.acquire(
            owner: "video-agent",
            reason: "Render Andromeda Demo",
            requirements: [.preventSystemSleep]
        )
        let section = await coordinator.doctorSection()
        #expect(section.contains("video-agent"))
        #expect(section.contains("Render Andromeda Demo"))
        #expect(section.contains("yes"))
    }

    // MARK: - Summary for checklist

    @Test("PowerLeaseSummary correctly converts from PowerAssertionStatus")
    func summaryConversion() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())
        _ = await coordinator.acquire(
            owner: "z-agent",
            reason: "test",
            requirements: [.preventSystemSleep, .preventDisplaySleep]
        )
        _ = await coordinator.acquire(
            owner: "a-agent",
            reason: "test2",
            requirements: [.preventSystemSleep]
        )

        let summary = await coordinator.summary()
        #expect(summary.activeLeaseCount == 2)
        #expect(summary.preventSystemSleep == true)
        #expect(summary.preventDisplaySleep == true)
        // Owners sorted
        #expect(summary.owners == ["a-agent", "z-agent"])
    }

    // MARK: - Doctor integration

    @Test("doctor checklist includes power section when powerStatus is provided")
    func doctorIncludesPowerSection() {
        let summary = PowerLeaseSummary(
            activeLeaseCount: 2,
            preventSystemSleep: true,
            preventDisplaySleep: false,
            owners: ["render-agent", "upload-agent"]
        )
        let report = HostDiagnostics.doctor(
            runtimeReachable: true,
            brokerTokenConfigured: true,
            secrets: [],
            qdrantReachable: nil,
            journalPathExists: true,
            vaultPathExists: true,
            guestConfigText: nil,
            toolsListNames: nil,
            vmSignalDetected: false,
            menubarAvailable: false,
            powerStatus: summary
        )
        #expect(report.items.contains { $0.id == "power.leases" })
        let powerItem = report.items.first { $0.id == "power.leases" }!
        #expect(powerItem.status == .pass)
        #expect(powerItem.detail.contains("render-agent"))
    }

    @Test("doctor checklist omits power section when powerStatus is nil")
    func doctorOmitsPowerSectionWhenNil() {
        let report = HostDiagnostics.doctor(
            runtimeReachable: true,
            brokerTokenConfigured: true,
            secrets: [],
            qdrantReachable: nil,
            journalPathExists: true,
            vaultPathExists: true,
            guestConfigText: nil,
            toolsListNames: nil,
            vmSignalDetected: false,
            menubarAvailable: false
        )
        #expect(!report.items.contains { $0.id == "power.leases" })
    }

    // MARK: - Scoped lease (withLease)

    @Test("withLease releases on success")
    func withLeaseSuccess() async throws {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        let result = try await coordinator.withLease(
            owner: "test-agent",
            reason: "unit test",
            requirements: [.preventSystemSleep]
        ) {
            42
        }
        #expect(result == 42)

        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
    }

    @Test("withLease releases on thrown error")
    func withLeaseError() async {
        let coordinator = PowerLeaseCoordinator(backend: NoopBackend())

        await #expect(throws: TestError.self) {
            try await coordinator.withLease(
                owner: "test-agent",
                reason: "unit test",
                requirements: [.preventSystemSleep]
            ) {
                throw TestError.boom
            }
        }

        let status = await coordinator.status()
        #expect(status.activeLeases.count == 0)
    }
}

// MARK: - Test helpers

private enum TestError: Error {
    case boom
}

/// No-op backend for tests — does not touch macOS power state.
private actor NoopBackend: PowerAssertionBackend {
    func apply(preventSystemSleep: Bool, preventDisplaySleep: Bool, reason: String) async {}
    func clear() async {}
}
