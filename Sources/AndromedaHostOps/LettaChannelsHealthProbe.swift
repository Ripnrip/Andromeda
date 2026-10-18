import Foundation

/// Model tier for the fleet fallback cascade. Enum (not raw String)
/// because a tier is a typed, enumerated choice — it carries its own
/// `rawValue` (the provider/model handle the agent retrieve path
/// consults) while staying exhaustive at compile time. A `[String]`
/// would let any stray value through silently; this forces every tier
/// to be a known, declared model.
public enum Tier: String, CaseIterable, Sendable {
    /// Native best-effort provider (needs `letta connect` to refresh
    /// OAuth; falls through when the token is stale).
    case xaiGrok46 = "xai/grok-4.6"
    /// Openai-compatible fallback, always tested at load.
    case glm53 = "openai-compatible/glm/glm-5.3"
    /// Secondary openai-compatible tier (added when the primary is
    /// down or quota-limited).
    case glm52 = "openai-compatible/glm/glm-5.2"

    /// All tiers in cascade order: primary first, fallbacks after.
    /// The order is the contract — `probe()` tries them in this
    /// sequence and `fleet status` reports the first live one.
    public static let cascade: [Tier] = [
        .xaiGrok46,
        .glm53,
        .glm52,
    ]
}

/// Home-relative layout for the Letta channels supervisor. Enum cases,
/// not concatenated path strings — a typo in `".local/bin"` would
/// otherwise silently install to the wrong place on every host.
public enum LettaChannelsLayout: Sendable {
    case supervisorBinary
    case outLog
    case errLog
    case tiersFile

    public func url(home: String) -> URL {
        let root = URL(fileURLWithPath: home, isDirectory: true)
        switch self {
        case .supervisorBinary:
            return root.appendingPathComponent(".local/bin/LettaChannels")
        case .outLog:
            return root.appendingPathComponent(".letta/logs/letta-channels.out.log")
        case .errLog:
            return root.appendingPathComponent(".letta/logs/letta-channels.err.log")
        case .tiersFile:
            return root.appendingPathComponent(".andromeda/fleet/letta-channels.tiers")
        }
    }
}

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
        public let tiers: [Tier]
        public let tierStatus: [Tier: Bool]

        /// True when launchd + process are up, and — if any tiers were
        /// configured — at least one catalog handle is live. Empty
        /// tiers keep the old process-only contract so a host that
        /// has not set a cascade yet is not failed closed.
        public var healthy: Bool {
            guard loaded && running else { return false }
            if tiers.isEmpty { return true }
            return hasLiveTier
        }

        /// True only when at least one model tier is reachable.
        public var hasLiveTier: Bool { tierStatus.values.contains(true) }
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
    public let tiers: [Tier]

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
        daemonPath: String = LettaChannelsLayout.supervisorBinary.url(home: NSHomeDirectory()).path,
        logPath: String = LettaChannelsLayout.outLog.url(home: NSHomeDirectory()).path,
        staleThreshold: TimeInterval = LettaChannelsHealthProbe.staleLogThreshold,
        tiers: [Tier] = [],
        shell: (any ShellExecuting)? = LiveShell(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.uid = uid
        self.daemonPath = daemonPath
        self.logPath = logPath
        self.staleThreshold = staleThreshold
        self.tiers = tiers
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
        let tierStatus = await probeTierStatus()
        return Report(
            loaded: loaded,
            running: running,
            logAge: logAge,
            logStale: logAge.map { $0 > staleThreshold } ?? false,
            tiers: tiers,
            tierStatus: tierStatus
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

    /// Verify each configured model tier by asking the local `letta`
    /// catalog whether the handle resolves. A tier that fails (429,
    /// 403, unknown-model, timeout) is marked inactive so
    /// `fleet status` can report which models are actually usable
    /// instead of assuming every listed tier is live.
    ///
    /// `letta model list` is the cheapest universal probe: it needs
    /// no provider-specific endpoint and returns the same catalog
    /// the agent retrieve path consults. The shell is injected so
    /// tests can stub the output deterministically.
    private func probeTierStatus() async -> [Tier: Bool] {
        guard !tiers.isEmpty else { return [:] }
        let list = try? await shell.execute([
            "/usr/bin/env", "letta", "model", "list",
        ])
        let output = list?.output ?? ""
        var status: [Tier: Bool] = [:]
        for tier in tiers {
            status[tier] = output.contains(tier.rawValue)
        }
        return status
    }
}
