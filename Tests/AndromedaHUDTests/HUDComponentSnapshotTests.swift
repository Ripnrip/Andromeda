import AppKit
import MemoryKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import AndromedaHUDCore

/// Point-Free pixel catalog for the HUD's reusable components and every `HUDOutcome` state.
///
/// Record deliberately on macOS with
/// `SNAPSHOT_TESTING_RECORD=1 swift test --filter HUDComponentSnapshotTests`; AppKit font and
/// material rendering make screenshots recorded on another platform misleading little space
/// impostors. 🚀
@Suite("Andromeda HUD Component Snapshots")
@MainActor
struct HUDComponentSnapshotTests {
    /// A stable, human-readable case used to name each image in the outcome matrix.
    struct OutcomeFixture: Sendable {
        let name: String
        let outcome: HUDOutcome
    }

    /// Enumerates every visual branch of `HUDOutcomeView`, including all four success rows.
    static let outcomeFixtures: [OutcomeFixture] = [
        .init(name: "idle", outcome: .idle),
        .init(name: "syncing", outcome: .syncing),
        .init(
            name: "recalled",
            outcome: .recalled(hits: [
                MemoryHit(narrative: "Hot-store result", source: .hotStore, score: 10),
                MemoryHit(narrative: "Selected vault result", project: "andromeda", source: .vault, score: 8),
            ])
        ),
        .init(name: "stored", outcome: .stored(idSummary: "A1B2C3D4")),
        .init(name: "journaled", outcome: .journaled(idSummary: "E5F6A7B8")),
        .init(
            name: "projects",
            outcome: .projects(states: [
                ProjectState(
                    id: "andromeda",
                    title: "Andromeda",
                    status: .active,
                    items: [
                        ProjectStateItem(id: "active", title: "Record component catalog", status: .active),
                        ProjectStateItem(id: "blocked", title: "Await macOS pixels", status: .blocked),
                        ProjectStateItem(id: "backlog", title: "Review visual diff", status: .backlog),
                    ]
                ),
            ])
        ),
        .init(name: "created", outcome: .created(title: "Catalog every component state")),
        .init(name: "updated", outcome: .updated(title: "Catalog every component state")),
        .init(name: "empty", outcome: .empty(message: "No memories matched “quasar”")),
        .init(name: "failed", outcome: .failed(message: "Memory store unavailable")),
    ]

    /// Uses the repository-wide opt-in recording convention so normal tests compare pixels.
    private var recordMode: SnapshotTestingConfiguration.Record {
        (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
    }

    /// Captures every outcome branch in light and dark appearances at a fixed component canvas.
    @Test("HUDOutcomeView all states", arguments: outcomeFixtures, [("light", true), ("dark", false)])
    func outcomeSnapshots(fixture: OutcomeFixture, appearance: (String, Bool)) {
        withSnapshotTesting(record: recordMode) {
            let scheme: ColorScheme = appearance.1 ? .light : .dark
            let view = HUDResultsView(isVisible: fixture.outcome.showsResultsPanel) {
                HUDOutcomeView(outcome: fixture.outcome, selectedIndex: 1)
            }
            .frame(width: 378)
            .padding(16)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)

            let size = CGSize(width: 410, height: fixture.name == "projects" ? 300 : 220)
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()

            assertSnapshot(
                of: hosting,
                as: .image(size: size),
                named: "outcome.\(fixture.name).\(appearance.0)"
            )
        }
    }

    /// Captures green, yellow, red, and unknown fleet indicators as one reviewable strip.
    @Test("HUDFleetPulseChip all states")
    func fleetPulseSnapshots() {
        withSnapshotTesting(record: recordMode) {
            let view = HStack(spacing: 24) {
                HUDFleetPulseChip(pulse: .init(status: .green, detail: "Healthy"))
                HUDFleetPulseChip(pulse: .init(status: .yellow, attentionCount: 1, detail: "Attention"))
                HUDFleetPulseChip(pulse: .init(status: .red, attentionCount: 2, detail: "Degraded"))
                HUDFleetPulseChip(pulse: .init(status: .unknown, detail: "Unknown"))
            }
            .padding(20)
            .background(Color.black)
            .environment(\.colorScheme, .dark)

            let size = CGSize(width: 180, height: 56)
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()

            assertSnapshot(of: hosting, as: .image(size: size), named: "fleet-pulse.all-states")
        }
    }
}
