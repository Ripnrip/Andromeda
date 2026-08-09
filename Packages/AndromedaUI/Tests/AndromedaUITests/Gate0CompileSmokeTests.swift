import XCTest
import SwiftUI
@testable import AndromedaUI

/// Non-visual Gate 0 coverage — must pass without snapshot baselines.
final class Gate0CompileSmokeTests: XCTestCase {
    func testBarPillarCatalogHasSixCapabilities() {
        XCTAssertEqual(BarPillar.all.count, 6)
        XCTAssertEqual(Set(BarPillar.all.map(\.id)).count, 6)
    }

    func testControlPlanePillarsIncludeSearchAndSettings() {
        XCTAssertTrue(Pillar.allCases.contains(.search))
        XCTAssertTrue(Pillar.allCases.contains(.settings))
        XCTAssertEqual(Pillar.allCases.count, 8)
    }

    func testPaletteTokensResolve() {
        // Touch every Gate 0 token so duplicate Color extensions fail at compile time.
        let tokens: [Color] = [
            .andromedaVoid, .andromedaPanel, .andromedaTeal, .andromedaGlow,
            .andromedaLive, .andromedaMuted, .andromedaAmber, .andromedaDim, .andromedaInk,
        ]
        XCTAssertEqual(tokens.count, 9)
    }

    func testMemoryKindsUseStableIndexIds() {
        let ids = AndromedaMemory.kinds.map(\.id)
        XCTAssertEqual(ids, ["01", "02", "03", "04", "05", "06", "07", "08"])
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
