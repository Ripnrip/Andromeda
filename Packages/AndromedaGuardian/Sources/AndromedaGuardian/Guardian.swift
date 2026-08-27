import Foundation
import OSLog

/// Loggers for the guardian package (file scope — generic types cannot hold
/// static stored properties). Emoji prefixes ride the emit sites — one
/// glyph per decision point, so a default Console.app filter reads like an
/// operator heartbeat.
enum GuardianLog {
    static let sweep = Logger(subsystem: "ai.andromeda.guardian", category: "sweep")
    static let census = Logger(subsystem: "ai.andromeda.guardian", category: "census")
    static let veto = Logger(subsystem: "ai.andromeda.guardian", category: "veto")
    static let signal = Logger(subsystem: "ai.andromeda.guardian", category: "signal")
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
/// Named sweep constants (file scope — generic types cannot hold static
/// stored properties).
public enum GuardianTuning {
    /// Poll cadence while waiting out a grace window (SIGTERM → exit watch).
    public static let gracePollInterval: Duration = .milliseconds(500)

    /// Maximum parent-chain hops before assuming a census cycle (8 ≈ two
    /// full agent→helper→child nests; beyond it the chain is bogus data).
    public static let parentChainHopLimit = 8
}

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
            GuardianLog.census.error("🛑 census failed — safe path, zero decisions: \(String(describing: error), privacy: .public)")
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

        let outcomes: [KillOutcome] = dryRun
            ? Self.logDryRun(sweepID: sweepID, decisions: decisions)
            : await executeAll(decisions, grace: grace)

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
        GuardianLog.sweep.info("📊 sweep \(sweepID.uuidString, privacy: .public): \(samples.count) sampled, \(decisions.count) condemned, \(outcomes.count) executed (\(dryRun ? "dry-run" : "live", privacy: .public))")
        await telemetry.record(report)
        return report
    }

    /// Dry-run leg: decisions computed, nothing signaled — one log, no state.
    private static func logDryRun(sweepID: UUID, decisions: [KillDecision]) -> [KillOutcome] {
        GuardianLog.sweep.info("⏸️ sweep \(sweepID.uuidString, privacy: .public) dry-run: \(decisions.count) decisions, nothing signaled")
        return []
    }

    /// Execution leg: an async map over decisions with two structural exits
    /// — the R2 parent-alive veto (per decision) and sweep-wide cancellation
    /// (a cancelled reaper never accelerates into forced kills).
    private func executeAll(_ decisions: [KillDecision], grace: Duration) async -> [KillOutcome] {
        var outcomes: [KillOutcome] = []
        for decision in decisions {
            if let parentPID = decision.parentPID, signaler.alive(parentPID) {
                GuardianLog.veto.notice("🛡️ parent \(parentPID) alive again — veto kill of \(decision.pid) (\(decision.executableName, privacy: .public))")
                outcomes.append(KillOutcome(pid: decision.pid, method: .skippedParentAlive))
                continue
            }
            let outcome = await execute(decision, grace: grace)
            outcomes.append(outcome)
            if outcome.method == .cancelled { break }
        }
        return outcomes
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
        switch PreFlight.check(decision, signaler: signaler) {
        case .veto(let method):
            Self.logVeto(decision, method: method)
            return KillOutcome(pid: decision.pid, method: method)

        case .condemned:
            GuardianLog.signal.notice("🎯 SIGTERM \(decision.pid) (\(decision.executableName, privacy: .public)) — \(decision.reason, privacy: .public)")
            _ = signaler.signal(decision.pid, SIGTERM)

            if let settled = await awaitGracefulExit(decision, grace: grace, clock: clock) {
                return settled
            }

            // Grace expired still alive: re-prove identity, then force.
            switch PreFlight.check(decision, signaler: signaler) {
            case .veto(let method):
                Self.logVeto(decision, method: method)
                return KillOutcome(pid: decision.pid, method: method)
            case .condemned:
                GuardianLog.signal.notice("💥 SIGKILL \(decision.pid) (\(decision.executableName, privacy: .public)) — grace expired")
                _ = signaler.signal(decision.pid, SIGKILL)
                return KillOutcome(pid: decision.pid, method: .sigkill)
            }
        }
    }

    /// Watches the pid for the grace window. Non-nil outcome settles the
    /// decision (exited / cancelled); nil = still alive at deadline.
    private func awaitGracefulExit<C: Clock>(
        _ decision: KillDecision,
        grace: Duration,
        clock: C
    ) async -> KillOutcome? where C.Duration == Duration {
        let deadline = clock.now.advanced(by: grace)
        do {
            while clock.now < deadline {
                if !signaler.alive(decision.pid) {
                    GuardianLog.signal.notice("✅ \(decision.pid) exited on SIGTERM (\(decision.executableName, privacy: .public))")
                    return KillOutcome(pid: decision.pid, method: .sigterm)
                }
                try await clock.sleep(for: GuardianTuning.gracePollInterval)
            }
        } catch {
            GuardianLog.signal.notice("⏹️ grace for \(decision.pid) cancelled — no escalation")
            return KillOutcome(pid: decision.pid, method: .cancelled)
        }
        return signaler.alive(decision.pid) ? nil : KillOutcome(pid: decision.pid, method: .sigterm)
    }

    private static func logVeto(_ decision: KillDecision, method: KillOutcome.Method) {
        switch method {
        case .skippedIdentityMismatch:
            GuardianLog.veto.notice("🪞 pid \(decision.pid) recycled (owner changed) — veto, never signal a stranger")
        case .skippedParentAlive:
            GuardianLog.veto.notice("🛡️ parent alive — veto kill of \(decision.pid)")
        case .alreadyDead:
            GuardianLog.signal.info("🕯️ \(decision.pid) already gone")
        case .sigterm, .sigkill, .cancelled:
            break // not veto paths
        }
    }

    /// The kill pre-flight: every reason NOT to signal, in one place.
    enum PreFlight {
        enum Result: Sendable {
            case condemned
            case veto(KillOutcome.Method)
        }

        static func check(_ decision: KillDecision, signaler: Signaler) -> Result {
            guard signaler.alive(decision.pid) else { return .veto(.alreadyDead) }
            if let start = decision.sampledStartTime,
               !signaler.matchesIdentity(decision.pid, sampledStartTime: start) {
                return .veto(.skippedIdentityMismatch)
            }
            return .condemned
        }
    }
}
