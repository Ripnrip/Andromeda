#if canImport(AppKit)
import AppKit
import SwiftUI
@preconcurrency import SnapshotTesting
import XCTest
@testable import AndromedaHUD

/**
 Point-Free SnapshotTesting catalog for the modern HUD (BIN-58).

 Hosted via `NSHostingView` because SnapshotTesting's SwiftUI `.image(layout:)`
 strategy is iOS/tvOS-only. Golden PNGs live under `__Snapshots__/`.
 */
@MainActor
final class AndromedaHUDSnapshotTests: XCTestCase {
    private static let collapsedSize = CGSize(width: 360, height: 100)
    private static let expandedSize = CGSize(width: 460, height: 320)

    override func invokeTest() {
        withSnapshotTesting(record: Self.recordMode) {
            super.invokeTest()
        }
    }

    func testCollapsedHealthyLight() {
        assertHUD(
            model: .snapshotCollapsedHealthy(),
            name: "HUD.collapsed.healthy.light",
            scheme: .light,
            size: Self.collapsedSize
        )
    }

    func testCollapsedHealthyDark() {
        assertHUD(
            model: .snapshotCollapsedHealthy(),
            name: "HUD.collapsed.healthy.dark",
            scheme: .dark,
            size: Self.collapsedSize
        )
    }

    func testExpandedWorkingDark() {
        assertHUD(
            model: .snapshotExpandedWorking(),
            name: "HUD.expanded.working.dark",
            scheme: .dark,
            size: Self.expandedSize
        )
    }

    func testExpandedWorkingLight() {
        assertHUD(
            model: .snapshotExpandedWorking(),
            name: "HUD.expanded.working.light",
            scheme: .light,
            size: Self.expandedSize
        )
    }

    func testCollapsedDegradedDark() {
        assertHUD(
            model: .snapshotDegraded(),
            name: "HUD.collapsed.degraded.dark",
            scheme: .dark,
            size: Self.collapsedSize
        )
    }

    func testExpandedA11y2Dark() {
        assertHUD(
            model: .snapshotExpandedWorking(),
            name: "HUD.expanded.working.dark.a11y2",
            scheme: .dark,
            size: Self.expandedSize,
            dynamicType: .accessibility2
        )
    }

    // MARK: - Helpers

    private static var recordMode: SnapshotTestingConfiguration.Record {
        if let raw = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            switch raw {
            case "all", "true", "1", "yes": return .all
            case "failed": return .failed
            case "never", "false", "0", "no": return .never
            case "missing": return .missing
            default: break
            }
        }
        return .missing
    }

    private func assertHUD(
        model: AndromedaHUDModel,
        name: String,
        scheme: ColorScheme,
        size: CGSize,
        dynamicType: DynamicTypeSize = .medium,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = AndromedaHUDView(model: model, honorSystemReduceMotion: false)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, dynamicType)
            .transaction { $0.animation = nil }
            .padding(12)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(scheme == .dark ? Color.black : Color.white)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: hosting,
            as: .image(size: size),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}

@MainActor
private extension AndromedaHUDModel {
    static func snapshotCollapsedHealthy() -> AndromedaHUDModel {
        AndromedaHUDModel(
            expansion: .collapsed,
            snapMode: .menuBar,
            health: .healthy,
            reduceMotion: true
        )
    }

    static func snapshotExpandedWorking() -> AndromedaHUDModel {
        let model = AndromedaHUDModel(
            expansion: .expanded,
            snapMode: .floating,
            health: .working,
            healthDetail: "sync",
            query: "recall launch entities",
            reduceMotion: true
        )
        model.lastMessage = "memory.recall · launch entities"
        return model
    }

    static func snapshotDegraded() -> AndromedaHUDModel {
        AndromedaHUDModel(
            expansion: .collapsed,
            snapMode: .floating,
            health: .degraded,
            healthDetail: "cache",
            reduceMotion: true
        )
    }
}
#else
import Testing

/// Snapshot catalog requires AppKit hosting — documented skip on Linux CI.
@Suite("AndromedaHUD snapshots")
struct AndromedaHUDSnapshotTests {
    @Test("Snapshots require macOS AppKit hosting")
    func testSnapshotsRequireAppKit() {
        // Intentionally empty on Linux: goldens are recorded on macOS.
        // See docs/ANDROMEDA-HUD.md for SNAPSHOT_TESTING_RECORD instructions.
    }
}
#endif
