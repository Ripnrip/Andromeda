import XCTest
@testable import AndromedaPowerKit

final class PowerAssertionManagerTests: XCTestCase {
    func testReferenceCountingKeepsSystemAwakeUntilFinalLeaseReleases() async {
        let backend = RecordingBackend()
        let manager = PowerAssertionManager(backend: backend)

        let render = await manager.acquire(
            owner: "video-agent",
            reason: "Render",
            requirements: [.preventSystemSleep]
        )

        let upload = await manager.acquire(
            owner: "testflight-agent",
            reason: "Upload",
            requirements: [.preventSystemSleep]
        )

        var status = await manager.status()
        XCTAssertEqual(status.activeLeases.count, 2)
        XCTAssertTrue(status.preventSystemSleep)

        await manager.release(render)

        status = await manager.status()
        XCTAssertEqual(status.activeLeases.count, 1)
        XCTAssertTrue(status.preventSystemSleep)

        await manager.release(upload)

        status = await manager.status()
        XCTAssertEqual(status.activeLeases.count, 0)
        XCTAssertFalse(status.preventSystemSleep)
    }

    func testDisplayRequirementAggregatesAcrossLeases() async {
        let backend = RecordingBackend()
        let manager = PowerAssertionManager(backend: backend)

        let render = await manager.acquire(
            owner: "video-agent",
            reason: "Render",
            requirements: [.preventSystemSleep]
        )

        let ui = await manager.acquire(
            owner: "ui-agent",
            reason: "Drive Simulator",
            requirements: [.preventSystemSleep, .preventDisplaySleep]
        )

        var status = await manager.status()
        XCTAssertTrue(status.preventSystemSleep)
        XCTAssertTrue(status.preventDisplaySleep)

        await manager.release(ui)

        status = await manager.status()
        XCTAssertTrue(status.preventSystemSleep)
        XCTAssertFalse(status.preventDisplaySleep)

        await manager.release(render)
    }
}

private actor RecordingBackend: PowerAssertionBackend {
    func apply(
        preventSystemSleep: Bool,
        preventDisplaySleep: Bool,
        reason: String
    ) async {}

    func clear() async {}
}
