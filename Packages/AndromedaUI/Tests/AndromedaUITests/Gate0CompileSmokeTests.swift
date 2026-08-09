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

    func testInferWriteIsNotAdvertisedAsLLMProxy() {
        let infer = BarPillar.all.first { $0.id == "infer.write" }
        XCTAssertEqual(infer?.name, "infer.write")
        XCTAssertEqual(infer?.health, .spec)
        XCTAssertEqual(Pillar.models.title, "infer.write")
        XCTAssertEqual(Pillar.models.status, .specified)
        XCTAssertFalse(Pillar.models.blurb.lowercased().contains("llm"))
    }

    func testModelCatalogHidesProviderBrands() {
        let banned = ["claude", "gpt", "gemini", "grok", "kimi", "deepseek", "openai", "anthropic"]
        let names = ControlPlaneData.models.map(\.name) + ControlPlaneData.speed.map(\.name)
        for name in names {
            let lower = name.lowercased()
            for brand in banned {
                XCTAssertFalse(lower.contains(brand), "client catalog leaked provider brand \(brand) in \(name)")
            }
            XCTAssertTrue(name.hasPrefix("infer.write"), "expected capability alias, got \(name)")
        }
    }

    func testMemoryLayersOnlyExposeShippedSwiftData() {
        XCTAssertEqual(ControlPlaneData.layers.map(\.key), ["swiftdata"])
        let joined = ControlPlaneData.layers.map { $0.name + $0.path + $0.detail }.joined().lowercased()
        for brand in ["realm", "qdrant", "keychain", "letta"] {
            XCTAssertFalse(joined.contains(brand), "storage surface leaked private brand \(brand)")
        }
    }

    func testSkillsCapabilitiesStaySpecifiedUntilBuilt() async {
        for item in ControlPlaneData.items(for: .skills) {
            XCTAssertEqual(item.status, "spec", "\(item.ref) should be spec until registry ships")
        }
        let probe = UnwiredDoctorProbe()
        let checks = await probe.run()
        XCTAssertFalse(checks.isEmpty)
        XCTAssertTrue(checks.allSatisfy { !$0.ok }, "unwired doctor must not report success")
    }
}
