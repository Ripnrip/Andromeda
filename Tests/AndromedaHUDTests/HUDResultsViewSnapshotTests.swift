import Testing
import SnapshotTesting
import SwiftUI
@testable import AndromedaHUDCore

/// Pixel catalog for `HUDResultsView`.
///
/// ## Reduce-motion note (macOS)
/// Do not inject `.environment(\.accessibilityReduceMotion, true)` — that key is not a
/// `WritableKeyPath` under AppKit `NSHostingView` on macOS. The `*.reduceMotion` snapshot
/// captures the dark visible layout; product code still branches on the Environment at runtime.
/// Prefer Home/MemoryKit-style `forceReduceMotion` injectables if pixel-forcing motion is needed.
@Suite("HUDResultsView Snapshots")
@MainActor
struct HUDResultsViewSnapshotTests {

    private var recordMode: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] != nil ? .all : .missing
    }

    private func makeSUT(isVisible: Bool) -> some View {
        VStack(spacing: 0) {
            HUDResultsView(isVisible: isVisible) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result Match 1").font(.headline)
                    Text("Result Match 2").font(.subheadline)
                    Text("Result Match 3").font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 300, height: 220)
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    @Test("HUDResultsView visible light/dark", arguments: [
        ("Light", true),
        ("Dark", false),
    ])
    func visibleSnapshots(name: String, isLight: Bool) {
        withSnapshotTesting(record: recordMode) {
            let view = makeSUT(isVisible: true)
                .environment(\.colorScheme, isLight ? .light : .dark)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 260)

            assertSnapshot(of: hosting, as: .image, named: "HUDResultsView.visible.\(name.lowercased())")
        }
    }

    @Test("HUDResultsView hidden")
    func hiddenSnapshot() {
        withSnapshotTesting(record: recordMode) {
            let view = makeSUT(isVisible: false)
                .environment(\.colorScheme, .light)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 220)

            assertSnapshot(of: hosting, as: .image, named: "HUDResultsView.hidden")
        }
    }

    @Test("HUDResultsView visible dark (reduce-motion honored at runtime via Environment)")
    func visibleReduceMotionSnapshot() {
        withSnapshotTesting(record: recordMode) {
            // Skip reduce-motion env injection (not WritableKeyPath on macOS); dark layout only.
            let view = makeSUT(isVisible: true)
                .environment(\.colorScheme, .dark)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 260)

            assertSnapshot(of: hosting, as: .image, named: "HUDResultsView.visible.dark.reduceMotion")
        }
    }

    @Test("HUDResultsView visible Dynamic Type accessibility3")
    func visibleDynamicTypeSnapshot() {
        withSnapshotTesting(record: recordMode) {
            let view = makeSUT(isVisible: true)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .accessibility3)

            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 300)

            assertSnapshot(of: hosting, as: .image, named: "HUDResultsView.visible.dark.a11y3")
        }
    }
}
