import AndromedaGuardian
import Foundation
import Testing

/// Policy + coordinator coverage: fixture censuses → typed verdicts, and the
/// full sweep through recording boundary mocks. No live process is ever
/// sampled or signaled.
@Suite("ProcessGuardian")
struct ProcessGuardianTests {

    // MARK: - Fixtures

    /// Builds a census sample with just the fields the policy reads.
    private func proc(
        pid: Int32,
        ppid: Int32 = 1,
        user: String = "admin",
        name: String,
        args: [String] = [],
        ageMinutes: Double = 30,
        rssMB: UInt64 = 100
    ) -> ProcessSample {
        ProcessSample(
            pid: pid, ppid: ppid, user: user,
            executablePath: "/usr/libexec/\(name)",
            args: args,
            startTime: Date().addingTimeInterval(-ageMinutes * 60),
            rssBytes: rssMB * 1024 * 1024
        )
    }

    private func daemon(_ pid: Int32, user: String = "admin", ageMinutes: Double = 30) -> ProcessSample {
        proc(pid: pid, user: user, name: ProcessFamily.sourceControlDaemonName, ageMinutes: ageMinutes, rssMB: 1_800)
    }

    private func mcpNode(_ pid: Int32, ppid: Int32, ageMinutes: Double = 30) -> ProcessSample {
        proc(pid: pid, ppid: ppid, name: "node", args: ["/opt/homebrew/bin/xcodebuildmcp", "mcp"], ageMinutes: ageMinutes)
    }

    private func evaluate(
        _ census: [ProcessSample],
        pressure: Pressure = .normal,
        configuration: GuardianConfiguration = GuardianConfiguration()
    ) -> [KillDecision] {
        PolicyEngine().evaluate(census: census, pressure: pressure, configuration: configuration)
    }

    // MARK: - Family classification

    @Test("classification is total and family-correct")
    func classification() {
        #expect(ProcessFamily.classify(daemon(1)) == .sourceControlDaemon(user: "admin"))
        #expect(ProcessFamily.classify(mcpNode(2, ppid: 1)) == .mcpChild(marker: "xcodebuildmcp"))
        #expect(ProcessFamily.classify(proc(pid: 3, name: "Claude")) == .agentHost)
        #expect(ProcessFamily.classify(proc(pid: 4, name: "CapCut")) == .userApplication)
        #expect(ProcessFamily.classify(proc(pid: 5, name: "loginwindow")) == .other)
        #expect(ProcessFamily.userApplication.isProtected)
        #expect(ProcessFamily.agentHost.isProtected)
        #expect(!(ProcessFamily.mcpChild(marker: "xcodebuildmcp").isProtected))
    }

    // MARK: - Pressure as transformation

    @Test("pressure selects gates exhaustively")
    func pressureGates() {
        let config = GuardianConfiguration()
        #expect(Pressure.normal.gates(configuration: config).daemonKeepPerUser == 2)
        #expect(Pressure.elevated.gates(configuration: config).daemonKeepPerUser == 1)
        #expect(Pressure.elevated.gates(configuration: config).mcpMaxAgeSeconds == 3_600)
    }

    // MARK: - R1: source-control horde

    @Test("no Xcode alive — every daemon is residue, all reaped")
    func hordeReapedWhenXcodeDead() {
        let decisions = evaluate([daemon(101), daemon(102, user: "root"), daemon(103)])
        #expect(decisions.count == 3)
        #expect(decisions.allSatisfy { $0.rule == .sourceControlHorde })
        #expect(decisions.allSatisfy { $0.reason.contains("residue") })
    }

    @Test("Xcode alive — keep newest 2 per user, reap the rest")
    func hordeCappedPerUser() {
        let decisions = evaluate([
            proc(pid: 1, name: "Xcode", ageMinutes: 500),
            daemon(201, ageMinutes: 10),
            daemon(202, ageMinutes: 20),
            daemon(203, ageMinutes: 30),
            daemon(204, ageMinutes: 40),
            daemon(205, user: "root", ageMinutes: 5),
            daemon(206, user: "root", ageMinutes: 15),
            daemon(207, user: "root", ageMinutes: 25),
        ])
        // admin: keep 201+202 (youngest 2), reap 203+204. root: keep 205+206, reap 207.
        #expect(Set(decisions.map(\.pid)) == [203, 204, 207])
    }

    @Test("over-age daemon reaped even within the per-user cap")
    func leakAgeBeatsCap() {
        let decisions = evaluate([
            proc(pid: 1, name: "Xcode", ageMinutes: 500),
            daemon(301, ageMinutes: 60 * 7),
            daemon(302, ageMinutes: 10),
        ])
        #expect(decisions.map(\.pid) == [301])
    }

    @Test("elevated pressure tightens the cap to 1 per user")
    func pressureEscalationTightensCap() {
        let decisions = evaluate([
            proc(pid: 1, name: "Xcode", ageMinutes: 500),
            daemon(401, ageMinutes: 10),
            daemon(402, ageMinutes: 20),
            daemon(403, ageMinutes: 30),
        ], pressure: .elevated)
        #expect(Set(decisions.map(\.pid)) == [402, 403])
    }

    // MARK: - R2: orphaned MCP children

    @Test("orphaned aged MCP child reaped")
    func orphanReaped() {
        let decisions = evaluate([mcpNode(501, ppid: 999, ageMinutes: 60 * 5)])
        #expect(decisions.count == 1)
        #expect(decisions[0].rule == .orphanedMCPChild)
    }

    @Test("young orphan gets a grace window, not a kill")
    func youngOrphanSpared() {
        #expect(evaluate([mcpNode(502, ppid: 999, ageMinutes: 10)]).isEmpty)
    }

    @Test("MCP child of a live agent host is protected")
    func liveSessionChildProtected() {
        #expect(evaluate([
            proc(pid: 600, name: "Claude", ageMinutes: 200),
            mcpNode(601, ppid: 600, ageMinutes: 60 * 9),
        ]).isEmpty)
    }

    @Test("orphan chain reaching an agent host through a helper is protected")
    func chainProtection() {
        #expect(evaluate([
            proc(pid: 700, name: "Letta Helper (Renderer)", ageMinutes: 300),
            proc(pid: 701, ppid: 700, name: "node", args: ["/usr/bin/something-else"], ageMinutes: 100),
            mcpNode(702, ppid: 701, ageMinutes: 60 * 8),
        ]).isEmpty)
    }

    @Test("non-MCP node processes are ignored entirely")
    func plainNodeIgnored() {
        #expect(evaluate([
            proc(pid: 800, ppid: 999, name: "node", args: ["./server.js"], ageMinutes: 60 * 20),
        ]).isEmpty)
    }

    // MARK: - Idempotency

    @Test("same census yields the same decisions")
    func idempotent() {
        let census = [daemon(901), daemon(902), mcpNode(903, ppid: 999, ageMinutes: 60 * 6)]
        #expect(evaluate(census) == evaluate(census))
    }

    // MARK: - Coordinator through recording boundaries

    /// Fixture census: returns what it was given.
    struct FixtureCensus: CensusProvider {
        let samples: [ProcessSample]
        func sampleAll() throws -> [ProcessSample] { samples }
    }

    /// Fixture pressure: returns what it was given.
    struct FixturePressure: PressureProvider {
        let value: Pressure
        func pressure(configuration: GuardianConfiguration) -> Pressure { value }
    }

    /// Records signals; alive-state is scriptable. A locked class, not an
    /// actor: the signaler protocol is synchronous (kill(2) is sync), so a
    /// sync conformance must be nonisolated.
    final class RecordingSignaler: ProcessSignaler, @unchecked Sendable {
        private let lock = NSLock()
        private var _signals: [(pid: Int32, sig: Int32)] = []
        private var livePIDs: Set<Int32>
        /// PIDs whose identity check should FAIL (simulating PID reuse).
        var mismatchedPIDs: Set<Int32> = []

        init(livePIDs: Set<Int32>) { self.livePIDs = livePIDs }

        var signals: [(pid: Int32, sig: Int32)] {
            lock.withLock { _signals }
        }

        func signal(_ pid: Int32, _ sig: Int32) -> Bool {
            lock.withLock {
                _signals.append((pid, sig))
                if sig == SIGKILL || sig == SIGTERM { livePIDs.remove(pid) }
            }
            return true
        }

        func alive(_ pid: Int32) -> Bool {
            lock.withLock { livePIDs.contains(pid) }
        }

        func matchesIdentity(_ pid: Int32, sampledStartTime: Date) -> Bool {
            lock.withLock { !mismatchedPIDs.contains(pid) }
        }
    }

    /// Records sweep reports.
    actor RecordingTelemetry: TelemetrySink {
        private(set) var reports: [SweepReport] = []
        func record(_ report: SweepReport) { reports.append(report) }
    }

    @Test("dry-run sweep decides everything, signals nothing, still telemeters")
    func dryRunSweep() async {
        let census = [daemon(101), daemon(102), mcpNode(103, ppid: 999, ageMinutes: 60 * 6)]
        let signaler = RecordingSignaler(livePIDs: [101, 102, 103])
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FixtureCensus(samples: census),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )

        let report = await guardian.sweep(dryRun: true)
        #expect(report.dryRun)
        #expect(report.decisions.count == 3)
        #expect(report.outcomes.isEmpty)
        #expect(report.censusSize == 3)
        #expect(report.condemnedRSSBytes == decisions(of: report).reduce(0) { $0 + $1.rssBytes })
        #expect(signaler.signals.isEmpty)
        let reports = await telemetry.reports
        #expect(reports.count == 1)
    }

    @Test("live sweep signals every decision and reports outcomes")
    func liveSweep() async {
        let census = [daemon(201), mcpNode(202, ppid: 999, ageMinutes: 60 * 6)]
        let signaler = RecordingSignaler(livePIDs: [201, 202])
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FixtureCensus(samples: census),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )

        let report = await guardian.sweep(grace: .seconds(1))
        #expect(!report.dryRun)
        #expect(report.outcomes.count == 2)
        #expect(report.outcomes.allSatisfy { $0.method == .sigterm })
        #expect(signaler.signals.count == 2)
        #expect(signaler.signals.allSatisfy { $0.sig == SIGTERM })
    }

    @Test("already-dead pid is reported, not signaled")
    func alreadyDead() async {
        let signaler = RecordingSignaler(livePIDs: [])
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FixtureCensus(samples: [daemon(301)]),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )

        let report = await guardian.sweep(grace: .seconds(1))
        #expect(report.outcomes.map(\.method) == [.alreadyDead])
        #expect(signaler.signals.isEmpty)
    }

    // MARK: - Kill-path safety (review round 2026-08-26)

    @Test("PID reuse vetoes the kill — identity mismatch, nothing signaled")
    func identityMismatchVetoes() async {
        let signaler = RecordingSignaler(livePIDs: [401])
        signaler.mismatchedPIDs = [401]
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FixtureCensus(samples: [daemon(401)]),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )
        let report = await guardian.sweep(grace: .seconds(1))
        #expect(report.outcomes.map(\.method) == [.skippedIdentityMismatch])
        #expect(signaler.signals.isEmpty)
    }

    @Test("orphan whose parent came back to life is vetoed at execution")
    func parentAliveVetoes() async {
        // Census sees the orphan (parent 999 absent); by execution time the
        // parent is alive again (signaler sees it).
        let census = [mcpNode(501, ppid: 999, ageMinutes: 60 * 6)]
        let signaler = RecordingSignaler(livePIDs: [501, 999])
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FixtureCensus(samples: census),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )
        let report = await guardian.sweep(grace: .seconds(1))
        #expect(report.outcomes.map(\.method) == [.skippedParentAlive])
        #expect(signaler.signals.isEmpty)
    }

    /// Census provider that always fails.
    struct FailingCensus: CensusProvider {
        struct Boom: Error {}
        func sampleAll() throws -> [ProcessSample] { throw Boom() }
    }

    @Test("census failure yields an error report — zero decisions, zero signals")
    func censusFailureIsSafe() async {
        let signaler = RecordingSignaler(livePIDs: [])
        let telemetry = RecordingTelemetry()
        let guardian = Guardian(
            census: FailingCensus(),
            sampler: FixturePressure(value: .normal),
            signaler: signaler,
            telemetry: telemetry
        )
        let report = await guardian.sweep()
        #expect(report.censusError != nil)
        #expect(report.decisions.isEmpty)
        #expect(report.outcomes.isEmpty)
        #expect(signaler.signals.isEmpty)
        let reports = await telemetry.reports
        #expect(reports.count == 1)
    }

    @Test("unanchored marker text does NOT classify as MCP child")
    func anchoredMarkerMatching() {
        // env-var-style text containing the marker (not a path component).
        let envStyle = proc(
            pid: 601, ppid: 999, name: "node",
            args: ["./server.js", "--config", "NODE_OPTIONS=--require xcodebuildmcp/register"],
            ageMinutes: 60 * 9
        )
        #expect(ProcessFamily.classify(envStyle) == .other)
        // Similarly-named directory is not the marker.
        let nearMiss = proc(
            pid: 602, ppid: 999, name: "node",
            args: ["/Users/x/my-claude-mem-notes/server.js"],
            ageMinutes: 60 * 9
        )
        #expect(ProcessFamily.classify(nearMiss) == .other)
        // Exact path component IS the marker.
        let real = proc(
            pid: 603, ppid: 999, name: "node",
            args: ["/opt/homebrew/bin/xcodebuildmcp", "mcp"],
            ageMinutes: 60 * 9
        )
        #expect(ProcessFamily.classify(real) == .mcpChild(marker: "xcodebuildmcp"))
    }

    /// Extracts decisions for byte accounting assertions.
    private func decisions(of report: SweepReport) -> [KillDecision] {
        report.decisions
    }
}
