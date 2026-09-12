// AndromedaMCPHub — upstream supervisor: owns one Process per hosted server.
//
// Spawns the RESOLVED executable directly (no `npm exec` at runtime — the
// sprawl blob dies here). Restart budget with exponential backoff, stdin/
// stdout pipes owned by the hub, exits surfaced as telemetry. Process
// handles sit behind a protocol for fixture-based tests (guardian-plan
// discipline: tests never spawn or kill real processes).

import Foundation

#if canImport(OSLog)
    import os
#endif

// MARK: - Process factory (injectable)

/// Creates and runs child processes — protocol-injected for tests.
public protocol UpstreamProcessHosting: Sendable {
    /// Launch the resolved command; return its stdin/stdout file handles.
    func launch(command: String, arguments: [String], environment: [String: String])
        -> UpstreamPipes?
}

/// The live pipes of one running upstream.
public struct UpstreamPipes: Sendable {
    public let stdin: FileHandle
    public let stdout: FileHandle
    public let stderr: FileHandle

    public init(stdin: FileHandle, stdout: FileHandle, stderr: FileHandle) {
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Environment keys every hosted server needs. An enum — not a Set<String>
/// of magic strings — so the allowlist is exhaustive by construction, its
/// membership is CaseIterable-testable, and a typo cannot silently admit a
/// key that was never reviewed (Codex P1: copying the ambient environment
/// hands every hosted process all credentials in scope of whoever launched
/// the hub, bypassing the per-server env entirely). Secrets-bearing
/// servers get their keys via the hub config's `environment` (broker lane
/// later) — never ambient.
public enum EnvironmentAllowKey: String, CaseIterable, Sendable {
    case path = "PATH"
    case home = "HOME"
    case lang = "LANG"
    case lcAll = "LC_ALL"
    case tmpdir = "TMPDIR"
    case xdgCacheHome = "XDG_CACHE_HOME"
}

/// Real process host — Foundation `Process`.
public struct ProcessUpstreamHost: UpstreamProcessHosting {
    public init() {}

    /// The ambient keys that survive into a hosted process. Derived from
    /// the enum, never hand-maintained (drift between the two was the
    /// failure mode of the raw-string Set).
    static var environmentAllowlist: Set<String> {
        Set(EnvironmentAllowKey.allCases.map(\.rawValue))
    }

    public func launch(
        command: String, arguments: [String], environment: [String: String]
    ) -> UpstreamPipes? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            Self.environmentAllowlist.contains(key)
        }
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }
        // Keep the process object alive for the pipes' lifetime: the hub
        // never terminates upstreams it did not decide to stop.
        objc_setAssociatedObject(
            stdoutPipe, &ProcessUpstreamHost.processSlot, process, .OBJC_ASSOCIATION_RETAIN
        )
        return UpstreamPipes(
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading
        )
    }

    private nonisolated(unsafe) static var processSlot: UInt8 = 0
}

// MARK: - Supervisor

/// Owns ONE hosted server's upstream process lifecycle. NSLock-guarded
/// class, not an actor: the hub's callback I/O (readability handlers) is
/// nonisolated and needs synchronous access to pipe state.
public final class UpstreamSupervisor: @unchecked Sendable {
    private let config: HubServerConfig
    private let host: UpstreamProcessHosting
    private let telemetry: HubTelemetry
    private let lock = NSLock()
    private var _pipes: UpstreamPipes?
    private var restartCount = 0
    private let maxRestarts = 5
    private var backoff: TimeInterval = 1
    /// Earliest instant a respawn may be attempted after an exit (the
    /// enforced backoff window — Codex round 3).
    private var nextEligibleLaunchAt: Date?

    public init(config: HubServerConfig, host: UpstreamProcessHosting = ProcessUpstreamHost(),
                telemetry: HubTelemetry = HubTelemetry.shared)
    {
        self.config = config
        self.host = host
        self.telemetry = telemetry
    }

    public var serverID: String {
        config.id
    }

    // MARK: Lifecycle

    /// Spawn (first call) or respawn the upstream. Returns the live pipes.
    /// Respawns inside the backoff window return nil (the caller's
    /// unavailable-path answers the client) — the window is real, not
    /// telemetry-only (Codex round 3).
    public func ensureRunning() -> UpstreamPipes? {
        lock.lock(); defer { lock.unlock() }
        if let pipes = _pipes {
            return pipes
        }
        guard restartCount < maxRestarts else {
            telemetry.event(.upstreamExhausted(serverID: config.id, restarts: restartCount))
            return nil
        }
        if let eligible = nextEligibleLaunchAt, Date() < eligible {
            return nil
        }
        guard let pipes = host.launch(
            command: config.command,
            arguments: config.arguments,
            environment: config.environment
        ) else {
            restartCount += 1
            telemetry.event(.upstreamSpawnFailed(serverID: config.id, attempt: restartCount))
            return nil
        }
        _pipes = pipes
        telemetry.event(.upstreamSpawned(
            serverID: config.id, command: config.command, attempt: restartCount
        ))
        return pipes
    }

    /// The live pipes, if an upstream is currently running (Codex round 3:
    /// callers resolving stdin per write must see respawns immediately).
    public func livePipes() -> UpstreamPipes? {
        lock.lock(); defer { lock.unlock() }
        return _pipes
    }

    /// Called when the stdout pipe closes (upstream died): clears state so
    /// the next `ensureRunning` respawns under the budget. The backoff
    /// window is ENFORCED here (Codex round 3): `ensureRunning` refuses to
    /// launch again until `nextEligibleLaunchAt` has passed, so a crashing
    /// upstream cannot burn the whole budget in a tight reconnect loop.
    public func upstreamExited() {
        lock.lock(); defer { lock.unlock() }
        _pipes = nil
        restartCount += 1
        backoff = min(backoff * 2, 30)
        nextEligibleLaunchAt = Date().addingTimeInterval(backoff)
        telemetry.event(.upstreamExited(serverID: config.id, restarts: restartCount))
        // 🔁 a restart is now scheduled — the decision point the agent host
        // cannot otherwise see (the exit alone reads as terminal).
        if restartCount <= maxRestarts {
            telemetry.event(.upstreamRestartScheduled(
                serverID: config.id, restarts: restartCount, backoffSeconds: backoff
            ))
        }
    }

    /// Write one line to the live upstream's stdin (used by the hub to
    /// answer server-initiated requests itself). Nil-returning no-op when
    /// no upstream is live.
    public func writeUpstream(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        _ = try? _pipes?.stdin.write(contentsOf: data)
    }

    /// Test/teardown hook.
    public func forgetForTeardown() {
        lock.lock(); defer { lock.unlock() }
        _pipes = nil
        restartCount = 0
        nextEligibleLaunchAt = nil
    }
}
