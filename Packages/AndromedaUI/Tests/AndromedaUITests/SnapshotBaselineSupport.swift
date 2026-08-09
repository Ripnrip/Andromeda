import Foundation
import SnapshotTesting
import XCTest

/// Shared Gate 0 helper: snapshot suites stay in-tree, but do not fail CI until
/// baselines are recorded on macOS (verification follow-up).
enum AndromedaUISnapshotSupport {
    /// Record mode for Point-Free `withSnapshotTesting(record:)`.
    /// Override with `SNAPSHOT_TESTING_RECORD=1` (or `all` / `failed` / `never` / `missing`).
    static var recordMode: SnapshotTestingConfiguration.Record {
        if let raw = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty
        {
            switch raw {
            case "all", "true", "1", "yes":
                return .all
            case "failed":
                return .failed
            case "never", "false", "0", "no":
                return .never
            case "missing":
                return .missing
            default:
                break
            }
        }
        return .missing
    }

    /// Skip when `__Snapshots__` next to the calling test file is missing/empty.
    /// Record mode (`SNAPSHOT_TESTING_RECORD=1`) always proceeds.
    static func requireBaselines(
        file: StaticString = #filePath
    ) throws {
        // Equatable compare — `Record` is not a frozen switchable enum in SnapshotTesting 1.19.
        if recordMode == .all || recordMode == .failed {
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
            throw XCTSkip(
                "AndromedaUI snapshot baselines not recorded yet — run once with SNAPSHOT_TESTING_RECORD=1 on macOS"
            )
        }
    }
}
