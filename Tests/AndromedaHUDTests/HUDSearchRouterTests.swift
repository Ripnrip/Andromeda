import Testing
@testable import AndromedaHUD

/// Ask AI / memory.* routing proofs (BIN-57) — capability IDs only, no tracker brands.
@Suite("HUD search router")
struct HUDSearchRouterTests {
    @Test("Empty input routes to empty intent")
    func testEmptyInput() {
        #expect(HUDSearchRouter.route("   ") == .empty)
        #expect(HUDSearchRouter.route("").capabilityID == "hud.search.empty")
    }

    @Test("Recall prefixes map to memory.recall")
    func testRecallPrefixes() {
        #expect(
            HUDSearchRouter.route("recall launch entities")
                == .memoryRecall(query: "launch entities")
        )
        #expect(
            HUDSearchRouter.route("memory.recall vault path")
                == .memoryRecall(query: "vault path")
        )
        #expect(
            HUDSearchRouter.route("/recall health")
                == .memoryRecall(query: "health")
        )
    }

    @Test("Store prefixes map to memory.store")
    func testStorePrefixes() {
        #expect(
            HUDSearchRouter.route("store note about snap")
                == .memoryStore(content: "note about snap")
        )
        #expect(
            HUDSearchRouter.route("memory.store sealed fact")
                == .memoryStore(content: "sealed fact")
        )
    }

    @Test("Journal prefixes map to memory.journal")
    func testJournalPrefixes() {
        #expect(
            HUDSearchRouter.route("journal today")
                == .memoryJournal(query: "today")
        )
        #expect(
            HUDSearchRouter.route("session dump last hour")
                == .memoryJournal(query: "last hour")
        )
    }

    @Test("Bare text becomes infer.write")
    func testBareTextBecomesInferWrite() {
        let intent = HUDSearchRouter.route("summarize fleet health")
        #expect(intent == .inferWrite(prompt: "summarize fleet health"))
        #expect(intent.capabilityID == "infer.write")
    }

    @Test("Display summaries never mention tracker brands")
    func testDisplaySummaryNeverMentionsTrackerBrands() {
        let summaries = [
            HUDSearchIntent.memoryRecall(query: "x").displaySummary,
            HUDSearchIntent.memoryStore(content: "y").displaySummary,
            HUDSearchIntent.inferWrite(prompt: "z").displaySummary,
        ]
        for summary in summaries {
            let lower = summary.lowercased()
            #expect(!lower.contains("linear"))
            #expect(!lower.contains("multica"))
            #expect(!lower.contains("habitat"))
        }
    }
}
