import Testing
@testable import AndromedaHUD

/// `@Observable` HUD model rituals (BIN-58) — expansion, health, search ledger, snap.
@Suite("AndromedaHUD model")
@MainActor
struct AndromedaHUDModelTests {
    private let screen = HUDScreenMetrics(
        visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900)
    )

    @Test("Default model wakes collapsed under menu-bar snap")
    func testDefaultState() {
        let model = AndromedaHUDModel()
        #expect(model.expansion == .collapsed)
        #expect(model.snapMode == .menuBar)
        #expect(model.health == .unknown)
        #expect(model.submissions.isEmpty)
        #expect(model.chromeSize == HUDSnapEngine.collapsedSize)
        #expect(model.showsAccessory == false)
    }

    @Test("Accessory flag expands chrome to console size")
    func testAccessoryChromeSize() {
        let model = AndromedaHUDModel(expansion: .expanded, showsAccessory: true)
        #expect(model.chromeSize == HUDSnapEngine.expandedWithAccessorySize)
    }

    @Test("Expand and collapse update chrome size + timing sample")
    func testExpandAndCollapse() {
        let model = AndromedaHUDModel()
        model.expandSearch()
        #expect(model.expansion == .expanded)
        #expect(model.chromeSize == HUDSnapEngine.expandedSize)
        #expect(model.lastTiming != nil)
        #expect(model.lastTiming?.operation == "hud.expand")
        model.collapse()
        #expect(model.expansion == .collapsed)
    }

    @Test("Toggle expansion flips collapsed and expanded")
    func testToggleExpansion() {
        let model = AndromedaHUDModel()
        model.toggleExpansion()
        #expect(model.expansion.isExpanded)
        model.toggleExpansion()
        #expect(!model.expansion.isExpanded)
    }

    @Test("Submit query records capability intent and clears field")
    func testSubmitQueryRecordsCapabilityIntent() {
        let model = AndromedaHUDModel(query: "recall floating hud")
        let intent = model.submitQuery()
        #expect(intent == .memoryRecall(query: "floating hud"))
        #expect(model.submissions.count == 1)
        #expect(model.submissions[0].intent.capabilityID == "memory.recall")
        #expect(model.query == "")
        #expect(model.lastTiming?.operation == "hud.search.route")
    }

    @Test("Empty submit does not append to ledger")
    func testSubmitEmptyDoesNotAppend() {
        let model = AndromedaHUDModel(query: "  ")
        _ = model.submitQuery()
        #expect(model.submissions.isEmpty)
    }

    @Test("End drag near menu bar snaps and settles")
    func testEndDragSnapsToMenuBar() {
        let model = AndromedaHUDModel()
        let size = model.chromeSize
        let proposed = HUDPoint(x: 40, y: screen.menuBarDockY - size.y - 8)
        model.endDrag(proposedOrigin: proposed, screen: screen)
        #expect(model.snapMode == .menuBar)
        #expect(abs(model.origin.y - (screen.menuBarDockY - size.y)) < 0.001)
        #expect(model.lastTiming?.operation == "hud.snap")
    }

    @Test("End drag with velocity records decay coast in footer")
    func testEndDragWithVelocityCoasts() {
        let model = AndromedaHUDModel(snapMode: .floating, origin: HUDPoint(x: 100, y: 300))
        model.endDrag(
            proposedOrigin: HUDPoint(x: 100, y: 300),
            screen: screen,
            velocity: HUDPoint(x: 700, y: 0)
        )
        #expect(model.origin.x > 100)
        #expect(model.lastMessage?.contains("decay coast") == true)
    }

    @Test("Dock to menu bar centers horizontally")
    func testDockToMenuBar() {
        let model = AndromedaHUDModel(snapMode: .floating)
        model.dockToMenuBar(screen: screen)
        #expect(model.snapMode == .menuBar)
        let expectedX = (screen.visibleFrame.width - model.chromeSize.x) / 2
        #expect(abs(model.origin.x - expectedX) < 0.001)
    }

    @Test("Apply health updates pulse and accessibility label")
    func testApplyHealth() {
        let model = AndromedaHUDModel()
        model.applyHealth(.degraded, detail: "cache")
        #expect(model.health == .degraded)
        #expect(model.healthDetail == "cache")
        #expect(model.accessibilityLabel.contains("degraded"))
    }

    @Test("Clear submissions resets ledger and timing")
    func testClearSubmissions() {
        let model = AndromedaHUDModel(query: "store hello")
        _ = model.submitQuery()
        model.clearSubmissions()
        #expect(model.submissions.isEmpty)
        #expect(model.lastMessage == nil)
        #expect(model.lastTiming == nil)
    }
}
