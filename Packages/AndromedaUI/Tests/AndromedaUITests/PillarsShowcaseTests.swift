import XCTest
@testable import AndromedaUI

@MainActor
final class PillarsShowcaseTests: XCTestCase {

    /// The exported pillars wave is intentionally seven cards today: six grid cards
    /// plus the wider retrieval bench beneath them.
    func testSampleDataMatchesShowcaseShape() {
        XCTAssertEqual(AndromedaPillarsData.skills.count, 4)
        XCTAssertEqual(AndromedaPillarsData.servers.count, 5)
        XCTAssertEqual(AndromedaPillarsData.memoryFamilies.count, 6)
        XCTAssertEqual(AndromedaPillarsData.retrievalLanes.count, 5)
    }

    /// Client-facing surfaces should keep using stable capability language instead of
    /// leaking provider brands into the package showcase.
    func testRetrievalLaneNamesStayCapabilityLevel() {
        let names = AndromedaPillarsData.retrievalLanes.map(\.name).joined(separator: " ").lowercased()
        XCTAssertFalse(names.contains("anthropic"))
        XCTAssertFalse(names.contains("openai"))
        XCTAssertFalse(names.contains("claude"))
        XCTAssertFalse(names.contains("gpt"))
    }

    /// Skill names should stay stable and unique so previews, screenshots, and future
    /// gallery/specimen plumbing have deterministic identifiers.
    func testSkillRowsUseUniqueNames() {
        let names = AndromedaPillarsData.skills.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
    }
}
