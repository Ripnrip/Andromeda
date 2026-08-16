import XCTest
@testable import AndromedaUI

@MainActor
final class AndromedaCatalogueTests: XCTestCase {

    func testCatalogueShipsEveryAnimation() {
        // 8 core + 25 extended + 24 transitions + 27 wild
        XCTAssertEqual(AndromedaCatalogue.specimens.count, 84)
    }

    func testSpecimenNamesAreUnique() {
        let names = AndromedaCatalogue.specimens.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Specimen names must be unique")
    }
}
