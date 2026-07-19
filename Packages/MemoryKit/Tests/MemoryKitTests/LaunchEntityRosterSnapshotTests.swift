/**
 * 🎭 LaunchEntityRosterSnapshotTests - The Visual Catalog Ritual
 *
 * "Twelve portraits of the LaunchEntity playbill — light and dark,
 * Dynamic Type XXL, reduce-motion stills — locked as SnapshotTesting
 * PNGs so the roster can never quietly shrink into a stub again."
 *
 * - The Theatrical Snapshot Virtuoso of Fleet Observability
 */

import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import MemoryKit

/// 📸 XCTest host for SnapshotTesting — Swift Testing can't drive assertSnapshot yet.
/// macOS path hosts SwiftUI in `NSHostingView` (SwiftUI `.image(layout:)` is iOS/tvOS-only).
@MainActor
final class LaunchEntityRosterSnapshotTests: XCTestCase {

    private let canvasSize = CGSize(width: 460, height: 520)

    func testRosterLoadingLight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_loading_light",
            state: .loading,
            colorScheme: .light
        )
    }

    func testRosterLoadingDark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_loading_dark",
            state: .loading,
            colorScheme: .dark
        )
    }

    func testRosterEmptyLight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_empty_light",
            state: .empty,
            colorScheme: .light
        )
    }

    func testRosterEmptyDark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_empty_dark",
            state: .empty,
            colorScheme: .dark
        )
    }

    func testRosterHubFullLight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_hubFull_light",
            state: .hubFull,
            colorScheme: .light
        )
    }

    func testRosterHubFullDark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_hubFull_dark",
            state: .hubFull,
            colorScheme: .dark
        )
    }

    func testRosterSatelliteNALight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_satelliteNA_light",
            state: .satelliteNA,
            colorScheme: .light
        )
    }

    func testRosterSatelliteNADark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_satelliteNA_dark",
            state: .satelliteNA,
            colorScheme: .dark
        )
    }

    func testRosterHubFullDynamicTypeXXXLLight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_hubFull_dynamicTypeXXXL_light",
            state: .hubFull,
            colorScheme: .light,
            dynamicTypeSize: .accessibility3
        )
    }

    func testRosterHubFullDynamicTypeXXXLDark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_hubFull_dynamicTypeXXXL_dark",
            state: .hubFull,
            colorScheme: .dark,
            dynamicTypeSize: .accessibility3
        )
    }

    func testRosterHubFullReduceMotionLight() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_hubFull_reduceMotion_light",
            state: .hubFull,
            colorScheme: .light,
            reduceMotion: true
        )
    }

    func testRosterLoadingReduceMotionDark() {
        assertRosterSnapshot(
            named: "LaunchEntityRoster_loading_reduceMotion_dark",
            state: .loading,
            colorScheme: .dark,
            reduceMotion: true
        )
    }

    // MARK: - Helpers

    /// 🎨 Assert a named PNG under `__Snapshots__/LaunchEntityRosterSnapshotTests/`.
    private func assertRosterSnapshot(
        named name: String,
        state: LaunchEntityRosterState,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize? = nil,
        reduceMotion: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let model = LaunchEntityRosterFixtures.model(state, reduceMotion: reduceMotion)
        var root = AnyView(
            LaunchEntityRosterView(model: model, honorSystemReduceMotion: false)
                .preferredColorScheme(colorScheme)
                .frame(width: canvasSize.width, height: canvasSize.height)
        )
        if let dynamicTypeSize {
            root = AnyView(root.environment(\.dynamicTypeSize, dynamicTypeSize))
        }

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: canvasSize)

        // 🌙 Record when SNAPSHOT_TESTING_RECORD is set; otherwise compare against catalog.
        let recordMode: SnapshotTestingConfiguration.Record =
            (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing

        assertSnapshot(
            of: hosting,
            as: .image(size: canvasSize),
            named: name,
            record: recordMode,
            file: file,
            testName: "LaunchEntityRoster",
            line: line
        )
    }
}
