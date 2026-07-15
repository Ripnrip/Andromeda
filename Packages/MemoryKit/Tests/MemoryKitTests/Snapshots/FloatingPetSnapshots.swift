/**
 * 🧪 FloatingPetSnapshots - Pixel Catalog for the Ambient Familiar
 *
 * "Thirty-two stills: four moods × reduceMotion × light/dark × medium/a11y2.
 * The pocket constellation must freeze the same way every curtain call."
 *
 * - The Theatrical Visual Regression Virtuoso of Phase-4 Delight
 */

import AppKit
import SwiftUI
@preconcurrency import SnapshotTesting
import XCTest
@testable import MemoryKit

@MainActor
final class FloatingPetSnapshots: MemoryKitSnapshotTestCase {

    /// 🔮 Full matrix: ambient × reduceMotion × color scheme × Dynamic Type
    func testFloatingPetCatalogMatrix() {
        let reduceMotionFlags: [(name: String, value: Bool)] = [
            ("motion", false),
            ("reduceMotion", true),
        ]

        for ambient in FloatingPetAmbientState.allCases {
            for motion in reduceMotionFlags {
                for scheme in SnapshotCatalogSupport.colorSchemes {
                    for typeSize in SnapshotCatalogSupport.dynamicTypeSizes {
                        let name = "pet-\(ambient.rawValue)-\(motion.name)-\(scheme.name)-\(typeSize.name)"
                        let model = SnapshotCatalogSupport.petModel(
                            state: ambient,
                            reduceMotion: motion.value
                        )
                        let hosted = SnapshotCatalogSupport.hostingView(
                            FloatingPetView(model: model, honorSystemReduceMotion: false),
                            colorScheme: scheme.value,
                            dynamicType: typeSize.value,
                            size: SnapshotCatalogSupport.petSize
                        )

                        assertSnapshot(
                            of: hosted,
                            as: .image,
                            named: name,
                            file: #filePath,
                            testName: "FloatingPet"
                        )
                    }
                }
            }
        }
    }
}
