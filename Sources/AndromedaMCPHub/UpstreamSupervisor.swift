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

/// Real process host — Foundation `Process`.
public struct ProcessUpstreamHost: UpstreamProcessHosting {
    public init() {}

    public func launch(
        command: String, arguments: [String], environment: [String: String]
    ) -> UpstreamPipes? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
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
    public func ensureRunning() -> UpstreamPipes? {
        lock.lock(); defer { lock.unlock() }
        if let pipes = _pipes {
            return pipes
        }
        guard restartCount < maxRestarts else {
            telemetry.event(.upstreamExhausted(serverID: config.id, restarts: restartCount))
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

    /// Called when the stdout pipe closes (upstream died): clears state so
    /// the next `ensureRunning` respawns under the budget.
    public func upstreamExited() {
        lock.lock(); defer { lock.unlock() }
        _pipes = nil
        restartCount += 1
        backoff = min(backoff * 2, 30)
        telemetry.event(.upstreamExited(serverID: config.id, restarts: restartCount))
    }

    /// Test/teardown hook.
    public func forgetForTeardown() {
        lock.lock(); defer { lock.unlock() }
        _pipes = nil
        restartCount = 0
    }
}
