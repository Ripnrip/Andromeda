import Testing
import SnapshotTesting
import SwiftUI
import MemoryKit
@testable import AndromedaHUDCore

/// Pixel catalog for `HUDView` (light/dark × Dynamic Type × outcome states).
///
/// ## Reduce-motion note (macOS)
/// `EnvironmentValues.accessibilityReduceMotion` is **not** a `WritableKeyPath` on
/// macOS AppKit hosting — `.environment(\.accessibilityReduceMotion, true)` does not
/// compile. Do **not** inject reduce-motion in these snapshots. Runtime still honors
/// `@Environment(\.accessibilityReduceMotion)` from system Accessibility settings;
/// Dynamic Type + dark layouts cover the a11y matrix gap for CI.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter 'HUDViewSnapshotTests|HUDResultsViewSnapshotTests'`
@Suite("Andromeda HUD Snapshots")
@MainActor
struct HUDViewSnapshotTests {
    /// Matches the committed `Dark_RecentQueries` baseline (visible cap = 6).
    private static let recentQueriesFixture = [
        "project.state",
        "recall fleet observe",
        "q11", "q10", "q9", "q8", "q7", "q6",
    ]

    private var recordMode: SnapshotTestingConfiguration.Record {
        (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
    }

    init() {
        HUDModel.clearPersistedRecentQueries()
    }

    @Test("HUD Idle State Snapshots", arguments: [
        ("Light", true),
        ("Dark", false)
    ])
    func idleSnapshots(name: String, isLight: Bool) {
        withSnapshotTesting(record: recordMode) {
            let view = HUDView()
                .padding()
                .frame(width: 400, height: 100)
                .environment(\.colorScheme, isLight ? .light : .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)

            assertSnapshot(of: hostingView, as: .image, named: name)
        }
    }

    @Test("HUD Extra Large Dynamic Type Snapshot")
    func extraLargeDynamicTypeSnapshot() {
        withSnapshotTesting(record: recordMode) {
            let view = HUDView()
                .padding()
                .frame(width: 400, height: 150)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .accessibility3)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 150)

            assertSnapshot(of: hostingView, as: .image, named: "Dark_ExtraLargeDynamicType")
        }
    }

    @Test("HUD Collapsed State with Query Snapshots", arguments: [
        ("Light", true),
        ("Dark", false)
    ])
    func collapsedWithQuerySnapshots(name: String, isLight: Bool) {
        withSnapshotTesting(record: recordMode) {
            let view = HUDView(isExpanded: false, searchQuery: "test query")
                .padding()
                .frame(width: 400, height: 100)
                .environment(\.colorScheme, isLight ? .light : .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 100)

            assertSnapshot(of: hostingView, as: .image, named: "\(name)_Collapsed_Query")
        }
    }

    @Test("HUD Expanded State Snapshots", arguments: [
        ("Light", true),
        ("Dark", false)
    ])
    func expandedSnapshots(name: String, isLight: Bool) {
        withSnapshotTesting(record: recordMode) {
            let hits = [
                MemoryHit(narrative: "First memory from the hot store", source: .hotStore, score: 10.0),
                MemoryHit(narrative: "Second memory from the vault", project: "andromeda", source: .vault, score: 8.0)
            ]
            let model = HUDModel(
                projectSurface: InMemoryProjectStateStore(),
                memorySessionReady: true,
                recentQueries: []
            )
            model.lastOutcome = .recalled(hits: hits)

            let view = HUDView(isExpanded: true, searchQuery: "test query", model: model)
                .padding()
                .frame(width: 400, height: 320)
                .environment(\.colorScheme, isLight ? .light : .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 320)

            assertSnapshot(of: hostingView, as: .image, named: "\(name)_Expanded_Results")
        }
    }

    @Test("HUD Empty outcome · Dynamic Type + reduceMotion")
    func emptyOutcomeA11ySnapshot() {
        withSnapshotTesting(record: recordMode) {
            let model = HUDModel(
                projectSurface: InMemoryProjectStateStore(),
                memorySessionReady: true,
                recentQueries: []
            )
            model.lastOutcome = .empty(message: "No memories matched “xyz”")
            let view = HUDView(isExpanded: true, searchQuery: "xyz", model: model)
                .padding()
                .frame(width: 420, height: 220)
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, .accessibility3)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 220)

            // Skip `.environment(\.accessibilityReduceMotion, …)` — not WritableKeyPath on macOS.
            assertSnapshot(of: hostingView, as: .image, named: "Dark_Empty_A11y3")
        }
    }

    @Test("HUD Failed outcome · light")
    func failedOutcomeSnapshot() {
        withSnapshotTesting(record: recordMode) {
            let model = HUDModel(
                projectSurface: InMemoryProjectStateStore(),
                memorySessionReady: true,
                recentQueries: []
            )
            model.lastOutcome = .failed(message: "Memory store unavailable")
            let view = HUDView(isExpanded: true, searchQuery: "recall", model: model)
                .padding()
                .frame(width: 400, height: 200)
                .environment(\.colorScheme, .light)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)

            assertSnapshot(of: hostingView, as: .image, named: "Light_Failed")
        }
    }

    @Test("HUD Recent queries · dark")
    func recentQueriesSnapshot() {
        withSnapshotTesting(record: recordMode) {
            HUDModel.clearPersistedRecentQueries()
            let model = HUDModel(
                projectSurface: InMemoryProjectStateStore(),
                memorySessionReady: true,
                recentQueries: Self.recentQueriesFixture
            )
            let view = HUDView(isExpanded: true, searchQuery: "", model: model)
                .padding()
                .frame(width: 400, height: 260)
                .environment(\.colorScheme, .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 260)

            assertSnapshot(of: hostingView, as: .image, named: "Dark_RecentQueries")
            HUDModel.clearPersistedRecentQueries()
        }
    }
}
