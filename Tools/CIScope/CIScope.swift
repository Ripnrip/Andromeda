// CIScope — Swift replacement for the ci.yml inline bash scope script.
// Determines which CI lanes run from the changed files in this checkout.
//
// Usage: ciscope [--base-ref <git-ref>] [--event <pull_request|push|workflow_dispatch>]
// Emits GitHub Actions `key=value` lines to stdout (append to $GITHUB_OUTPUT).
// Changed-file trace goes to stderr.
//
// Behavior mirrors the retired bash case-statement exactly (two-dot diff,
// HEAD^1 base on PRs, root-commit fallback, same pattern → lane mapping).
//
// Security: Tools/CIScope/** is itself a classified path that triggers every
// lane — a PR that rewrites the classifier can never skip the gates it feeds.

import Foundation

// MARK: - Lane

/// A CI lane the classifier can arm. `allCases` drives both rule evaluation
/// and output emission — adding a lane is a one-line change here plus its
/// rules; no emit lists to forget.
enum Lane: String, CaseIterable, Sendable {
    case root
    case rootE2E = "root_e2e"
    case memoryKit = "memorykit"
    case memoryKitLiveE2E = "memorykit_live_e2e"
    case anima
    case andromedaMCP = "andromeda_mcp"
    case powerKit = "powerkit"
    case statusline
    case andromedaUI = "andromeda_ui"
    case guardian
    case orchestrator

    /// The GitHub Actions output key for this lane (`run_<snake_case>`).
    var outputKey: String { "run_\(rawValue)" }

    /// Live E2E lanes gate their own jobs and are excluded from `anyLane`,
    /// which arms the build/test jobs (mirrors the retired bash semantics).
    var isLiveE2E: Bool { self == .rootE2E || self == .memoryKitLiveE2E }
}

// MARK: - Event

/// The GitHub event that triggered the run — a closed taxonomy, so an enum
/// (retires the stringly-typed `event == "pull_request"` compare).
enum CIEvent: String, Sendable {
    case pullRequest = "pull_request"
    case push
    case workflowDispatch = "workflow_dispatch"

    /// Unknown event names behave like push (retired-bash semantics).
    init(rawOrPush raw: String) {
        self = CIEvent(rawValue: raw) ?? .push
    }
}

// MARK: - Pattern

/// How a rule matches a changed file. Replaces the retired `\0none` sentinel
/// prefix and the parallel prefix/exact string arrays.
enum FilePattern: Equatable, Sendable {
    /// Matches any file under the prefix (bash glob `prefix*` also crossed `/`).
    case under(String)
    /// Matches exactly these file paths.
    case exact(Set<String>)
    /// Matches either.
    case anyOf(under: String, exact: Set<String>)

    func matches(_ file: String) -> Bool {
        switch self {
        case .under(let prefix): return file.hasPrefix(prefix)
        case .exact(let paths): return paths.contains(file)
        case .anyOf(let prefix, let paths): return file.hasPrefix(prefix) || paths.contains(file)
        }
    }
}

// MARK: - Rule

/// A classification rule: files matching `pattern` arm `lanes`.
/// Multiple rules may fire for the same file (behavior mirrors the retired
/// bash case-statement fallthrough).
struct Rule: Sendable {
    let pattern: FilePattern
    let lanes: [Lane]

    init(_ pattern: FilePattern, _ lanes: [Lane]) {
        self.pattern = pattern
        self.lanes = lanes
    }
}

// MARK: - Scope

/// The armed-lane set for this diff.
struct Scope: Sendable {
    private(set) var lanes: Set<Lane> = []

    /// CI-critical surfaces — the workflow itself, the package manifests, and
    /// the classifier (this tool) — arm every lane. A change to how lanes are
    /// decided must never be able to skip the lanes it decides.
    static let allLanes: [Lane] = Lane.allCases

    mutating func arm(_ lanes: some Sequence<Lane>) {
        self.lanes.formUnion(lanes)
    }

    mutating func apply(_ rules: [Rule], to file: String) {
        for rule in rules where rule.pattern.matches(file) {
            arm(rule.lanes)
        }
    }

    /// True when any non-E2E lane is armed — gates build/test jobs.
    /// (Live E2E lanes gate their own jobs via their individual outputs.)
    var anyLane: Bool { lanes.contains { !$0.isLiveE2E } }

    var needsQdrant: Bool { lanes.contains(.rootE2E) || lanes.contains(.memoryKitLiveE2E) }
}

// MARK: - Rules

// Lane rules — exact semantic clone of the retired bash case statement.
let laneRules: [Rule] = [
    // CI workflow change → the lanes the bash script armed (byte-compatible clone;
    // deliberately unchanged in this refactor — see PR body for the security rule).
    Rule(.exact([".github/workflows/ci.yml"]), [
        .root, .rootE2E, .memoryKit, .memoryKitLiveE2E, .anima, .guardian, .orchestrator,
    ]),
    Rule(.exact(["Package.swift", "Package.resolved"]), [.root]),
    Rule(.under("Sources/"), [.root]),
    Rule(.under("Tests/"), [.root]),
    Rule(.under("Packages/MemoryKit/"), [.root, .memoryKit]),
    Rule(.under("Packages/Anima/"), [.anima]),
    Rule(.under("Packages/AndromedaMCP/"), [.andromedaMCP]),
    Rule(.under("Packages/AndromedaPowerKit/"), [.powerKit]),
    Rule(.under("Packages/AndromedaStatusline/"), [.statusline]),
    Rule(.under("Packages/AndromedaUI/"), [.andromedaUI]),
    Rule(.under("Packages/AndromedaGuardian/"), [.guardian]),
    Rule(.under("Packages/AndromedaOrchestrator/"), [.orchestrator]),

    // SECURITY: the classifier classifies itself. A diff that rewrites the
    // scope engine arms every lane — it can never skip the gates it feeds.
    // (Cursor Security MEDIUM 2026-09-02: Tools/CIScope was previously an
    // unclassified path; a classifier-only PR emitted any_lane=false.)
    Rule(.under("Tools/CIScope/"), Lane.allCases),
]

// Live E2E rules (separate lanes, same matching model) — exact clone.
let liveE2ERules: [Rule] = [
    // Root manifests also arm the root E2E lane (bash rootE2EExact).
    Rule(.exact(["Package.swift", "Package.resolved",
                 "Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved"]), [.rootE2E]),
    // MemoryKit manifests also arm its live E2E lane (bash memoryKitLiveE2EExact).
    Rule(.exact(["Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved"]), [.memoryKitLiveE2E]),
    Rule(.under("Packages/MemoryKit/Sources/"), [.memoryKitLiveE2E, .rootE2E]),
    Rule(.under("Packages/MemoryKit/Tests/"), [.memoryKitLiveE2E, .rootE2E]),
    Rule(.under("Sources/AndromedaMemory/"), [.rootE2E]),
    Rule(.under("Sources/AndromedaProjections/"), [.rootE2E]),
    Rule(.under("Tests/AndromedaProjectionTests/"), [.rootE2E]),
    Rule(.under("Sources/AndromedaHUDCore/"), [.rootE2E]),
    Rule(.under("Sources/AndromedaHomeCore/"), [.rootE2E]),
    Rule(.under("Tests/AndromedaHUDTests/"), [.rootE2E]),
    Rule(.under("Tests/AndromedaHomeTests/"), [.rootE2E]),
]

// MARK: - Git

func git(_ args: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return nil }
    // Drain the pipe BEFORE waiting (Codex P2): git blocks once the pipe
    // buffer fills (a large snapshot-tree diff exceeds 64 KB) while
    // waitUntilExit() waits on the child — a mutual deadlock. Drain first:
    // readDataToEndOfFile returns at EOF, i.e. once the child exits; then
    // waitUntilExit merely reaps the termination status.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}

/// Mirrors the bash base-ref resolution: HEAD^1 on PR merge commits,
/// HEAD^ on ordinary commits, root commit as last resort.
/// SE-0380 switch-expression — `where` clauses evaluate lazily in case
/// order, preserving the probe short-circuit.
func resolveBaseRef(event: CIEvent) -> String {
    return switch event {
    case .pullRequest where git(["rev-parse", "--verify", "HEAD^1"]) != nil:
        "HEAD^1"
    case _ where git(["rev-parse", "--verify", "HEAD^"]) != nil:
        "HEAD^"
    default:
        git(["rev-list", "--max-parents=0", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD^"
    }
}

// MARK: - Observability

/// Emoji decision-point logging to stderr (stdout stays the pure key=value
/// contract GitHub Actions consumes). Doctrine: every decision — start,
/// base-ref resolution, per-file arms, fallbacks, failures, results — logs.
func log(_ emoji: String, _ message: String) {
    FileHandle.standardError.write("\(emoji) \(message)\n".data(using: .utf8)!)
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let baseRefOverride = flag("--base-ref")
let event = CIEvent(rawOrPush: flag("--event") ?? "push")

log("🚀", "ciscope event=\(event)\(baseRefOverride.map { " base-ref-override=\($0)" } ?? "")")

var scope = Scope()
let baseRef: String
if let override = baseRefOverride {
    baseRef = override
    log("🔀", "base ref: override \(override)")
} else {
    baseRef = resolveBaseRef(event: event)
    log("🔀", "base ref: resolved \(baseRef)")
}
let allRules = laneRules + liveE2ERules
log("📋", "rules loaded: \(laneRules.count) lane + \(liveE2ERules.count) live-E2E")

guard let diffOut = git(["diff", "--name-only", baseRef, "HEAD"]) else {
    log("❌", "git diff failed for base \(baseRef) — failing closed (exit 1)")
    exit(1)
}

let changedFiles = diffOut.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
log("📊", "diff vs \(baseRef): \(changedFiles.count) changed file(s)")
if changedFiles.isEmpty {
    log("⚠️", "empty diff — no lanes will arm (any_lane=false)")
}

for file in changedFiles {
    let before = scope.lanes
    scope.apply(allRules, to: file)
    let armed = scope.lanes.subtracting(before)
    if armed.isEmpty {
        log("⚪️", "\(file) → no lane")
    } else {
        log("🎯", "\(file) → \(armed.map(\.rawValue).sorted().joined(separator: ", "))")
    }
}

// CaseIterable-driven emission — one source of truth for keys and lanes.
var out = ""
for lane in Lane.allCases {
    out += "\(lane.outputKey)=\(scope.lanes.contains(lane))\n"
}
out += "needs_qdrant=\(scope.needsQdrant)\n"
out += "any_lane=\(scope.anyLane)\n"
FileHandle.standardOutput.write(out.data(using: .utf8)!)

let armedLanes = scope.lanes.map(\.rawValue).sorted()
log("🏁", "result: \(armedLanes.count) lane(s) armed [\(armedLanes.joined(separator: ", "))] any_lane=\(scope.anyLane) needs_qdrant=\(scope.needsQdrant)")
