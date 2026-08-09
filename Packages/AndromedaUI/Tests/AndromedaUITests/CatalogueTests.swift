import XCTest
@testable import AndromedaUI

@MainActor
final class AndromedaCatalogueTests: XCTestCase {

    func testCatalogueShipsEveryAnimation() {
        // 8 core + 25 in-the-wild + 2 event-driven
        XCTAssertEqual(AndromedaCatalogue.specimens.count, 35)
    }

    func testSpecimenNamesAreUnique() {
        let names = AndromedaCatalogue.specimens.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Specimen names must be unique")
    }
}
