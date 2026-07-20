/**
 * 🧪 MCPRegistrySnapshotTests - Pixel Catalog for the Sprawl Roster
 *
 * "Light, dark, empty, sprawl — we freeze the stage in glass
 * so future agents notice when the duplicate badge drifts off cue."
 *
 * - The Theatrical Snapshot Virtuoso of MemoryKit UI
 */

import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import MemoryKit

/// 📸 XCTest host required — SnapshotTesting's assertSnapshot speaks XCTFail.
final class MCPRegistrySnapshotTests: XCTestCase {

    @MainActor
    func testEmptyLight() {
        assertHostingSnapshot(model: makeEmptyModel(), named: "empty-light", scheme: .light)
    }

    @MainActor
    func testEmptyDark() {
        assertHostingSnapshot(model: makeEmptyModel(), named: "empty-dark", scheme: .dark)
    }

    @MainActor
    func testSprawlLight() {
        assertHostingSnapshot(model: makeSprawlModel(), named: "sprawl-light", scheme: .light)
    }

    @MainActor
    func testSprawlDark() {
        assertHostingSnapshot(model: makeSprawlModel(), named: "sprawl-dark", scheme: .dark)
    }

    // MARK: - Helpers

    @MainActor
    private func assertHostingSnapshot(
        model: MCPRegistryModel,
        named: String,
        scheme: ColorScheme,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = MCPRegistryView(model: model)
            .preferredColorScheme(scheme)
            .frame(width: 420, height: 520)
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 420, height: 520)
        assertSnapshot(
            of: hosting,
            as: .image,
            named: named,
            record: false,
            file: file,
            testName: testName,
            line: line
        )
    }

    @MainActor
    private func makeEmptyModel() -> MCPRegistryModel {
        let model = MCPRegistryModel()
        model.clear()
        return model
    }

    @MainActor
    private func makeSprawlModel() -> MCPRegistryModel {
        let snaps = (1...3).map { i in
            MCPProcessSnapshot(
                pid: 1000 + i,
                command: "npm exec @modelcontextprotocol/server-filesystem /Users/admin",
                memoryMB: 71
            )
        }
        var registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(processes: snaps),
            telemetry: RecordingMCPTelemetry()
        )
        let scan = registry.scan()
        let model = MCPRegistryModel()
        model.apply(scan: scan)
        return model
    }
}
