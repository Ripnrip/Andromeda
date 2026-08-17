/**
 * 🎭 The LiveLaunchctlObserver - Honest launchctl Peek
 *
 * "No more Null theater. We ask launchctl list for PID and LastExitStatus —
 * observe only, never kickstart, bootstrap, or bootout."
 *
 * - The Cosmic Process Orchestrator of Andromeda Observe
 */

import Foundation

// MARK: - Process runner (injectable)

/// 🌟 Runs `launchctl list <label>` and returns stdout on success (exit 0).
public protocol LaunchctlListRunning: Sendable {
    /// 📜 stdout when the label is loaded; nil when unloaded / error.
    func listOutput(label: String) -> String?
}

/// 🧪 Fixture runner — maps labels to canned NeXTSTEP stdout (or nil).
public struct MockLaunchctlListRunner: LaunchctlListRunning {
    private let outputs: [String: String?]

    public init(outputs: [String: String?] = [:]) {
        self.outputs = outputs
    }

    public func listOutput(label: String) -> String? {
        outputs[label] ?? nil
    }
}

/// 🛰️ Real `/bin/launchctl list <label>` — read-only.
public struct ProcessLaunchctlListRunner: LaunchctlListRunning {
    private let launchctlPath: String

    public init(launchctlPath: String = "/bin/launchctl") {
        self.launchctlPath = launchctlPath
    }

    public func listOutput(label: String) -> String? {
        // Exhibit 3: drain concurrently — wait-then-read deadlocks if the
        // label's output ever crosses the pipe buffer.
        guard let output = try? ConcurrentProcess.run(
            executable: launchctlPath,
            arguments: ["list", label]
        ), output.status == 0 else { return nil }
        return String(data: output.stdout, encoding: .utf8)
    }
}

// MARK: - Live observer

/**
 * 👁️ Production `LaunchctlObserving` — wraps `launchctl list`.
 *
 * Default at Andromeda / MultibrainBar Observe boundaries.
 * Tests inject `MockLaunchctlListRunner` or stay on `MockLaunchctlObserver`.
 */
public struct LiveLaunchctlObserver: LaunchctlObserving {
    private let runner: any LaunchctlListRunning

    public init(runner: any LaunchctlListRunning = ProcessLaunchctlListRunner()) {
        self.runner = runner
    }

    public func observe(label: String) -> LaunchObservation? {
        guard let text = runner.listOutput(label: label) else { return nil }
        return LaunchObservation.parse(launchctlListOutput: text)
    }
}
