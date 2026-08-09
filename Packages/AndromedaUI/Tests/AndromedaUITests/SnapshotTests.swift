#if canImport(UIKit)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

/// Point-Free snapshot coverage: every specimen is captured in both dark
/// and light mode. Snapshots record the initial (pre-`onAppear`) frame,
/// which the synchronous hosting render produces deterministically.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter AndromedaSnapshotTests`
@MainActor
final class AndromedaSnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: AndromedaUISnapshotSupport.recordMode) {
            super.invokeTest()
        }
    }

    func testSpecimensDarkAndLight() throws {
        try AndromedaUISnapshotSupport.requireBaselines()
        for specimen in AndromedaCatalogue.specimens {
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                let root = ZStack { AndromedaSurface(); specimen.view }
                    .frame(width: 220, height: 170)
                    .environment(\.colorScheme, scheme)

                let host = UIHostingController(rootView: root)
                host.view.frame = CGRect(x: 0, y: 0, width: 220, height: 170)
                host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light

                assertSnapshot(
                    of: host,
                    as: .image(precision: 0.98, perceptualPrecision: 0.97),
                    named: "\(specimen.name)-\(scheme == .dark ? "dark" : "light")"
                )
            }
        }
    }
}
#endif
