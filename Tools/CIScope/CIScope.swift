// CIScope — Swift replacement for the ci.yml inline bash scope script.
// Determines which CI lanes run from the changed files in this checkout.
//
// Usage: ciscope [--base-ref <git-ref>] [--event <pull_request|push|workflow_dispatch>]
// Emits GitHub Actions `key=value` lines to stdout (append to $GITHUB_OUTPUT).
// Changed-file trace goes to stderr.
//
// Behavior mirrors the retired bash case-statement exactly (two-dot diff,
// HEAD^1 base on PRs, root-commit fallback, same pattern → lane mapping),
// plus Tools/CIScope/ → all lanes (classifier changes must not skip gates).

import Foundation

struct Scope {
    var runRoot = false
    var runRootE2E = false
    var runMemoryKit = false
    var runMemoryKitLiveE2E = false
    var runAnima = false
    var runAndromedaMCP = false
    var runPowerKit = false
    var runStatusline = false
    var runAndromedaUI = false
    var runGuardian = false
    var runOrchestrator = false

    var needsQdrant: Bool { runRootE2E || runMemoryKitLiveE2E }

    var anyLane: Bool {
        runRoot || runMemoryKit || runAnima || runAndromedaMCP || runPowerKit
            || runStatusline || runAndromedaUI || runGuardian || runOrchestrator
    }
}

// MARK: - Repo layout (typed)

/// Repo-root paths — every literal path string lives exactly once, here.
enum RepoPath {
    static let ciWorkflow = ".github/workflows/ci.yml"
    static let rootManifest = "Package.swift"
    static let rootResolved = "Package.resolved"
    static let sources = "Sources/"
    static let tests = "Tests/"
    static let ciscopeTool = "Tools/CIScope/"
}

/// The nested SPM packages — the rawValue is the directory name; every
/// derived path (root / manifest / resolved / sources / tests) composes
/// from it. No rule spells a package path by hand.
enum Package: String, CaseIterable {
    case memoryKit = "MemoryKit"
    case anima = "Anima"
    case andromedaMCP = "AndromedaMCP"
    case powerKit = "AndromedaPowerKit"
    case statusline = "AndromedaStatusline"
    case andromedaUI = "AndromedaUI"
    case guardian = "AndromedaGuardian"
    case orchestrator = "AndromedaOrchestrator"

    /// `Packages/<dir>/`
    var root: String { "Packages/\(rawValue)/" }
    /// `Packages/<dir>/Package.swift`
    var manifest: String { root + "Package.swift" }
    /// `Packages/<dir>/Package.resolved`
    var resolved: String { root + "Package.resolved" }
    /// `Packages/<dir>/Sources/`
    var sources: String { root + "Sources/" }
    /// `Packages/<dir>/Tests/`
    var tests: String { root + "Tests/" }
}

/// Root-level Swift modules (outside the Packages tree) that the E2E rules
/// select — the rawValue is the module name; which tree it lives under is
/// declared per case, never inferred from string shape.
enum RootModule: String, CaseIterable {
    case andromedaMemory = "AndromedaMemory"
    case projections = "AndromedaProjections"
    case hudCore = "AndromedaHUDCore"
    case homeCore = "AndromedaHomeCore"
    case projectionTests = "AndromedaProjectionTests"
    case hudTests = "AndromedaHUDTests"
    case homeTests = "AndromedaHomeTests"

    /// `Sources/<module>/` or `Tests/<module>/` — exhaustive, compile-checked.
    var path: String {
        switch self {
        case .andromedaMemory, .projections, .hudCore, .homeCore:
            return RepoPath.sources + rawValue + "/"
        case .projectionTests, .hudTests, .homeTests:
            return RepoPath.tests + rawValue + "/"
        }
    }
}

/// Path matchers for lane / E2E classification (exact path or directory prefix).
enum PathMatcher {
    case exact(String)
    case prefix(String)

    func matches(_ file: String) -> Bool {
        switch self {
        case .exact(let path):
            return file == path
        case .prefix(let path):
            return file.hasPrefix(path)
        }
    }
}

/// Primary lane rules — exhaustive CaseIterable table replacing the bash globs.
enum LaneRule: CaseIterable {
    case workflowCI
    case ciScopeTool
    case rootPackage
    case sources
    case tests
    case memoryKit
    case anima
    case andromedaMCP
    case powerKit
    case statusline
    case andromedaUI
    case guardian
    case orchestrator

    var matchers: [PathMatcher] {
        switch self {
        case .workflowCI:
            return [.exact(RepoPath.ciWorkflow)]
        case .ciScopeTool:
            // Classifier lives outside product prefixes; a rewrite must not skip gates.
            return [.prefix(RepoPath.ciscopeTool)]
        case .rootPackage:
            return [.exact(RepoPath.rootManifest), .exact(RepoPath.rootResolved)]
        case .sources:
            return [.prefix(RepoPath.sources)]
        case .tests:
            return [.prefix(RepoPath.tests)]
        case .memoryKit:
            return [
                .prefix(Package.memoryKit.root),
                .exact(Package.memoryKit.manifest),
                .exact(Package.memoryKit.resolved),
            ]
        case .anima:
            return [
                .prefix(Package.anima.root),
                .exact(Package.anima.manifest),
                .exact(Package.anima.resolved),
            ]
        case .andromedaMCP:
            return [
                .prefix(Package.andromedaMCP.root),
                .exact(Package.andromedaMCP.manifest),
                .exact(Package.andromedaMCP.resolved),
            ]
        case .powerKit:
            return [.prefix(Package.powerKit.root)]
        case .statusline:
            return [
                .prefix(Package.statusline.root),
                .exact(Package.statusline.manifest),
                .exact(Package.statusline.resolved),
            ]
        case .andromedaUI:
            return [
                .prefix(Package.andromedaUI.root),
                .exact(Package.andromedaUI.manifest),
                .exact(Package.andromedaUI.resolved),
            ]
        case .guardian:
            return [
                .prefix(Package.guardian.root),
                .exact(Package.guardian.manifest),
                .exact(Package.guardian.resolved),
            ]
        case .orchestrator:
            return [
                .prefix(Package.orchestrator.root),
                .exact(Package.orchestrator.manifest),
                .exact(Package.orchestrator.resolved),
            ]
        }
    }

    func apply(to scope: inout Scope) {
        switch self {
        case .workflowCI, .ciScopeTool:
            scope.runRoot = true
            scope.runRootE2E = true
            scope.runMemoryKit = true
            scope.runMemoryKitLiveE2E = true
            scope.runAnima = true
            scope.runGuardian = true
            scope.runOrchestrator = true
        case .rootPackage, .sources, .tests:
            scope.runRoot = true
        case .memoryKit:
            scope.runRoot = true
            scope.runMemoryKit = true
        case .anima:
            scope.runAnima = true
        case .andromedaMCP:
            scope.runAndromedaMCP = true
        case .powerKit:
            scope.runPowerKit = true
        case .statusline:
            scope.runStatusline = true
        case .andromedaUI:
            scope.runAndromedaUI = true
        case .guardian:
            scope.runGuardian = true
        case .orchestrator:
            scope.runOrchestrator = true
        }
    }

    func matches(_ file: String) -> Bool {
        matchers.contains { $0.matches(file) }
    }
}

/// Overlay E2E triggers (Case 3 in the retired bash script).
enum E2ETrigger: CaseIterable {
    case rootE2E
    case memoryKitLiveE2E

    var matchers: [PathMatcher] {
        switch self {
        case .rootE2E:
            return [
                .exact(RepoPath.ciWorkflow),
                .exact(RepoPath.rootManifest),
                .exact(RepoPath.rootResolved),
                .exact(Package.memoryKit.manifest),
                .exact(Package.memoryKit.resolved),
                .prefix(Package.memoryKit.sources),
                .prefix(Package.memoryKit.tests),
                .prefix(RootModule.andromedaMemory.path),
                .prefix(RootModule.projections.path),
                .prefix(RootModule.projectionTests.path),
                .prefix(RootModule.hudCore.path),
                .prefix(RootModule.homeCore.path),
                .prefix(RootModule.hudTests.path),
                .prefix(RootModule.homeTests.path),
            ]
        case .memoryKitLiveE2E:
            return [
                .exact(RepoPath.ciWorkflow),
                .exact(Package.memoryKit.manifest),
                .exact(Package.memoryKit.resolved),
                .prefix(Package.memoryKit.sources),
                .prefix(Package.memoryKit.tests),
            ]
        }
    }

    func apply(to scope: inout Scope) {
        switch self {
        case .rootE2E:
            scope.runRootE2E = true
        case .memoryKitLiveE2E:
            scope.runMemoryKitLiveE2E = true
        }
    }

    func matches(_ file: String) -> Bool {
        matchers.contains { $0.matches(file) }
    }
}

/// GITHUB_OUTPUT keys — CaseIterable maps each key ↔ Scope field explicitly.
enum OutputKey: CaseIterable {
    case runRoot
    case runRootE2E
    case runMemoryKit
    case runMemoryKitLiveE2E
    case runAnima
    case runAndromedaMCP
    case runPowerKit
    case runStatusline
    case runAndromedaUI
    case runGuardian
    case runOrchestrator
    case needsQdrant
    case anyLane

    /// Stable contract string for `$GITHUB_OUTPUT` (exhaustive — no rawValue concat).
    var githubKey: String {
        switch self {
        case .runRoot: return "run_root"
        case .runRootE2E: return "run_root_e2e"
        case .runMemoryKit: return "run_memorykit"
        case .runMemoryKitLiveE2E: return "run_memorykit_live_e2e"
        case .runAnima: return "run_anima"
        case .runAndromedaMCP: return "run_andromeda_mcp"
        case .runPowerKit: return "run_powerkit"
        case .runStatusline: return "run_statusline"
        case .runAndromedaUI: return "run_andromeda_ui"
        case .runGuardian: return "run_guardian"
        case .runOrchestrator: return "run_orchestrator"
        case .needsQdrant: return "needs_qdrant"
        case .anyLane: return "any_lane"
        }
    }

    func value(in scope: Scope) -> Bool {
        switch self {
        case .runRoot: return scope.runRoot
        case .runRootE2E: return scope.runRootE2E
        case .runMemoryKit: return scope.runMemoryKit
        case .runMemoryKitLiveE2E: return scope.runMemoryKitLiveE2E
        case .runAnima: return scope.runAnima
        case .runAndromedaMCP: return scope.runAndromedaMCP
        case .runPowerKit: return scope.runPowerKit
        case .runStatusline: return scope.runStatusline
        case .runAndromedaUI: return scope.runAndromedaUI
        case .runGuardian: return scope.runGuardian
        case .runOrchestrator: return scope.runOrchestrator
        case .needsQdrant: return scope.needsQdrant
        case .anyLane: return scope.anyLane
        }
    }
}

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
func resolveBaseRef(event: String) -> String {
    if event == "pull_request", git(["rev-parse", "--verify", "HEAD^1"]) != nil {
        return "HEAD^1"
    }
    if git(["rev-parse", "--verify", "HEAD^"]) != nil {
        return "HEAD^"
    }
    let root = git(["rev-list", "--max-parents=0", "HEAD"])?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let root, !root.isEmpty else { return "HEAD^" }
    return root
}

func classify(_ file: String, _ scope: inout Scope) {
    for rule in LaneRule.allCases where rule.matches(file) {
        rule.apply(to: &scope)
    }
    for trigger in E2ETrigger.allCases where trigger.matches(file) {
        trigger.apply(to: &scope)
    }
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let baseRefOverride = flag("--base-ref")
let event = flag("--event") ?? "push"

var scope = Scope()
let baseRef = baseRefOverride ?? resolveBaseRef(event: event)

let diffOutput = git(["diff", "--name-only", baseRef, "HEAD"])
guard let diffOutput else {
    FileHandle.standardError.write(
        "ciscope: git diff failed for base \(baseRef)\n".data(using: .utf8)!)
    exit(1)
}

for file in diffOutput.split(separator: "\n").map(String.init) where !file.isEmpty {
    FileHandle.standardError.write("changed: \(file)\n".data(using: .utf8)!)
    classify(file, &scope)
}

var out = ""
for key in OutputKey.allCases {
    out += "\(key.githubKey)=\(key.value(in: scope))\n"
}
FileHandle.standardOutput.write(out.data(using: .utf8)!)
