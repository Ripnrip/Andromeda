import Foundation

/// Health probe for the Letta Slack channels LaunchAgent
/// (`com.binarybros.letta-channels`).
///
/// The daemon silently stayed unloaded for 10 days because nothing
/// observed it — fleet visibility (AGENTS.md charter: "no invisible
/// launch agents", "everything important is observable") requires an
/// explicit probe a human or cron can run cheaply. This type answers
/// three independent questions so a failure localizes immediately:
/// is the job registered with launchd, is the process actually alive,
/// and is it producing output (a wedged-but-alive daemon shows up as a
/// stale log, not as a missing PID).
///
/// Shell and clock are injected (`ShellExecuting` like
/// `LaunchAgentInstaller`, a `now` closure) so tests exercise the
/// classification logic without touching live `launchctl` or `pgrep`,
/// and log-freshness is tested against synthetic timestamps rather
/// than sleeping.
public struct LettaChannelsHealthProbe: Sendable {
    /// Probe outcome. `healthy` is the exit-code contract: false when
    /// the agent is not loaded OR the process is absent. A stale log
    /// only downgrades to a warning — a live process with a quiet hour
    /// is suspicious, not proven-dead.
    public struct Report: Sendable {
        public let loaded: Bool
        public let running: Bool
        public let logAge: TimeInterval?
        public let logStale: Bool

        /// True only when the hard signals (launchd registration +
        /// live process) are both green. This is what `andromeda fleet
        /// status` uses as its exit code.
        public var healthy: Bool { loaded && running }
    }

    public static let label = "com.binarybros.letta-channels"

    /// Anything older than this (seconds) is flagged stale. One hour
    /// matches the daemon's ambient chatter cadence; a shorter window
    /// would false-positive during quiet Slack periods.
    public static let staleLogThreshold: TimeInterval = 3600

    public let uid: UInt32
    public let daemonPath: String
    public let logPath: String
    public let staleThreshold: TimeInterval

    private let shell: any ShellExecuting
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - uid: gui/<uid> launchd domain owner.
    ///   - daemonPath: absolute script path; `pgrep -f` matches on the
    ///     full argument string, which excludes unrelated node daemons.
    ///   - logPath: mtime of this file is the freshness signal.
    ///   - shell: executor for launchctl/pgrep (mocked in tests).
    ///   - now: injected clock so log age is deterministic in tests.
    public init(
        uid: UInt32,
        daemonPath: String = "/Users/admin/.local/bin/LettaChannels",
        logPath: String = "/Users/admin/.letta/logs/letta-channels.out.log",
        staleThreshold: TimeInterval = LettaChannelsHealthProbe.staleLogThreshold,
        shell: (any ShellExecuting)? = LiveShell(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.uid = uid
        self.daemonPath = daemonPath
        self.logPath = logPath
        self.staleThreshold = staleThreshold
        self.shell = shell ?? LiveShell()
        self.now = now
    }

    /// Run all three checks and classify. `launchctl print` exit status
    /// is the loaded signal (exit 0 iff the job exists in the gui
    /// domain); `pgrep -f` exit status is the running signal (pgrep
    /// exits 1 on no match). A missing log is reported as nil age, not
    /// staleness — the daemon may be freshly installed and simply has
    /// not written yet.
    public func probe() async -> Report {
        // launchctl print: exit status is the whole signal; we never
        // need the (large) property-list body for a loaded/not-loaded
        // verdict, so discard output.
        let printResult = try? await shell.execute([
            "/bin/launchctl", "print", "gui/\(uid)/\(Self.label)",
        ])
        let loaded = printResult?.success ?? false

        // pgrep -f: match the script path, not just "node" — the host
        // runs several node daemons and a name-only match would report
        // this one alive whenever any of them runs.
        let pgrepResult = try? await shell.execute([
            "/usr/bin/pgrep", "-f", daemonPath,
        ])
        let running = pgrepResult?.success ?? false

        let logAge = logAgeSeconds()
        return Report(
            loaded: loaded,
            running: running,
            logAge: logAge,
            logStale: logAge.map { $0 > staleThreshold } ?? false
        )
    }

    /// mtime age of the log, or nil when the file is absent/unreadable.
    /// FileManager (not `stat` via the shell) because this is a local
    /// filesystem read — no process spawn, nothing to mock beyond the
    /// injected clock.
    private func logAgeSeconds() -> TimeInterval? {
        guard
            let mtime = try? FileManager.default.attributesOfItem(
                atPath: logPath
            )[.modificationDate] as? Date
        else { return nil }
        return now().timeIntervalSince(mtime)
    }
}
