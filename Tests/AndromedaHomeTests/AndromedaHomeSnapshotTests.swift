/**
 * 🧪 AndromedaHome Snapshot Rituals — pixel catalog for product chrome (HAB-74)
 *
 * "Twelve stills of the Andromeda window: healthy / recalled / degraded /
 * syncing × light/dark, plus Dynamic Type and reduce-motion. memory.* stays
 * the default path; tracker brands never appear."
 *
 * - The Theatrical Snapshot Virtuoso
 */

import AndromedaHomeCore
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
final class AndromedaHomeSnapshotTests: XCTestCase {

    /// 🖼️ Taller canvas — deepened memory.* console (verb chips + guidance).
    private let canvasSize = CGSize(width: 780, height: 720)

    override func invokeTest() {
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil ? .all : .missing
        withSnapshotTesting(record: recordMode) {
            super.invokeTest()
        }
    }

    func testHomeHealthyLight() {
        assertHome(named: "AndromedaHome_healthy_light", model: AndromedaHomeFixtures.healthyHome(), scheme: .light)
    }

    func testHomeHealthyDark() {
        assertHome(named: "AndromedaHome_healthy_dark", model: AndromedaHomeFixtures.healthyHome(), scheme: .dark)
    }

    func testHomeRecalledLight() {
        assertHome(named: "AndromedaHome_recalled_light", model: AndromedaHomeFixtures.recalledHome(), scheme: .light)
    }

    func testHomeRecalledDark() {
        assertHome(named: "AndromedaHome_recalled_dark", model: AndromedaHomeFixtures.recalledHome(), scheme: .dark)
    }

    func testHomeDegradedLight() {
        assertHome(named: "AndromedaHome_degraded_light", model: AndromedaHomeFixtures.degradedHome(), scheme: .light)
    }

    func testHomeDegradedDark() {
        assertHome(named: "AndromedaHome_degraded_dark", model: AndromedaHomeFixtures.degradedHome(), scheme: .dark)
    }

    func testHomeSyncingLight() {
        assertHome(named: "AndromedaHome_syncing_light", model: AndromedaHomeFixtures.syncingHome(), scheme: .light)
    }

    func testHomeSyncingDark() {
        assertHome(named: "AndromedaHome_syncing_dark", model: AndromedaHomeFixtures.syncingHome(), scheme: .dark)
    }

    func testHomeHealthyDynamicTypeA2Light() {
        assertHome(
            named: "AndromedaHome_healthy_a2_light",
            model: AndromedaHomeFixtures.healthyHome(),
            scheme: .light,
            dynamicTypeSize: .accessibility2
        )
    }

    func testHomeRecalledDynamicTypeA2Dark() {
        assertHome(
            named: "AndromedaHome_recalled_a2_dark",
            model: AndromedaHomeFixtures.recalledHome(),
            scheme: .dark,
            dynamicTypeSize: .accessibility2
        )
    }

    func testHomeSyncingReduceMotionLight() {
        assertHome(
            named: "AndromedaHome_syncing_reduceMotion_light",
            model: AndromedaHomeFixtures.syncingHome(),
            scheme: .light,
            reduceMotion: true
        )
    }

    func testHomeDegradedReduceMotionDark() {
        assertHome(
            named: "AndromedaHome_degraded_reduceMotion_dark",
            model: AndromedaHomeFixtures.degradedHome(),
            scheme: .dark,
            reduceMotion: true
        )
    }

    // MARK: - Helpers

    private func assertHome(
        named name: String,
        model: AndromedaHomeModel,
        scheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize? = nil,
        reduceMotion: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // 🕰️ Keep footer clock frozen for pixel stability.
        model.lastRefresh = Date(timeIntervalSince1970: 1_752_700_000)

        var root = AnyView(
            AndromedaHomeView(model: model, forceReduceMotion: reduceMotion)
                .preferredColorScheme(scheme)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(scheme == .dark ? Color.black : Color.white)
        )
        if let dynamicTypeSize {
            root = AnyView(root.environment(\.dynamicTypeSize, dynamicTypeSize))
        }

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: canvasSize)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: hosting,
            as: .image(size: canvasSize),
            named: name,
            file: file,
            testName: "AndromedaHome",
            line: line
        )
    }
}
