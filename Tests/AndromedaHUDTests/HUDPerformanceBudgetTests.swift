import Testing
@testable import AndromedaHUD

/// Aggressive latency budget proofs (BIN-59) — local work must stay sub-frame.
@Suite("HUD performance budgets")
struct HUDPerformanceBudgetTests {
    @Test("Budgets stay aggressive and under one second")
    func testBudgetsAreAggressive() {
        #expect(HUDPerformanceBudget.renderFrameMilliseconds == 16)
        #expect(HUDPerformanceBudget.expandInteractionMilliseconds <= 50)
        #expect(HUDPerformanceBudget.snapSettleMilliseconds <= 16)
        #expect(HUDPerformanceBudget.searchRouteMilliseconds <= 5)
        #expect(HUDPerformanceBudget.hardCeilingMilliseconds < 1_000)
    }

    @Test("Search route meets its budget")
    func testSearchRouteMeetsBudget() {
        let sample = HUDStopwatch.measure(
            operation: "hud.search.route",
            budgetMilliseconds: HUDPerformanceBudget.searchRouteMilliseconds
        ) {
            _ = HUDSearchRouter.route("recall performance budgets")
            _ = HUDSearchRouter.route("store a note")
            _ = HUDSearchRouter.route("what is the fleet pulse?")
        }
        #expect(
            sample.isWithinBudget,
            "search route took \(sample.elapsedMilliseconds)ms (budget \(sample.budgetMilliseconds)ms)"
        )
        #expect(!sample.breachedHardCeiling)
    }

    @Test("Snap settle meets its budget across many settles")
    func testSnapSettleMeetsBudget() {
        let screen = HUDScreenMetrics(
            visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let sample = HUDStopwatch.measure(
            operation: "hud.snap",
            budgetMilliseconds: HUDPerformanceBudget.snapSettleMilliseconds
        ) {
            for i in 0..<200 {
                _ = HUDSnapEngine.settle(
                    proposedOrigin: HUDPoint(x: Double(i), y: Double(800 - i)),
                    size: HUDSnapEngine.collapsedSize,
                    screen: screen
                )
            }
        }
        #expect(
            sample.isWithinBudget,
            "snap settle took \(sample.elapsedMilliseconds)ms (budget \(sample.budgetMilliseconds)ms)"
        )
    }

    @Test("Timing sample flags slow work without hard-ceiling breach")
    func testTimingSampleFlagsSlowWork() {
        let sample = HUDTimingSample(
            operation: "hud.expand",
            elapsedMilliseconds: 80,
            budgetMilliseconds: 50
        )
        #expect(!sample.isWithinBudget)
        #expect(!sample.breachedHardCeiling)
    }
}
