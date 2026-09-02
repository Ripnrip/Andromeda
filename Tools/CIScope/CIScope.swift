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
// lane. Paired with ci.yml compiling the *base* parent's CIScope on
// pull_request (not the PR rewrite), a neutered classifier cannot skip gates.

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
    var isLiveE2E: Bool {
        switch self {
        case .rootE2E, .memoryKitLiveE2E: true
        case .root, .memoryKit, .anima, .andromedaMCP, .powerKit, .statusline,
            .andromedaUI, .guardian, .orchestrator:
            false
        }
    }
}

// MARK: - Derived outputs

/// Non-lane GITHUB_OUTPUT keys derived from the armed set.
/// CaseIterable so emission can't forget a derived flag the way the old
/// hand-written emit list could.
enum DerivedOutput: String, CaseIterable, Sendable {
    case needsQdrant = "needs_qdrant"
    case anyLane = "any_lane"

    func value(in scope: Scope) -> Bool {
        switch self {
        case .needsQdrant: scope.needsQdrant
        case .anyLane: scope.anyLane
        }
    }
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
///
/// Matching lives here — not as a free function, not as a `String` extension.
/// `FilePattern` owns the closed algebra of match strategies; `String` does not.
enum FilePattern: Equatable, Sendable {
    /// Matches any file under the prefix (bash glob `prefix*` also crossed `/`).
    case under(String)
    /// Matches exactly these file paths.
    case exact(Set<String>)
    /// Matches either.
    case anyOf(under: String, exact: Set<String>)

    func matches(_ file: String) -> Bool {
        switch self {
        case .under(let prefix): file.hasPrefix(prefix)
        case .exact(let paths): paths.contains(file)
        case .anyOf(let prefix, let paths): file.hasPrefix(prefix) || paths.contains(file)
        }
    }
}

// MARK: - Rule

/// A classification rule: files matching `pattern` arm `lanes`.
/// Multiple rules may fire for the same file (behavior mirrors the retired
/// bash case-statement fallthrough).
///
/// Deliberately a *struct*, not a protocol. Rule is pure data (pattern + lanes);
/// matching polymorphism already lives on `FilePattern`'s associated values.
/// A protocol would buy existential/generic dispatch for a single closed shape
/// with no second implementation. If rule *kinds* appear later, upgrade to an
/// enum-with-associated-values (same doctrine as FilePattern) — not a protocol.
struct Rule: Equatable, Sendable {
    let pattern: FilePattern
    let lanes: [Lane]

    init(_ pattern: FilePattern, _ lanes: [Lane]) {
        self.pattern = pattern
        self.lanes = lanes
    }
}

// MARK: - Scope

/// The armed-lane set for this diff.
///
/// Deliberately a *struct* wrapping `Set<Lane>`, not an enum. Scope is an
/// aggregate that accumulates an arbitrary subset of lanes (up to 2^N states).
/// Enums model mutually exclusive sum types; this is a set. `Lane` itself is
/// the enum — Scope is the bag of armed ones.
struct Scope: Sendable {
    private(set) var lanes: Set<Lane> = []

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

    var needsQdrant: Bool {
        lanes.contains(.rootE2E) || lanes.contains(.memoryKitLiveE2E)
    }
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
    // Runs from the *trusted* base-parent binary (ci.yml HEAD^1 compile), so
    // a PR that deletes this rule still gets classified by the base copy.
    // (Cursor Security MEDIUM 2026-09-02 + Manus trust review.)
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

/// Candidate base refs the probe chain may return.
enum BaseRef: String, Sendable {
    case mergeParent = "HEAD^1"
    case parent = "HEAD^"
}

/// Mirrors the bash base-ref resolution: HEAD^1 on PR merge commits,
/// HEAD^ on ordinary commits, root commit as last resort.
///
/// SE-0380 `return switch` verified: yes, Swift 5.9+. `where` clauses evaluate
/// lazily in case order, so the git probes keep their short-circuit (a
/// switch-on-tuple would eager-evaluate every probe — don't do that).
func resolveBaseRef(event: CIEvent) -> String {
    return switch event {
    case .pullRequest where git(["rev-parse", "--verify", BaseRef.mergeParent.rawValue]) != nil:
        BaseRef.mergeParent.rawValue
    case _ where git(["rev-parse", "--verify", BaseRef.parent.rawValue]) != nil:
        BaseRef.parent.rawValue
    default:
        git(["rev-list", "--max-parents=0", "HEAD"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? BaseRef.parent.rawValue
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

log(
    "🚀",
    "ciscope event=\(event.rawValue)\(baseRefOverride.map { " base-ref-override=\($0)" } ?? "")")

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

// CaseIterable-driven emission — lanes + derived flags, one source of truth.
var out = ""
for lane in Lane.allCases {
    out += "\(lane.outputKey)=\(scope.lanes.contains(lane))\n"
}
for derived in DerivedOutput.allCases {
    out += "\(derived.rawValue)=\(derived.value(in: scope))\n"
}
FileHandle.standardOutput.write(out.data(using: .utf8)!)

let armedLanes = scope.lanes.map(\.rawValue).sorted()
log("🏁", "result: \(armedLanes.count) lane(s) armed [\(armedLanes.joined(separator: ", "))] any_lane=\(scope.anyLane) needs_qdrant=\(scope.needsQdrant)")
