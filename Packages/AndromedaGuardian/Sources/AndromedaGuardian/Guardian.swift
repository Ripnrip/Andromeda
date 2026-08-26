import Foundation
import OSLog

/// Loggers for the guardian package (file scope — generic types cannot hold
/// static stored properties).
enum GuardianLog {
    static let sweep = Logger(subsystem: "ai.andromeda.guardian", category: "sweep")
}

// MARK: - The guardian
//
// The coordinator: census → pressure → policy → execution → telemetry.
// Generic over every boundary so production wires libproc + kill(2) and
// tests wire fixtures + recordings through the same code path.

/// One completed sweep, the telemetry atom.
public struct SweepReport: Sendable, Equatable, Codable {
    public var sweepID: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var censusSize: Int
    public var pressure: Pressure
    public var decisions: [KillDecision]
    public var outcomes: [KillOutcome]
    /// RSS (bytes) of every process condemned, whether or not the kill landed.
    public var condemnedRSSBytes: UInt64
    /// True when decisions were computed but nothing was signaled.
    public var dryRun: Bool
    /// Census failure description when the sweep could not sample the
    /// process table. Non-nil means: no decisions, no signals — the
    /// failure path is the safe path.
    public var censusError: String?

    public init(
        sweepID: UUID, startedAt: Date, finishedAt: Date, censusSize: Int,
        pressure: Pressure, decisions: [KillDecision], outcomes: [KillOutcome],
        condemnedRSSBytes: UInt64, dryRun: Bool, censusError: String? = nil
    ) {
        self.sweepID = sweepID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.censusSize = censusSize
        self.pressure = pressure
        self.decisions = decisions
        self.outcomes = outcomes
        self.condemnedRSSBytes = condemnedRSSBytes
        self.dryRun = dryRun
        self.censusError = censusError
    }
}

public struct KillOutcome: Sendable, Equatable, Codable {
    public enum Method: String, Sendable, Codable {
        case sigterm
        case sigkill
        case alreadyDead
        /// The sweep task was cancelled mid-grace — no forced kill followed.
        case cancelled
        /// The pid's owner changed between census and signal (PID reuse) —
        /// the kill was vetoed rather than risk an innocent replacement.
        case skippedIdentityMismatch
        /// An orphan verdict's parent came back to life between census and
        /// execution — the kill was vetoed.
        case skippedParentAlive
    }
    public var pid: Int32
    public var method: Method

    public init(pid: Int32, method: Method) {
        self.pid = pid
        self.method = method
    }
}

/// The process guardian. Fleet-pillar mutation surface — typed Swift
/// (BIN-101), never bash; every sweep leaves a telemetry record
/// (AGENTS.md: visible status, telemetry, ownership, controls).
public struct Guardian<Census: CensusProvider, Sampler: PressureProvider, Signaler: ProcessSignaler>: Sendable {

    public let configuration: GuardianConfiguration
    public let policy: PolicyEngine
    public let census: Census
    public let sampler: Sampler
    public let signaler: Signaler
    public let telemetry: any TelemetrySink

    public init(
        configuration: GuardianConfiguration = GuardianConfiguration(),
        policy: PolicyEngine = PolicyEngine(),
        census: Census,
        sampler: Sampler,
        signaler: Signaler,
        telemetry: any TelemetrySink
    ) {
        self.configuration = configuration
        self.policy = policy
        self.census = census
        self.sampler = sampler
        self.signaler = signaler
        self.telemetry = telemetry
    }

    // MARK: - Sweep

    /// One full sweep: sample, judge, execute (unless dry-run), report.
    /// Bounded: exactly one census, one decision set, one execution pass.
    /// Idempotent: the same host state yields the same decisions.
    ///
    /// A failed census is NOT an empty success — the report carries
    /// `censusError`, zero decisions are produced, and nothing is signaled
    /// (an empty census would make every MCP child look orphaned: the
    /// failure path must be the safe path).
    @discardableResult
    public func sweep(dryRun: Bool = false, grace: Duration = .seconds(10)) async -> SweepReport {
        let startedAt = Date()
        let sweepID = UUID()

        let samples: [ProcessSample]
        do {
            samples = try census.sampleAll()
        } catch {
            let report = SweepReport(
                sweepID: sweepID,
                startedAt: startedAt,
                finishedAt: Date(),
                censusSize: 0,
                pressure: sampler.pressure(configuration: configuration),
                decisions: [],
                outcomes: [],
                condemnedRSSBytes: 0,
                dryRun: dryRun,
                censusError: String(describing: error)
            )
            await telemetry.record(report)
            return report
        }

        let pressure = sampler.pressure(configuration: configuration)
        let decisions = policy.evaluate(
            census: samples,
            pressure: pressure,
            configuration: configuration
        )

        var outcomes: [KillOutcome] = []
        if !dryRun {
            for decision in decisions {
                // R2 veto: the orphan's parent may have come back to life
                // between census and execution — check before signaling.
                if let parentPID = decision.parentPID, signaler.alive(parentPID) {
                    outcomes.append(KillOutcome(pid: decision.pid, method: .skippedParentAlive))
                    continue
                }
                let outcome = await execute(decision, grace: grace)
                outcomes.append(outcome)
                // Cancellation stops the sweep — remaining decisions are
                // not executed (a cancelled reaper must not accelerate
                // into forced kills).
                if outcome.method == .cancelled { break }
            }
        } else {
            GuardianLog.sweep.info("guardian sweep \(sweepID.uuidString, privacy: .public) dry-run: \(decisions.count) decisions, nothing signaled")
        }

        let report = SweepReport(
            sweepID: sweepID,
            startedAt: startedAt,
            finishedAt: Date(),
            censusSize: samples.count,
            pressure: pressure,
            decisions: decisions,
            outcomes: outcomes,
            condemnedRSSBytes: decisions.reduce(0) { $0 + $1.rssBytes },
            dryRun: dryRun,
            censusError: nil
        )
        await telemetry.record(report)
        return report
    }

    /// Executes one decision: SIGTERM, wait up to `grace` for the pid to
    /// exit, SIGKILL on timeout. Clock-driven deadline.
    ///
    /// Identity is revalidated immediately before each signal: if the pid's
    /// owner changed since the census (PID reuse), the kill is vetoed —
    /// the guardian never signals a process it did not condemn.
    /// Cancellation propagates: a cancelled grace returns `.cancelled`
    /// and never escalates to SIGKILL.
    public func execute<C: Clock>(
        _ decision: KillDecision,
        grace: Duration = .seconds(10),
        clock: C = ContinuousClock()
    ) async -> KillOutcome where C.Duration == Duration {
        guard signaler.alive(decision.pid) else {
            return KillOutcome(pid: decision.pid, method: .alreadyDead)
        }
        if let start = decision.sampledStartTime, !signaler.matchesIdentity(decision.pid, sampledStartTime: start) {
            return KillOutcome(pid: decision.pid, method: .skippedIdentityMismatch)
        }
        _ = signaler.signal(decision.pid, SIGTERM)
        let deadline = clock.now.advanced(by: grace)
        do {
            while clock.now < deadline {
                guard signaler.alive(decision.pid) else {
                    return KillOutcome(pid: decision.pid, method: .sigterm)
                }
                try await clock.sleep(for: .milliseconds(500))
            }
        } catch is CancellationError {
            return KillOutcome(pid: decision.pid, method: .cancelled)
        } catch {
            return KillOutcome(pid: decision.pid, method: .cancelled)
        }
        guard signaler.alive(decision.pid) else {
            return KillOutcome(pid: decision.pid, method: .sigterm)
        }
        if let start = decision.sampledStartTime, !signaler.matchesIdentity(decision.pid, sampledStartTime: start) {
            return KillOutcome(pid: decision.pid, method: .skippedIdentityMismatch)
        }
        _ = signaler.signal(decision.pid, SIGKILL)
        return KillOutcome(pid: decision.pid, method: .sigkill)
    }
}
