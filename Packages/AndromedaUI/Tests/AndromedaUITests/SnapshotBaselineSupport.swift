import Foundation
import XCTest

/// Shared Gate 0 helper: snapshot suites stay in-tree, but do not fail CI until
/// baselines are recorded on macOS (verification follow-up).
enum AndromedaUISnapshotSupport {
    /// Skip when `__Snapshots__` next to the calling test file is missing/empty.
    /// Record mode (`SNAPSHOT_TESTING_RECORD=1`) always proceeds.
    static func requireBaselines(
        file: StaticString = #filePath
    ) throws {
        let envRecord = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "1"
        if envRecord {
            return
        }
        let dir = URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard !contents.isEmpty else {
            throw XCTSkip("AndromedaUI snapshot baselines not recorded yet — run once with isRecording on macOS")
        }
    }
}
