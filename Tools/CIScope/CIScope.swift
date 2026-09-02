// CIScope — Swift replacement for the ci.yml inline bash scope script.
// Determines which CI lanes run from the changed files in this checkout.
//
// Usage: ciscope [--base-ref <git-ref>] [--event <pull_request|push|workflow_dispatch>]
// Emits GitHub Actions `key=value` lines to stdout (append to $GITHUB_OUTPUT).
// Changed-file trace goes to stderr.
//
// Behavior mirrors the retired bash case-statement exactly (two-dot diff,
// HEAD^1 base on PRs, root-commit fallback, same pattern → lane mapping).

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

func git(_ args: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return nil }
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
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
    return git(["rev-list", "--max-parents=0", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD^"
}

/// Bash case globs treat `*` as matching `/` too, so prefix matching is equivalent.
func matches(_ file: String, _ prefix: String, exact: [String] = []) -> Bool {
    file.hasPrefix(prefix) || exact.contains(file)
}

/// A (glob → lanes) rule from the retired bash script.
struct Rule {
    let prefix: String
    let exact: [String]
    let apply: (inout Scope) -> Void
}

// Case 1 — lane flags.
let laneRules: [Rule] = [
    Rule(prefix: "\0none", exact: [".github/workflows/ci.yml"]) {
        $0.runRoot = true; $0.runRootE2E = true; $0.runMemoryKit = true
        $0.runMemoryKitLiveE2E = true; $0.runAnima = true
        $0.runGuardian = true; $0.runOrchestrator = true
    },
    Rule(prefix: "\0none", exact: ["Package.swift", "Package.resolved"]) { $0.runRoot = true },
    Rule(prefix: "Sources/", exact: []) { $0.runRoot = true },
    Rule(prefix: "Tests/", exact: []) { $0.runRoot = true },
    Rule(prefix: "Packages/MemoryKit/", exact: [
        "Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved",
    ]) { $0.runRoot = true; $0.runMemoryKit = true },
    Rule(prefix: "Packages/Anima/", exact: [
        "Packages/Anima/Package.swift", "Packages/Anima/Package.resolved",
    ]) { $0.runAnima = true },
    Rule(prefix: "Packages/AndromedaMCP/", exact: [
        "Packages/AndromedaMCP/Package.swift", "Packages/AndromedaMCP/Package.resolved",
    ]) { $0.runAndromedaMCP = true },
    Rule(prefix: "Packages/AndromedaPowerKit/", exact: []) { $0.runPowerKit = true },
    Rule(prefix: "Packages/AndromedaStatusline/", exact: [
        "Packages/AndromedaStatusline/Package.swift", "Packages/AndromedaStatusline/Package.resolved",
    ]) { $0.runStatusline = true },
    Rule(prefix: "Packages/AndromedaUI/", exact: [
        "Packages/AndromedaUI/Package.swift", "Packages/AndromedaUI/Package.resolved",
    ]) { $0.runAndromedaUI = true },
    Rule(prefix: "Packages/AndromedaGuardian/", exact: [
        "Packages/AndromedaGuardian/Package.swift", "Packages/AndromedaGuardian/Package.resolved",
    ]) { $0.runGuardian = true },
    Rule(prefix: "Packages/AndromedaOrchestrator/", exact: [
        "Packages/AndromedaOrchestrator/Package.swift", "Packages/AndromedaOrchestrator/Package.resolved",
    ]) { $0.runOrchestrator = true },
]

// Case 2 — root E2E.
let rootE2ERule = Rule(prefix: "\0none", exact: [
    ".github/workflows/ci.yml", "Package.swift", "Package.resolved",
    "Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved",
]) { scope in
    let e2ePrefixes = [
        "Packages/MemoryKit/Sources/", "Packages/MemoryKit/Tests/",
        "Sources/AndromedaMemory/", "Sources/AndromedaProjections/",
        "Tests/AndromedaProjectionTests/", "Sources/AndromedaHUDCore/",
        "Sources/AndromedaHomeCore/", "Tests/AndromedaHUDTests/", "Tests/AndromedaHomeTests/",
    ]
    // handled by caller via prefix list
    scope.runRootE2E = scope.runRootE2E // placeholder, real logic below
}

// Case 3 — MemoryKit live E2E.
let memoryKitLiveE2EPrefixes = ["Packages/MemoryKit/Sources/", "Packages/MemoryKit/Tests/"]
let memoryKitLiveE2EExact = [
    ".github/workflows/ci.yml", "Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved",
]
let rootE2EPrefixes = [
    "Packages/MemoryKit/Sources/", "Packages/MemoryKit/Tests/",
    "Sources/AndromedaMemory/", "Sources/AndromedaProjections/",
    "Tests/AndromedaProjectionTests/", "Sources/AndromedaHUDCore/",
    "Sources/AndromedaHomeCore/", "Tests/AndromedaHUDTests/", "Tests/AndromedaHomeTests/",
]
let rootE2EExact = [
    ".github/workflows/ci.yml", "Package.swift", "Package.resolved",
    "Packages/MemoryKit/Package.swift", "Packages/MemoryKit/Package.resolved",
]

func classify(_ file: String, _ scope: inout Scope) {
    for rule in laneRules where matches(file, rule.prefix, exact: rule.exact) {
        rule.apply(&scope)
    }
    if rootE2EExact.contains(file) || rootE2EPrefixes.contains(where: file.hasPrefix) {
        scope.runRootE2E = true
    }
    if memoryKitLiveE2EExact.contains(file) || memoryKitLiveE2EPrefixes.contains(where: file.hasPrefix) {
        scope.runMemoryKitLiveE2E = true
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

if let out = git(["diff", "--name-only", baseRef, "HEAD"]) {
    for file in out.split(separator: "\n").map(String.init) where !file.isEmpty {
        FileHandle.standardError.write("changed: \(file)\n".data(using: .utf8)!)
        classify(file, &scope)
    }
} else {
    FileHandle.standardError.write("ciscope: git diff failed for base \(baseRef)\n".data(using: .utf8)!)
    exit(1)
}

var out = ""
func emit(_ key: String, _ value: Bool) { out += "\(key)=\(value)\n" }
emit("run_root", scope.runRoot)
emit("run_root_e2e", scope.runRootE2E)
emit("run_memorykit", scope.runMemoryKit)
emit("run_memorykit_live_e2e", scope.runMemoryKitLiveE2E)
emit("run_anima", scope.runAnima)
emit("run_andromeda_mcp", scope.runAndromedaMCP)
emit("run_powerkit", scope.runPowerKit)
emit("run_statusline", scope.runStatusline)
emit("run_andromeda_ui", scope.runAndromedaUI)
emit("run_guardian", scope.runGuardian)
emit("run_orchestrator", scope.runOrchestrator)
emit("needs_qdrant", scope.needsQdrant)
emit("any_lane", scope.anyLane)
FileHandle.standardOutput.write(out.data(using: .utf8)!)
