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
        // Honesty language may mention generation; never advertise as an LLM proxy product.
        let blurb = Pillar.models.blurb.lowercased()
        XCTAssertFalse(blurb.contains("llm proxy"))
        XCTAssertTrue(blurb.contains("episodic") || blurb.contains("alias"))
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

    func testDreamingStatesHideProviderBrands() {
        // The dreaming board renders client-visible badges/logs — same curtain
        // law as the model catalog: capability IDs only, never upstream brands.
        let banned = ["sonnet", "haiku", "gpt", "claude", "gemini", "grok",
                      "linear", "notion", "qdrant", "graphiti"]
        var surfaces: [String] = []
        surfaces.append(contentsOf: ProxyState.allCases.map(\.badge))
        surfaces.append(contentsOf: ProxyState.allCases.map(\.log))
        surfaces.append(contentsOf: ProxyState.models)
        surfaces.append(contentsOf: MCPState.allCases.map(\.badge))
        surfaces.append(contentsOf: MCPState.allCases.map(\.log))
        surfaces.append(contentsOf: FabricState.allCases.map(\.badge))
        surfaces.append(contentsOf: FabricState.allCases.map(\.log))
        surfaces.append(contentsOf: FabricState.allCases.map(\.label))
        for state in FleetState.allCases {
            surfaces.append(state.badge)
            surfaces.append(state.log)
        }
        for surface in surfaces {
            let lower = surface.lowercased()
            for brand in banned {
                XCTAssertFalse(lower.contains(brand),
                               "dreaming surface leaked brand \(brand) in \(surface)")
            }
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
