import AndromedaHomeCore
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Pixel catalog for `MemoryConsoleView` — each outcome state independently.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter MemoryConsoleSnapshotTests`
@MainActor
final class MemoryConsoleSnapshotTests: XCTestCase {

    private let canvasSize = CGSize(width: 460, height: 400)

    override func invokeTest() {
        let recordMode: SnapshotTestingConfiguration.Record =
            (ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"].map { !$0.isEmpty } ?? false) ? .all : .missing
        withSnapshotTesting(record: recordMode) {
            super.invokeTest()
        }
    }

    func testIdleDark() {
        assertConsole(named: "idle_dark", outcome: .idle, query: "", scheme: .dark)
    }

    func testRecallReadyLight() {
        assertConsole(named: "recallReady_light", outcome: .idle, query: "recall ", scheme: .light)
    }

    func testStoreTypedDark() {
        assertConsole(named: "storeTyped_dark", outcome: .idle, query: "store hello hive", scheme: .dark)
    }

    func testSyncingDark() {
        assertConsole(named: "syncing_dark", outcome: .syncing, query: "store hello", scheme: .dark)
    }

    func testSyncingReduceMotionLight() {
        assertConsole(named: "syncing_reduceMotion_light", outcome: .syncing, query: "store hello", scheme: .light, reduceMotion: true)
    }

    func testRecalledDark() {
        let session = makeSession()
        session.lastOutcome = .recalled(
            hits: [
                AndromedaMemoryHit(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    title: "Studio hosts the hive mind; Book recalls as a satellite.",
                    subtitle: "multibrain · ~/Developer/SecondBrain",
                    sourceLabel: "vault",
                    visibility: "private"
                ),
                AndromedaMemoryHit(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    title: "Hot store ephemeral capture.",
                    subtitle: "",
                    sourceLabel: "hot",
                    visibility: nil
                ),
            ],
            degraded: false,
            note: nil
        )
        assertConsole(named: "recalled_dark", session: session, query: "recall andromeda", scheme: .dark)
    }

    func testStoredLight() {
        assertConsole(named: "stored_light", outcome: .stored(idSummary: "A1B2C3D4"), query: "store hello hive", scheme: .light)
    }

    func testFailedDark() {
        assertConsole(named: "failed_dark", outcome: .failed(message: "Memory store unavailable"), query: "recall", scheme: .dark)
    }

    func testEmptyLight() {
        assertConsole(named: "empty_light", outcome: .empty(message: "No memories matched"), query: "recall xyz", scheme: .light)
    }

    // MARK: - Helpers

    private func assertConsole(
        named name: String,
        outcome: AndromedaMemoryOutcome? = nil,
        session: AndromedaMemorySession? = nil,
        query: String,
        scheme: ColorScheme,
        reduceMotion: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ses = session ?? makeSession()
        if let outcome {
            ses.lastOutcome = outcome
        }

        var queryBinding = query

        let view = MemoryConsoleView(
            session: ses,
            query: SwiftUI.Binding(get: { queryBinding }, set: { queryBinding = $0 }),
            onSubmit: {},
            forceReduceMotion: reduceMotion
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .preferredColorScheme(scheme)
        .background(scheme == .dark ? Color.black : Color.white)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: canvasSize)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: hosting,
            as: .image(size: canvasSize),
            named: name,
            file: file,
            testName: "MemoryConsole",
            line: line
        )
    }

    private func makeSession() -> AndromedaMemorySession {
        AndromedaMemorySession()
    }
}
