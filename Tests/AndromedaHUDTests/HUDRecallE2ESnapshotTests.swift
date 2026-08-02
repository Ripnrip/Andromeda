import Testing
import SnapshotTesting
import SwiftUI
import MemoryKit
@testable import AndromedaHUDCore

/// 🌐 End-to-end HUD snapshots that drive the **real** submit pipeline.
///
/// Unlike `HUDViewSnapshotTests` (which injects `model.lastOutcome` directly),
/// these tests exercise the whole functional path against a hermetic backend:
///
///   `submitQuery` → `HUDCommand.parse` → `executeCommand` → real `CaptureService`
///   / `RetrievalService` (in-memory SwiftData store, **no** on-disk boot, **no**
///   live vault ripgrep) → `applyOutcome` → `HUDView` render → pixel snapshot.
///
/// Determinism: the store is `SwiftDataContainer.createInMemory()`, the vault
/// fallback is disabled (`vaultURL: nil`), and recalled rows render only
/// `narrative` / source / project (no dates, scores, or ids). Same input →
/// same pixels on every host.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter HUDRecallE2ESnapshotTests`
@Suite("Andromeda HUD E2E Snapshots")
@MainActor
struct HUDRecallE2ESnapshotTests {

    private var recordMode: SnapshotTestingConfiguration.Record {
        (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
    }

    /// Build a HUDModel wired to a hermetic in-memory MemoryKit session.
    private func makeModelWithInMemorySession() throws -> HUDModel {
        let container = try SwiftDataContainer.createInMemory()
        let capture = CaptureService(container: container)
        let retrieval = RetrievalService(
            container: container,
            vaultURL: nil,
            processRunner: LocalProcessRunner(),
            ripgrepExecutable: "/opt/homebrew/bin/rg"
        )
        let model = HUDModel(
            projectSurface: InMemoryProjectStateStore(),
            recentQueries: []
        )
        model.injectSessionForTesting(retrieval: retrieval, capture: capture)
        return model
    }

    @Test("E2E · store then recall renders the hit")
    func recallRoundTripRendersHit() async throws {
        let model = try makeModelWithInMemorySession()

        // Drive the real store capability through the submit pipeline.
        await model.submitQuery("store Andromeda HUD ships the floating memory bar", recordRecent: false)
        guard case .stored = model.lastOutcome else {
            Issue.record("Expected .stored, got \(String(describing: model.lastOutcome))")
            return
        }

        // Drive the real recall capability — hot-store search finds the just-stored neuron.
        await model.submitQuery("recall andromeda", recordRecent: false)
        guard case .recalled(let hits) = model.lastOutcome else {
            Issue.record("Expected .recalled, got \(String(describing: model.lastOutcome))")
            return
        }
        #expect(hits.count == 1)
        #expect(hits.first?.narrative.contains("floating memory bar") == true)
        #expect(hits.first?.source == .hotStore)

        withSnapshotTesting(record: recordMode) {
            let view = HUDView(isExpanded: true, searchQuery: "recall andromeda", model: model)
                .padding()
                .frame(width: 400, height: 240)
                .environment(\.colorScheme, .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 240)
            assertSnapshot(of: hostingView, as: .image, named: "Dark_E2E_Recalled")
        }
    }

    @Test("E2E · recall with no match renders empty")
    func recallNoMatchRendersEmpty() async throws {
        let model = try makeModelWithInMemorySession()

        await model.submitQuery("store Andromeda HUD ships the floating memory bar", recordRecent: false)
        guard case .stored = model.lastOutcome else {
            Issue.record("Expected .stored, got \(String(describing: model.lastOutcome))")
            return
        }

        await model.submitQuery("recall nonexistent-needle-zzz", recordRecent: false)
        guard case .empty(let message) = model.lastOutcome else {
            Issue.record("Expected .empty, got \(String(describing: model.lastOutcome))")
            return
        }
        #expect(message.contains("No memories matched"))

        withSnapshotTesting(record: recordMode) {
            let view = HUDView(isExpanded: true, searchQuery: "recall nonexistent-needle-zzz", model: model)
                .padding()
                .frame(width: 400, height: 200)
                .environment(\.colorScheme, .dark)

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            assertSnapshot(of: hostingView, as: .image, named: "Dark_E2E_Empty")
        }
    }

    @Test("E2E · journal lands with session tags and is recallable")
    func journalRoundTrip() async throws {
        let model = try makeModelWithInMemorySession()

        await model.submitQuery("journal", recordRecent: false)
        guard case .journaled = model.lastOutcome else {
            Issue.record("Expected .journaled, got \(String(describing: model.lastOutcome))")
            return
        }

        await model.submitQuery("recall memory.journal", recordRecent: false)
        guard case .recalled(let hits) = model.lastOutcome else {
            Issue.record("Expected .recalled, got \(String(describing: model.lastOutcome))")
            return
        }
        #expect(hits.count == 1)
        #expect(hits.first?.narrative.contains("Journal entry") == true)
        #expect(hits.first?.tags.contains("journal") == true)
        #expect(hits.first?.tags.contains("session-dump") == false)
    }

    @Test("E2E · session dump retains its capability identity")
    func sessionDumpRoundTrip() async throws {
        let model = try makeModelWithInMemorySession()

        await model.submitQuery("memory.session_dump", recordRecent: false)
        guard case .journaled = model.lastOutcome else {
            Issue.record("Expected .journaled, got \(String(describing: model.lastOutcome))")
            return
        }

        await model.submitQuery("recall memory.session_dump", recordRecent: false)
        guard case .recalled(let hits) = model.lastOutcome else {
            Issue.record("Expected .recalled, got \(String(describing: model.lastOutcome))")
            return
        }
        #expect(hits.count == 1)
        #expect(hits.first?.narrative.contains("Session dump") == true)
        #expect(hits.first?.tags.contains("journal") == true)
        #expect(hits.first?.tags.contains("session-dump") == true)
    }

    @Test("E2E · visibility policy forces cloak writes internal")
    func cloakWriteIsInternal() async throws {
        let model = try makeModelWithInMemorySession()

        await model.submitQuery("store [cloak] private curtain note", recordRecent: false)
        guard case .stored = model.lastOutcome else {
            Issue.record("Expected .stored, got \(String(describing: model.lastOutcome))")
            return
        }

        await model.submitQuery("recall private curtain note", recordRecent: false)
        guard case .recalled(let hits) = model.lastOutcome else {
            Issue.record("Expected .recalled, got \(String(describing: model.lastOutcome))")
            return
        }
        #expect(hits.first?.visibility == VisibilityClass.internal.rawValue)
    }
}
