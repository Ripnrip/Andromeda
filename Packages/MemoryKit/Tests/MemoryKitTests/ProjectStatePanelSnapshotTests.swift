/**
 * 🧪 The ProjectStatePanelSnapshotTests - Light/Dark Footlight Proofs
 *
 * "Four frames freeze the client board under SnapshotTesting—
 * light, dark, empty stage, loading hush —
 * hosted via NSHostingController (macOS has no SwiftUI .image strategy)."
 *
 * - The Theatrical Snapshot Virtuoso of project.state
 */

import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import MemoryKit

@MainActor
final class ProjectStatePanelSnapshotTests: XCTestCase {

    private let canvas = CGSize(width: 360, height: 420)

    func testProjectStatePanelLight() {
        assertPanelSnapshot(
            named: "light",
            root: fixtureRoot(colorScheme: .light)
        )
    }

    func testProjectStatePanelDark() {
        assertPanelSnapshot(
            named: "dark",
            root: fixtureRoot(colorScheme: .dark)
        )
    }

    func testProjectStatePanelEmpty() {
        let model = ProjectStatePanelModel(projects: [], lastMessage: "Loaded 0 project(s)")
        assertPanelSnapshot(
            named: "empty",
            root: AnyView(
                ProjectStatePanel(model: model)
                    .preferredColorScheme(.light)
                    .padding()
                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                    .background(Color.white)
            )
        )
    }

    func testProjectStatePanelLoading() {
        let model = ProjectStatePanelModel(
            projects: [],
            lastMessage: "Refreshing…",
            isLoading: true
        )
        assertPanelSnapshot(
            named: "loading",
            root: AnyView(
                ProjectStatePanel(model: model)
                    .preferredColorScheme(.light)
                    .padding()
                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                    .background(Color.white)
            )
        )
    }

    // MARK: - Helpers

    private func fixtureRoot(colorScheme: ColorScheme) -> AnyView {
        AnyView(
            ProjectStatePanel(model: .snapshotFixture())
                .preferredColorScheme(colorScheme)
                .padding()
                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                .background(colorScheme == .dark ? Color.black : Color.white)
        )
    }

    /// 🎨 Snapshot via NSHostingController — SnapshotTesting SwiftUI `.image` is iOS/tvOS-only.
    private func assertPanelSnapshot(
        named name: String,
        root: AnyView,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let host = NSHostingController(rootView: root)
        host.view.frame = NSRect(origin: .zero, size: canvas)
        host.view.layoutSubtreeIfNeeded()

        // 🌙 Prefer SnapshotTestingConfiguration.Record when SNAPSHOT_TESTING_RECORD is set
        withSnapshotTesting(
            record: ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil ? .all : .missing
        ) {
            assertSnapshot(
                of: host,
                as: .image,
                named: name,
                file: file,
                testName: "ProjectStatePanel",
                line: line
            )
        }
    }
}
