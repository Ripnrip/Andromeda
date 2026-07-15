/**
 * 🧪 CommandCenterSnapshots - Pixel Catalog for the Utility Popover
 *
 * "Sixteen stills: four moods × light/dark × medium/a11y2.
 * If a badge drifts or a button grows a mustache, the PNG tribunal notices."
 *
 * - The Spellbinding Visual Regression Alchemist of MemoryKit
 */

import AppKit
import SwiftUI
@preconcurrency import SnapshotTesting
import XCTest
@testable import MemoryKit

@MainActor
final class CommandCenterSnapshots: MemoryKitSnapshotTestCase {

    /// 🎪 Full matrix: state × color scheme × Dynamic Type
    func testCommandCenterCatalogMatrix() {
        for state in CommandCenterSnapshotState.allCases {
            for scheme in SnapshotCatalogSupport.colorSchemes {
                for typeSize in SnapshotCatalogSupport.dynamicTypeSizes {
                    let name = "cc-\(state.rawValue)-\(scheme.name)-\(typeSize.name)"
                    let model = SnapshotCatalogSupport.commandCenterModel(state: state)
                    let hosted = SnapshotCatalogSupport.hostingView(
                        CommandCenterView(model: model),
                        colorScheme: scheme.value,
                        dynamicType: typeSize.value,
                        size: SnapshotCatalogSupport.commandCenterSize
                    )

                    assertSnapshot(
                        of: hosted,
                        as: .image,
                        named: name,
                        file: #filePath,
                        testName: "CommandCenter"
                    )
                }
            }
        }
    }
}
