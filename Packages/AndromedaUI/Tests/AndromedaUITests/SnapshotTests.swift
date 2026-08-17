import XCTest
import SwiftUI
import SnapshotTesting
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Point-Free snapshot coverage: every specimen is captured in both dark
/// and light mode. Snapshots record the initial (pre-`onAppear`) frame,
/// which the synchronous hosting render produces deterministically.
///
/// Cross-platform via `SnapshotHosting` — this suite previously compiled
/// only under `canImport(UIKit)`, so the macOS CI lane (the only lane that
/// runs) silently never executed it. Every animation in `AndromedaCatalogue`
/// now gets dark + light baselines on the runner.
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
            for dark in [true, false] {
                let root = ZStack { AndromedaSurface(); specimen.view }
                    .frame(width: 220, height: 170)

                let host = SnapshotHosting.makeHost(root, CGSize(width: 220, height: 170), dark: dark)

                assertSnapshot(
                    of: host,
                    as: .image(precision: 0.98, perceptualPrecision: 0.97),
                    named: "\(specimen.name)-\(dark ? "dark" : "light")",
                    file: #filePath,
                    testName: #function
                )
            }
        }
    }
}
