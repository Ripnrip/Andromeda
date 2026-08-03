import Testing
import SnapshotTesting
import SwiftUI
import MemoryKit
@testable import AndromedaHUDCore

/// Pixel catalog for HUD sub-components — each tested in isolation across all states.
///
/// Covers: HUDMemoryHitRow, HUDProjectResultsView, HUDStatusRow,
/// HUDFleetPulseChip, HUDRecentQueriesView, DragHandleView
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter HUDComponentsSnapshotTests`
@Suite("HUD Component Snapshots")
@MainActor
struct HUDComponentsSnapshotTests {

    private var recordMode: SnapshotTestingConfiguration.Record {
        (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
    }

    private func snapshot<V: View>(
        _ view: V,
        size: NSSize = NSSize(width: 380, height: 80),
        scheme: ColorScheme = .dark,
        named: String,
        dynamicTypeSize: DynamicTypeSize? = nil
    ) {
        withSnapshotTesting(record: recordMode) {
            var root = AnyView(
                view
                    .environment(\.colorScheme, scheme)
                    .padding()
                    .background(scheme == .dark ? Color.black : Color.white)
            )
            if let dynamicTypeSize {
                root = AnyView(root.environment(\.dynamicTypeSize, dynamicTypeSize))
            }

            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.wantsLayer = true
            hosting.layoutSubtreeIfNeeded()

            assertSnapshot(of: hosting, as: .image, named: named)
        }
    }

    // MARK: - HUDMemoryHitRow

    @Test("HUDMemoryHitRow · selected vs unselected · dark", arguments: [
        ("Selected", true),
        ("Unselected", false),
    ])
    func memoryHitRowStates(name: String, isSelected: Bool) {
        let hit = MemoryHit(
            narrative: "Studio hosts the hive mind; Book recalls as a satellite.",
            project: "andromeda",
            source: .vault,
            score: 8.0
        )
        snapshot(
            HUDMemoryHitRow(hit: hit, isSelected: isSelected, onActivate: {}),
            named: "MemoryHitRow_\(name)_Dark"
        )
    }

    @Test("HUDMemoryHitRow · hot store · light")
    func memoryHitRowHotStore() {
        let hit = MemoryHit(
            narrative: "Quick recall from the hot store — ephemeral capture.",
            source: .hotStore,
            score: 12.0
        )
        snapshot(
            HUDMemoryHitRow(hit: hit, isSelected: false, onActivate: {}),
            scheme: .light,
            named: "MemoryHitRow_HotStore_Light"
        )
    }

    @Test("HUDMemoryHitRow · a11y3 · dark")
    func memoryHitRowA11y() {
        let hit = MemoryHit(
            narrative: "Long narrative that wraps with Dynamic Type enabled.",
            project: "multibrain",
            source: .vault,
            score: 6.0
        )
        snapshot(
            HUDMemoryHitRow(hit: hit, isSelected: true, onActivate: {}),
            size: NSSize(width: 380, height: 120),
            named: "MemoryHitRow_A11y3_Dark",
            dynamicTypeSize: .accessibility3
        )
    }

    // MARK: - HUDFleetPulseChip

    @Test("HUDFleetPulseChip · all statuses", arguments: [
        ("Green", HUDFleetPulse(status: .green, attentionCount: 0, detail: "All systems nominal")),
        ("Yellow", HUDFleetPulse(status: .yellow, attentionCount: 3, detail: "3 services need attention")),
        ("Red", HUDFleetPulse(status: .red, attentionCount: 1, detail: "Critical: Qdrant unreachable")),
        ("Unknown", HUDFleetPulse(status: .unknown, attentionCount: 0, detail: "fleet idle")),
    ])
    func fleetPulseChipStates(name: String, pulse: HUDFleetPulse) {
        snapshot(
            HUDFleetPulseChip(pulse: pulse),
            size: NSSize(width: 60, height: 40),
            named: "FleetPulse_\(name)_Dark"
        )
    }

    // MARK: - HUDStatusRow

    @Test("HUDStatusRow · syncing · dark")
    func statusRowSyncing() {
        snapshot(
            HUDStatusRow(
                systemImage: nil,
                showsProgress: true,
                title: "Working…",
                accessibilityLabel: "Working on your query"
            ),
            named: "StatusRow_Syncing_Dark"
        )
    }

    @Test("HUDStatusRow · empty · light")
    func statusRowEmpty() {
        snapshot(
            HUDStatusRow(
                systemImage: "magnifyingglass",
                showsProgress: false,
                title: "No memories matched",
                accessibilityLabel: "No memories matched",
                emphasis: .secondary
            ),
            scheme: .light,
            named: "StatusRow_Empty_Light"
        )
    }

    @Test("HUDStatusRow · failed · dark")
    func statusRowFailed() {
        snapshot(
            HUDStatusRow(
                systemImage: "exclamationmark.triangle.fill",
                showsProgress: false,
                title: "Memory store unavailable",
                accessibilityLabel: "Error: Memory store unavailable",
                emphasis: .warning
            ),
            named: "StatusRow_Failed_Dark"
        )
    }

    @Test("HUDStatusRow · stored (tinted) · dark")
    func statusRowStored() {
        snapshot(
            HUDStatusRow(
                systemImage: "tray.and.arrow.down.fill",
                showsProgress: false,
                title: "Stored memory (id: A1B2C3D4)",
                accessibilityLabel: "Stored memory, ID: A1B2C3D4",
                tinted: true
            ),
            named: "StatusRow_Stored_Dark"
        )
    }

    // MARK: - HUDRecentQueriesView

    @Test("HUDRecentQueriesView · dark")
    func recentQueriesView() {
        let queries = ["project.state", "recall fleet observe", "store hello", "infer.write note"]
        snapshot(
            HUDRecentQueriesView(queries: queries, selectedIndex: 1, onSelect: { _ in }),
            size: NSSize(width: 380, height: 200),
            named: "RecentQueries_Dark"
        )
    }

    @Test("HUDRecentQueriesView · light")
    func recentQueriesViewLight() {
        let queries = ["recall", "store", "journal"]
        snapshot(
            HUDRecentQueriesView(queries: queries, selectedIndex: 0, onSelect: { _ in }),
            size: NSSize(width: 380, height: 160),
            scheme: .light,
            named: "RecentQueries_Light"
        )
    }

    // MARK: - DragHandleView

    @Test("DragHandleView · dark")
    func dragHandleDark() {
        snapshot(
            DragHandleView(),
            size: NSSize(width: 50, height: 40),
            named: "DragHandle_Dark"
        )
    }

    // MARK: - HUDOutcomeView · all states

    @Test("HUDOutcomeView · syncing · dark")
    func outcomeViewSyncing() {
        snapshot(
            HUDOutcomeView(outcome: .syncing, isLiveSearching: true),
            size: NSSize(width: 380, height: 60),
            named: "Outcome_Syncing_Dark"
        )
    }

    @Test("HUDOutcomeView · empty · light")
    func outcomeViewEmpty() {
        snapshot(
            HUDOutcomeView(outcome: .empty(message: "No memories matched")),
            size: NSSize(width: 380, height: 60),
            scheme: .light,
            named: "Outcome_Empty_Light"
        )
    }

    @Test("HUDOutcomeView · failed · dark")
    func outcomeViewFailed() {
        snapshot(
            HUDOutcomeView(outcome: .failed(message: "Memory store unavailable")),
            size: NSSize(width: 380, height: 60),
            named: "Outcome_Failed_Dark"
        )
    }

    @Test("HUDOutcomeView · stored · dark")
    func outcomeViewStored() {
        snapshot(
            HUDOutcomeView(outcome: .stored(idSummary: "A1B2C3D4")),
            size: NSSize(width: 380, height: 60),
            named: "Outcome_Stored_Dark"
        )
    }

    // MARK: - HUDProjectResultsView

    @Test("HUDProjectResultsView · dark")
    func projectResultsDark() {
        let states = [
            ProjectState(
                id: "andromeda",
                title: "Andromeda",
                status: .active,
                items: [
                    ProjectStateItem(id: "i1", title: "Wire HUD results panel", status: .active),
                    ProjectStateItem(id: "i2", title: "Ship snapshots", status: .backlog),
                    ProjectStateItem(id: "i3", title: "Blocked: CI Qdrant", status: .blocked),
                ]
            ),
            ProjectState(
                id: "multibrain",
                title: "Multibrain",
                status: .active,
                items: [
                    ProjectStateItem(id: "i4", title: "Nightly consolidate", status: .done),
                ]
            ),
        ]
        snapshot(
            HUDProjectResultsView(projects: states, selectedIndex: 0, onActivateItem: nil),
            size: NSSize(width: 380, height: 280),
            named: "ProjectResults_Dark"
        )
    }
}
