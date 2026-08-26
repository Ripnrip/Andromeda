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

    public init(
        sweepID: UUID, startedAt: Date, finishedAt: Date, censusSize: Int,
        pressure: Pressure, decisions: [KillDecision], outcomes: [KillOutcome],
        condemnedRSSBytes: UInt64, dryRun: Bool
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
    }
}

public struct KillOutcome: Sendable, Equatable, Codable {
    public enum Method: String, Sendable, Codable { case sigterm, sigkill, alreadyDead }
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
    @discardableResult
    public func sweep(dryRun: Bool = false, grace: Duration = .seconds(10)) async -> SweepReport {
        let startedAt = Date()
        let sweepID = UUID()

        let samples = (try? census.sampleAll()) ?? []
        let pressure = sampler.pressure(configuration: configuration)
        let decisions = policy.evaluate(
            census: samples,
            pressure: pressure,
            configuration: configuration
        )

        var outcomes: [KillOutcome] = []
        if !dryRun {
            for decision in decisions {
                outcomes.append(await execute(decision, grace: grace))
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
            dryRun: dryRun
        )
        await telemetry.record(report)
        return report
    }

    /// Executes one decision: SIGTERM, wait up to `grace` for the pid to
    /// exit, SIGKILL on timeout. Clock-driven deadline.
    public func execute<C: Clock>(
        _ decision: KillDecision,
        grace: Duration = .seconds(10),
        clock: C = ContinuousClock()
    ) async -> KillOutcome where C.Duration == Duration {
        guard signaler.alive(decision.pid) else {
            return KillOutcome(pid: decision.pid, method: .alreadyDead)
        }
        _ = signaler.signal(decision.pid, SIGTERM)
        let deadline = clock.now.advanced(by: grace)
        while clock.now < deadline {
            guard signaler.alive(decision.pid) else {
                return KillOutcome(pid: decision.pid, method: .sigterm)
            }
            try? await clock.sleep(for: .milliseconds(500))
        }
        if signaler.alive(decision.pid) {
            _ = signaler.signal(decision.pid, SIGKILL)
            return KillOutcome(pid: decision.pid, method: .sigkill)
        }
        return KillOutcome(pid: decision.pid, method: .sigterm)
    }
}
