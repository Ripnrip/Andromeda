import Foundation
import OSLog

// MARK: - Domain
//
// The guardian's vocabulary. Every concept the policy reasons over is a
// typed value: process families are a rich enum, verdicts carry their own
// evidence as associated values, pressure is a transformation, not a flag.
// Nothing in this file touches a live process.

/// One process in a census snapshot.
public struct ProcessSample: Sendable, Equatable, Codable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var ppid: Int32
    public var user: String
    public var executablePath: String
    public var args: [String]
    /// When the process started — the stable identity anchor. PIDs are
    /// reused by macOS; (pid, startTime) is the revalidation key used before
    /// every signal so a condemned pid that exited and was recycled can
    /// never route a kill to an innocent replacement.
    public var startTime: Date
    /// Resident set size in bytes (best-effort; 0 when unknown).
    public var rssBytes: UInt64

    public init(
        pid: Int32, ppid: Int32, user: String, executablePath: String,
        args: [String], startTime: Date, rssBytes: UInt64,
        ageReference: Date = Date()
    ) {
        self.pid = pid
        self.ppid = ppid
        self.user = user
        self.executablePath = executablePath
        self.args = args
        self.startTime = startTime
        self.rssBytes = rssBytes
        self.ageSeconds = max(0, ageReference.timeIntervalSince(startTime))
    }

    /// Seconds since the process started (derived from `startTime`).
    public let ageSeconds: TimeInterval

    /// Basename of the executable path (no directories).
    public var executableName: String {
        URL(fileURLWithPath: executablePath).lastPathComponent
    }

    /// Executable path + args as one matchable command line.
    public var commandLine: String {
        ([executablePath] + args).joined(separator: " ")
    }

    /// True when `component` appears as an EXACT argv token or an exact path
    /// component of one ("/opt/…/xcodebuildmcp" components include
    /// "xcodebuildmcp"). Anchored matching — an unanchored substring scan of
    /// the command line lets an unrelated node workload with a marker in an
    /// env var, cwd, or similarly-named path ("my-claude-mem-notes/") be
    /// misclassified as an MCP child and killed.
    public func hasArgComponent(_ component: String) -> Bool {
        args.contains { arg in
            arg == component || arg.split(separator: "/").contains { $0 == component }
        }
    }
}

// MARK: - Process family

// MARK: - MCP markers

/// Known MCP server sprawl families. The enum IS the marker list — one
/// source of truth, `allCases` is the derived array, and adding a family is
/// adding a case (exhaustive switches downstream force the decision).
public enum MCPServerMarker: String, Sendable, Codable, CaseIterable {
    case filesystem = "mcp-server-filesystem"
    case memory = "mcp-server-memory"
    case sequentialThinking = "mcp-server-sequential-thinking"
    case xcodebuild = "xcodebuildmcp"
    case playwright = "playwright-mcp"
    case qdrant = "qdrant-mcp"
    case cerebras = "cerebras-mcp"
    case chromeDevTools = "chrome-devtools-mcp"
    case claudeMem = "claude-mem"
    case mcpServerCJS = "mcp-server.cjs"
}

// MARK: - Classification catalog

/// The naming catalog classification reads from. A VALUE, not a baked-in
/// global: `defaults` is the compile-time floor, and a remote/overlay
/// catalog can be injected through `GuardianConfiguration` — protection
/// lists can grow at runtime, never shrink below defaults (fail closed:
/// an overlay that fails to load leaves the default protection in place).
public struct ClassificationCatalog: Sendable, Equatable, Codable {
    /// Xcode's SourceControl helper — the R1 target.
    public var sourceControlDaemonName: String
    /// User applications the guardian must never signal, hung or not.
    public var neverTouchNames: Set<String>
    /// Agent hosts whose live descendants are protected.
    public var agentHostNames: Set<String>
    /// The executable that hosts MCP stdio children.
    public var mcpHostExecutable: String

    public init(
        sourceControlDaemonName: String = "com.apple.dt.Xcode.sourcecontrol.Git",
        neverTouchNames: Set<String> = [
            "CapCut", "Firefox", "ChatGPT", "Finder", "Simulator", "Obsidian",
            "Google Chrome", "Safari", "Terminal", "iTerm2", "Xcode",
        ],
        agentHostNames: Set<String> = [
            "Claude", "Claude Helper", "codex", "Cursor", "Trae", "claude.exe",
            "Claude Helper (Renderer)", "Letta", "Letta Helper", "Letta Helper (Renderer)",
        ],
        mcpHostExecutable: String = "node"
    ) {
        self.sourceControlDaemonName = sourceControlDaemonName
        self.neverTouchNames = neverTouchNames
        self.agentHostNames = agentHostNames
        self.mcpHostExecutable = mcpHostExecutable
    }

    /// Fail-closed merge: an overlay may ADD protection, never remove it.
    public func merged(with overlay: ClassificationCatalog) -> ClassificationCatalog {
        ClassificationCatalog(
            sourceControlDaemonName: overlay.sourceControlDaemonName,
            neverTouchNames: neverTouchNames.union(overlay.neverTouchNames),
            agentHostNames: agentHostNames.union(overlay.agentHostNames),
            mcpHostExecutable: overlay.mcpHostExecutable
        )
    }

    /// The compile-time floor.
    public static let defaults = ClassificationCatalog()
}

// MARK: - Process family

/// What a process IS to the guardian. Classification is pure naming — no
/// policy lives here, so rules can be exhaustive switches over family.
public enum ProcessFamily: Sendable, Equatable {
    /// Xcode's SourceControl helper — leaks in hordes (carries the owning user).
    case sourceControlDaemon(user: String)
    /// A node MCP stdio child (carries the marker that matched its command line).
    case mcpChild(marker: MCPServerMarker)
    /// An agent host (Claude.app, codex, Cursor, Trae, …) — protected subtree.
    case agentHost
    /// A user application — structural never-touch, regardless of rules.
    case userApplication
    /// Anything else — invisible to policy.
    case other

    /// Back-compat: the marker list as strings (derived, not maintained).
    public static var mcpArgMarkers: [String] { MCPServerMarker.allCases.map(\.rawValue) }

    /// Classify one sample into its family. Total — every process lands
    /// somewhere. A switch over precedence, not an `if` chain: each case
    /// names its branch and the compiler keeps the ladder honest.
    public static func classify(
        _ sample: ProcessSample,
        catalog: ClassificationCatalog = .defaults
    ) -> ProcessFamily {
        switch sample.executableName {
        case catalog.sourceControlDaemonName:
            return .sourceControlDaemon(user: sample.user)
        case _ where catalog.neverTouchNames.contains(sample.executableName):
            return .userApplication
        case _ where catalog.agentHostNames.contains(sample.executableName):
            return .agentHost
        case catalog.mcpHostExecutable:
            guard let marker = MCPServerMarker.allCases.first(where: { sample.hasArgComponent($0.rawValue) })
            else { return .other }
            return .mcpChild(marker: marker)
        default:
            return .other
        }
    }

    /// R4, as data: families the guardian may never signal.
    public var isProtected: Bool {
        switch self {
        case .userApplication, .agentHost: true
        case .sourceControlDaemon, .mcpChild, .other: false
        }
    }
}

// MARK: - Pressure

/// The gates a rule applies — the pressure-adjusted knobs in one value.
public struct EffectiveGates: Sendable, Equatable, Codable {
    public var daemonKeepPerUser: Int
    public var mcpMaxAgeSeconds: TimeInterval

    public init(daemonKeepPerUser: Int, mcpMaxAgeSeconds: TimeInterval) {
        self.daemonKeepPerUser = daemonKeepPerUser
        self.mcpMaxAgeSeconds = mcpMaxAgeSeconds
    }
}

/// Memory pressure as a typed transformation over configuration. The
/// elevated case carries its evidence (the swap bytes that tripped it) —
/// tests and telemetry assert on values, not strings.
public enum Pressure: Sendable, Equatable, Codable {
    case normal
    case elevated(swapBytes: UInt64)

    /// The gates this pressure level selects. R3 lives here, in one place.
    public func gates(configuration: GuardianConfiguration) -> EffectiveGates {
        switch self {
        case .normal:
            EffectiveGates(
                daemonKeepPerUser: configuration.daemonKeepPerUser,
                mcpMaxAgeSeconds: configuration.mcpMaxAgeSeconds
            )
        case .elevated:
            EffectiveGates(
                daemonKeepPerUser: configuration.escalatedDaemonKeepPerUser,
                mcpMaxAgeSeconds: configuration.escalatedMCPMaxAgeSeconds
            )
        }
    }
}

// MARK: - Configuration

/// Guardian knobs. Values only — no behavior.
public struct GuardianConfiguration: Sendable, Codable, Equatable {
    /// Daemons per user allowed to live while Xcode is running.
    public var daemonKeepPerUser: Int = 2
    /// Daemons older than this are leaks regardless of caps.
    public var daemonMaxAgeSeconds: TimeInterval = 6 * 3600
    /// MCP children older than this with a dead parent are reaped.
    public var mcpMaxAgeSeconds: TimeInterval = 4 * 3600
    /// Swap threshold at which pressure escalates.
    public var swapEscalationBytes: UInt64 = 24 * 1024 * 1024 * 1024

    /// Elevated-pressure tightening: cap drops to 1, MCP age to 1h.
    public var escalatedDaemonKeepPerUser: Int = 1
    public var escalatedMCPMaxAgeSeconds: TimeInterval = 3600

    /// The classification catalog — defaults + fail-closed overlay surface.
    /// Remote configuration merges here via `ClassificationCatalog.merged`
    /// (protections can grow at runtime; they can never shrink).
    public var catalog: ClassificationCatalog = .defaults

    public init() {}
}

// MARK: - Verdicts and decisions

/// WHY a process was condemned — the evidence, typed. `reason` is derived
/// exhaustively, so tests assert on values, never on strings.
public enum Verdict: Sendable, Equatable {
    /// R1: no Xcode alive — daemon is residue.
    case sourceControlResidue(ageMinutes: Int)
    /// R1: daemon exceeded the per-user cap.
    case sourceControlOverCap(user: String, rank: Int, cap: Int)
    /// R1: daemon is older than the leak horizon, cap or no cap.
    case sourceControlLeakAge(hours: Int, maxHours: Int)
    /// R2: MCP child orphaned and aged past grace.
    case orphanedMCP(parentPID: Int32, ageHours: Int)
    /// The rule family this verdict came from.
    public var rule: KillDecision.Rule {
        switch self {
        case .sourceControlResidue, .sourceControlOverCap, .sourceControlLeakAge:
            .sourceControlHorde
        case .orphanedMCP:
            .orphanedMCPChild
        }
    }

    /// Human-readable reason, derived — never the source of truth.
    public var reason: String {
        switch self {
        case .sourceControlResidue(let minutes):
            "no live Xcode/xcodebuild — daemon residue (age \(minutes)m)"
        case .sourceControlOverCap(let user, let rank, let cap):
            "cap \(cap)/user exceeded for \(user) (rank \(rank) by age)"
        case .sourceControlLeakAge(let hours, let maxHours):
            "leak age \(hours)h exceeds \(maxHours)h"
        case .orphanedMCP(let parentPID, let hours):
            "MCP child orphaned (ppid \(parentPID) dead) and aged \(hours)h"
        }
    }
}

/// A single reap verdict for one process.
public struct KillDecision: Sendable, Equatable, Codable {
    public enum Rule: String, Sendable, Codable {
        case sourceControlHorde
        case orphanedMCPChild
    }

    public var pid: Int32
    public var executableName: String
    public var rule: Rule
    public var reason: String
    /// RSS reclaimed if the kill lands (best-effort).
    public var rssBytes: UInt64
    /// The sampled process start time — revalidated immediately before every
    /// signal so a recycled PID can never route the kill to a replacement
    /// process (PID reuse is real; identity is (pid, startTime)).
    public var sampledStartTime: Date?
    /// For orphan verdicts: the parent whose death justified the reap.
    /// Revalidated at execution time — a parent that came back to life
    /// between census and signal vetoes the kill.
    public var parentPID: Int32?

    public init(
        pid: Int32, executableName: String, verdict: Verdict, rssBytes: UInt64,
        sampledStartTime: Date? = nil, parentPID: Int32? = nil
    ) {
        self.pid = pid
        self.executableName = executableName
        self.rule = verdict.rule
        self.reason = verdict.reason
        self.rssBytes = rssBytes
        self.sampledStartTime = sampledStartTime
        self.parentPID = parentPID
    }
}
