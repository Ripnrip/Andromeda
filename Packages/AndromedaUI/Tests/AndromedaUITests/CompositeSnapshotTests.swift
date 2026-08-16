import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

/// Snapshot coverage for the joined surfaces — the composites are the
/// contract the app actually ships, so they are captured whole, at their
/// natural size, in both schemes.
@MainActor
final class AndromedaCompositeSnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: AndromedaUISnapshotSupport.recordMode) {
            super.invokeTest()
        }
    }

    func testComposites() {
        for composite in AndromedaComposites.all {
            for dark in [true, false] {
                let host = andromedaHost(
                    composite.view.andromedaFrozen(),
                    composite.size,
                    dark: dark
                )
                assertSnapshot(
                    of: host,
                    as: .image(precision: 0.98, perceptualPrecision: 0.96),
                    named: "\(composite.name)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    /// The composite gallery wall — one capture that regresses layout across
    /// every joined surface at once.
    func testCompositeGallery() {
        let host = andromedaHost(
            AndromedaCompositeGallery().andromedaFrozen(),
            CGSize(width: 1240, height: 2400),
            dark: true
        )
        assertSnapshot(of: host, as: .image(precision: 0.97, perceptualPrecision: 0.95), named: "composite-wall")
    }

    /// The specimen wall — same idea for the individual components.
    func testSpecimenGallery() {
        let host = andromedaHost(
            AndromedaGallery().andromedaFrozen(),
            CGSize(width: 1000, height: 2600),
            dark: true
        )
        assertSnapshot(of: host, as: .image(precision: 0.97, perceptualPrecision: 0.95), named: "specimen-wall")
    }
}
