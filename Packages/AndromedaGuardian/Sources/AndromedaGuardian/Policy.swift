import Foundation

// MARK: - Policy
//
// Pure functions: census in, verdicts out. Rules are values composed in a
// pipeline; R4 (never-touch) is enforced structurally by the engine, so no
// rule — present or future — can condemn a protected family.

/// Everything a rule needs to judge a census, computed once.
public struct PolicyContext: Sendable {
    public let census: [ProcessSample]
    public let pressure: Pressure
    public let configuration: GuardianConfiguration

    public init(census: [ProcessSample], pressure: Pressure, configuration: GuardianConfiguration) {
        self.census = census
        self.pressure = pressure
        self.configuration = configuration
    }

    /// The gates this pressure level selects.
    public var gates: EffectiveGates { pressure.gates(configuration: configuration) }

    /// PIDs present in the census (a dead parent is simply absent).
    public var livePIDs: Set<Int32> { Set(census.map(\.pid)) }

    /// PID → sample lookup for parent-chain walks.
    public var byPID: [Int32: ProcessSample] {
        Dictionary(uniqueKeysWithValues: census.map { ($0.pid, $0) })
    }

    /// PID → family classification, computed once for the whole census.
    public var families: [Int32: ProcessFamily] {
        census.reduce(into: [:]) { $0[$1.pid] = ProcessFamily.classify($1) }
    }

    /// True when any Xcode-family driver is alive (daemons have an owner).
    public var xcodeAlive: Bool {
        census.contains { sample in
            let name = sample.executableName
            return name == "Xcode" || name == "xcodebuild" || name.hasPrefix("Simulator")
        }
    }

    /// Bounded parent-chain walk from a sample; stops at launchd, missing
    /// parents, or 8 hops (cycles are a census artifact).
    public func parentChain(of sample: ProcessSample) -> [ProcessSample] {
        let table = byPID
        var chain: [ProcessSample] = []
        var cursor = sample
        while cursor.ppid > 1, let parent = table[cursor.ppid], chain.count < 8 {
            chain.append(parent)
            cursor = parent
        }
        return chain
    }

    /// True when any ancestor is a live agent host (protected subtree).
    public func reachesAgentHost(_ sample: ProcessSample) -> Bool {
        parentChain(of: sample).contains {
            ProcessFamily.agentHostNames.contains($0.executableName)
        }
    }
}

/// A policy rule maps a context to kill decisions. Rules are pure values:
/// a new sprawl family gets a new rule added to `PolicyEngine.rules`, never
/// an edit to an existing one (open/closed — the R2 lesson family).
public typealias PolicyRule = @Sendable (PolicyContext) -> [KillDecision]

/// The policy engine: composes rules, applies the structural protection
/// filter, and stays pure — execution lives elsewhere.
public struct PolicyEngine: Sendable {

    /// The rules the engine runs, in evaluation order.
    public let rules: [PolicyRule]

    public init(rules: [PolicyRule] = PolicyEngine.defaultRules) {
        self.rules = rules
    }

    /// Runs every rule over the census and filters the union through R4:
    /// protected families can never be condemned, no matter what a rule says.
    public func evaluate(census: [ProcessSample], pressure: Pressure, configuration: GuardianConfiguration) -> [KillDecision] {
        let context = PolicyContext(census: census, pressure: pressure, configuration: configuration)
        let families = context.families
        return rules
            .flatMap { $0(context) }
            .filter { decision in
                !(families[decision.pid]?.isProtected ?? false)
            }
    }
}

// MARK: - The rules

extension PolicyEngine {

    public static let defaultRules: [PolicyRule] = [
        sourceControlHordeRule,
        orphanedMCPChildRule,
    ]

    /// R1: reap the source-control daemon accumulation.
    ///
    /// - No Xcode/xcodebuild alive → every daemon is residue: reap all.
    /// - Xcode alive → keep the newest N per user, reap the rest.
    /// - Any daemon older than `daemonMaxAgeSeconds` is a leak regardless.
    /// Daemons are read-only SCM helpers Xcode respawns on demand — killing
    /// them is recoverable and loses no data.
    public static let sourceControlHordeRule: PolicyRule = { context in
        let daemons = context.census.filter {
            $0.executableName == ProcessFamily.sourceControlDaemonName
        }
        guard !daemons.isEmpty else { return [] }

        guard context.xcodeAlive else {
            return daemons.map { daemon in
                KillDecision(
                    pid: daemon.pid,
                    executableName: daemon.executableName,
                    verdict: .sourceControlResidue(ageMinutes: Int(daemon.ageSeconds / 60)),
                    rssBytes: daemon.rssBytes
                )
            }
        }

        return Dictionary(grouping: daemons, by: \.user).flatMap { user, userDaemons in
            userDaemons
                .sorted { $0.ageSeconds < $1.ageSeconds }
                .enumerated()
                .compactMap { index, daemon in
                    if daemon.ageSeconds > context.configuration.daemonMaxAgeSeconds {
                        return KillDecision(
                            pid: daemon.pid,
                            executableName: daemon.executableName,
                            verdict: .sourceControlLeakAge(
                                hours: Int(daemon.ageSeconds / 3600),
                                maxHours: Int(context.configuration.daemonMaxAgeSeconds / 3600)
                            ),
                            rssBytes: daemon.rssBytes
                        )
                    }
                    guard index >= context.gates.daemonKeepPerUser else { return nil }
                    return KillDecision(
                        pid: daemon.pid,
                        executableName: daemon.executableName,
                        verdict: .sourceControlOverCap(
                            user: user,
                            rank: index + 1,
                            cap: context.gates.daemonKeepPerUser
                        ),
                        rssBytes: daemon.rssBytes
                    )
                }
        }
    }

    /// R2: reap MCP stdio children whose session is gone.
    ///
    /// A node process classified `.mcpChild` is reaped when its parent is
    /// absent from the census (orphaned to launchd) and it has aged past the
    /// grace window — but never when its parent chain reaches a live agent
    /// host: killing that child would break a live session's tools.
    public static let orphanedMCPChildRule: PolicyRule = { context in
        let families = context.families
        return context.census.compactMap { sample in
            guard case .mcpChild = families[sample.pid] else { return nil }
            guard !context.reachesAgentHost(sample) else { return nil }
            guard !context.livePIDs.contains(sample.ppid) else { return nil }
            guard sample.ageSeconds >= context.gates.mcpMaxAgeSeconds else { return nil }

            return KillDecision(
                pid: sample.pid,
                executableName: sample.executableName,
                verdict: .orphanedMCP(
                    parentPID: sample.ppid,
                    ageHours: Int(sample.ageSeconds / 3600)
                ),
                rssBytes: sample.rssBytes
            )
        }
    }
}
