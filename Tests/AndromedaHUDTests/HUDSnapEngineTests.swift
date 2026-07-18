import Testing
@testable import AndromedaHUD

/// Geometry / Ice-style snap proofs for the floating HUD (BIN-56 / BIN-60).
@Suite("HUD snap engine")
struct HUDSnapEngineTests {
    private let screen = HUDScreenMetrics(
        visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 25,
        snapDistance: 28
    )

    @Test("Dock Y equals the top of the visible frame")
    func testMenuBarDockYMatchesVisibleTop() {
        #expect(screen.menuBarDockY == 900)
    }

    @Test("Origin near the menu bar resolves to menuBar")
    func testResolveModeSnapsWhenNearMenuBar() {
        let size = HUDSnapEngine.collapsedSize
        let origin = HUDPoint(x: 100, y: screen.menuBarDockY - size.y - 10)
        let mode = HUDSnapEngine.resolveMode(
            proposedOrigin: origin,
            size: size,
            screen: screen
        )
        #expect(mode == .menuBar)
    }

    @Test("Origin far from the menu bar stays floating")
    func testResolveModeFloatsWhenFarFromMenuBar() {
        let size = HUDSnapEngine.collapsedSize
        let origin = HUDPoint(x: 100, y: 200)
        let mode = HUDSnapEngine.resolveMode(
            proposedOrigin: origin,
            size: size,
            screen: screen
        )
        #expect(mode == .floating)
    }

    @Test("Settle docks under the menu bar and clamps into the visible frame")
    func testSettleDocksAndClamps() {
        let size = HUDSnapEngine.collapsedSize
        let proposed = HUDPoint(x: -80, y: screen.menuBarDockY - size.y - 5)
        let settled = HUDSnapEngine.settle(
            proposedOrigin: proposed,
            size: size,
            screen: screen
        )
        #expect(settled.mode == .menuBar)
        #expect(abs(settled.origin.x - 0) < 0.001)
        #expect(abs(settled.origin.y - (screen.menuBarDockY - size.y)) < 0.001)
    }

    @Test("Default menu-bar origin is horizontally centered")
    func testDefaultMenuBarOriginCentersHorizontally() {
        let size = HUDSnapEngine.collapsedSize
        let origin = HUDSnapEngine.defaultMenuBarOrigin(size: size, screen: screen)
        #expect(abs(origin.x - ((1440 - size.x) / 2)) < 0.001)
        #expect(abs(origin.y - (screen.menuBarDockY - size.y)) < 0.001)
    }

    @Test("Negative width/height normalize correctly")
    func testRectNormalization() {
        let rect = HUDRect(x: 10, y: 10, width: -40, height: -20).normalized()
        #expect(abs(rect.x - (-30)) < 0.001)
        #expect(abs(rect.y - (-10)) < 0.001)
        #expect(abs(rect.width - 40) < 0.001)
        #expect(abs(rect.height - 20) < 0.001)
        #expect(rect.contains(HUDPoint(x: 0, y: 0)))
    }
}
