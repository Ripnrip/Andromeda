/**
 * 🎭 The MCPServerRegistry - The Sprawl Spotlight
 *
 * "We seed the known playbill from Cursor / Claude / Codex / Hermes,
 * then ask a polite process enumerator what is actually on stage —
 * grouping fifteen filesystem twins under one duplicate badge,
 * never swinging a kill wand in the rehearsal room."
 *
 * - The Cosmic Process Orchestrator of Andromeda Observe
 */

import Foundation

// MARK: - Process enumerator (injectable)

/// 🌟 Injectable live inventory — production wraps `ps`/`pgrep`; tests supply fixtures.
/// Contract: observe only. Never kill, signal, or unload processes.
public protocol MCPProcessEnumerating: Sendable {
    /// Return live MCP-related process rows (may be empty).
    func listMCPProcesses() -> [MCPProcessSnapshot]
}

/// 🌙 Default enumerator that refuses live `ps` — keeps unit tests hermetic.
public struct NullMCPProcessEnumerator: MCPProcessEnumerating {
    public init() {}

    public func listMCPProcesses() -> [MCPProcessSnapshot] {
        []
    }
}

/// 🧪 In-memory fixture for Swift Testing — sprawl without bloodshed.
public struct MockMCPProcessEnumerator: MCPProcessEnumerating {
    private let processes: [MCPProcessSnapshot]

    public init(processes: [MCPProcessSnapshot] = []) {
        self.processes = processes
    }

    public func listMCPProcesses() -> [MCPProcessSnapshot] {
        processes
    }
}

/// 👁️ Production-flavored enumerator that shells out to `ps` (read-only).
/// Not used in unit tests — wire at the Andromeda console boundary.
public struct ShellMCPProcessEnumerator: MCPProcessEnumerating {
    public init() {}

    public func listMCPProcesses() -> [MCPProcessSnapshot] {
        // 🌙 Gentle `ps` peek — never `kill`, never `pkill`.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,rss=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Self.parsePSOutput(text)
    }

    /// 🎨 Parse `ps -axo pid=,rss=,command=` into MCP-looking rows.
    public static func parsePSOutput(_ text: String) -> [MCPProcessSnapshot] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
            guard parts.count >= 3,
                  let pid = Int(parts[0]),
                  let rssKB = Double(parts[1]) else { return nil }
            let command = String(parts[2])
            guard looksLikeMCP(command) else { return nil }
            return MCPProcessSnapshot(pid: pid, command: command, memoryMB: rssKB / 1024.0)
        }
    }

    /// 🔍 Heuristic filter for MCP-related argv.
    public static func looksLikeMCP(_ command: String) -> Bool {
        let lowered = command.lowercased()
        let needles = [
            "npm exec",
            "npx ",
            "@modelcontextprotocol/",
            "mcp-server-",
            "firecrawl-mcp",
            "chrome-devtools-mcp",
            "claude-mem",
            "qdrant-mcp",
            "pageindex",
            "browsermcp",
            "mcp-server-time",
            "ios-simulator-mcp",
            "openai-websearch-mcp",
            "xcodebuildmcp",
            "@magicuidesign/mcp",
            "@remotion/mcp",
            "@supabase/mcp",
            "@playwright/mcp",
        ]
        return needles.contains { lowered.contains($0) }
    }
}

// MARK: - Scan result

/// 🌟 Crystallized output of `infra.mcp.scan` — roster + sprawl summary.
public struct MCPRegistryScanResult: Sendable, Equatable {
    public let entities: [MCPServerEntity]
    public let processCount: Int
    public let duplicateGroups: [String: Int]
    public let scannedAt: Date

    public init(
        entities: [MCPServerEntity],
        processCount: Int,
        duplicateGroups: [String: Int],
        scannedAt: Date = Date()
    ) {
        self.entities = entities
        self.processCount = processCount
        self.duplicateGroups = duplicateGroups
        self.scannedAt = scannedAt
    }

    /// 🌊 Groups with more than one live instance (the filesystem ×15 problem).
    public var sprawlGroups: [String: Int] {
        duplicateGroups.filter { $0.value > 1 }
    }
}

// MARK: - Registry

/**
 * 🎭 MCPServerRegistry — seed known configs + merge live inventory,
 * group duplicates, emit telemetry. Observe-only; no process killing.
 *
 * Client capabilities: `infra.mcp.list` / `infra.mcp.scan`.
 */
public struct MCPServerRegistry: Sendable {
    private let enumerator: any MCPProcessEnumerating
    private let telemetry: MCPTelemetryEmitting
    private var roster: [MCPServerEntity]
    private var lastScan: MCPRegistryScanResult?

    /// 🌟 The Grand Ignition — catalog seeds + injectable enumerator + telemetry.
    public init(
        enumerator: any MCPProcessEnumerating = NullMCPProcessEnumerator(),
        telemetry: MCPTelemetryEmitting = MCPTelemetry.shared,
        entities: [MCPServerEntity]? = nil
    ) {
        self.enumerator = enumerator
        self.telemetry = telemetry
        self.roster = entities ?? Self.catalogSeeds()
    }

    // MARK: Catalog seeds (config inventory)

    /// 📜 Known configured MCP packages from MCP-SPRAWL-PROBLEM.md host inventory.
    /// Config-only — `isLive` false until a scan attaches processes.
    public static func catalogSeeds() -> [MCPServerEntity] {
        let cursorPackages: [(String, String)] = [
            ("filesystem", "@modelcontextprotocol/server-filesystem"),
            ("memory", "@modelcontextprotocol/server-memory"),
            ("sequentialthinking", "@modelcontextprotocol/server-sequential-thinking"),
            ("firecrawl", "firecrawl-mcp"),
            ("browsermcp", "@browsermcp/mcp"),
            ("supabase", "@supabase/mcp-server-supabase"),
            ("vercel", "vercel"),
            ("postgresql", "postgresql"),
            ("openai-websearch", "openai-websearch-mcp"),
            ("ios-simulator", "ios-simulator-mcp"),
            ("time", "mcp-server-time"),
            ("youtube", "@anaisbetts/mcp-installer"),
            ("openaiDeveloperDocs", "openaiDeveloperDocs"),
            ("remotion-documentation", "@remotion/mcp"),
            ("magicuidesign-mcp", "@magicuidesign/mcp"),
            ("enhanced-quake-coding-arena", "enhanced-quake-coding-arena"),
            ("multica", "multica-habitat-mcp"),
            ("linear", "linear-mcp"),
        ]

        var seeds: [MCPServerEntity] = cursorPackages.map { key, package in
            MCPServerEntity(
                id: "mcp.cursor.\(key)",
                packageName: package,
                command: "config://cursor/\(key)",
                duplicateGroup: MCPPackageNormalizer.duplicateGroup(forPackage: package),
                source: .cursor,
                liveInstanceCount: 0,
                isLive: false
            )
        }

        let claudePackages = [
            "filesystem", "memory", "sequentialthinking", "browsermcp",
            "pageindex-local", "qdrant", "openaiDeveloperDocs",
            "multica", "linear",
        ]
        seeds += claudePackages.map { key in
            let package = seedPackageName(for: key)
            return MCPServerEntity(
                id: "mcp.claude.\(key)",
                packageName: package,
                command: "config://claude/\(key)",
                duplicateGroup: MCPPackageNormalizer.duplicateGroup(forPackage: package),
                source: .claude,
                liveInstanceCount: 0,
                isLive: false
            )
        }

        let codexPackages = [
            "chrome-devtools", "firecrawl", "playwright", "filesystem", "memory",
            "sequentialthinking", "qdrant", "browsermcp", "pageindex-local",
            "multica", "linear",
        ]
        seeds += codexPackages.map { key in
            let package = seedPackageName(for: key)
            return MCPServerEntity(
                id: "mcp.codex.\(key)",
                packageName: package,
                command: "config://codex/\(key)",
                duplicateGroup: MCPPackageNormalizer.duplicateGroup(forPackage: package),
                source: .codex,
                liveInstanceCount: 0,
                isLive: false
            )
        }

        let hermesPackages = [
            "higgsfield", "agent-zero", "gbrain", "mempalace", "obsidian", "wiki",
        ]
        seeds += hermesPackages.map { key in
            MCPServerEntity(
                id: "mcp.hermes.\(key)",
                packageName: key,
                command: "config://hermes/\(key)",
                duplicateGroup: key.lowercased(),
                source: .hermes,
                liveInstanceCount: 0,
                isLive: false
            )
        }

        return seeds
    }

    private static func seedPackageName(for key: String) -> String {
        switch key {
        case "filesystem": return "@modelcontextprotocol/server-filesystem"
        case "memory": return "@modelcontextprotocol/server-memory"
        case "sequentialthinking": return "@modelcontextprotocol/server-sequential-thinking"
        case "firecrawl": return "firecrawl-mcp"
        case "browsermcp": return "@browsermcp/mcp"
        case "chrome-devtools": return "chrome-devtools-mcp"
        case "playwright": return "@playwright/mcp"
        case "qdrant": return "qdrant-mcp-server"
        case "pageindex-local": return "pageindex-mcp-server"
        case "multica": return "multica-habitat-mcp"
        case "linear": return "linear-mcp"
        default: return key
        }
    }

    // MARK: Query — `infra.mcp.list`

    /// 📜 Current roster (seeds and/or last scan merge). Capability: `infra.mcp.list`.
    public func list() -> [MCPServerEntity] {
        roster
    }

    /// 🔍 Lookup by stable id.
    public func entity(id: String) -> MCPServerEntity? {
        roster.first { $0.id == id }
    }

    /// 🌊 Entities that currently show duplicate sprawl.
    public func duplicateEntities() -> [MCPServerEntity] {
        roster.filter(\.isDuplicate)
    }

    /// 💎 Last scan summary if any.
    public func lastScanResult() -> MCPRegistryScanResult? {
        lastScan
    }

    // MARK: Scan — `infra.mcp.scan`

    /**
     * 👁️ Merge live process inventory into the roster and emit telemetry.
     *
     * - Groups by `duplicateGroup` (filesystem ×15 → one badge).
     * - Never kills processes.
     * - Emits `registry.scan`, `mcp.process_count`, and `mcp.duplicate_detected`.
     *
     * Capability: `infra.mcp.scan`.
     */
    public mutating func scan(now: Date = Date()) -> MCPRegistryScanResult {
        let live = enumerator.listMCPProcesses()
        let grouped = Dictionary(grouping: live) { snapshot in
            MCPPackageNormalizer.duplicateGroup(
                forPackage: MCPPackageNormalizer.packageName(fromCommand: snapshot.command)
            )
        }

        var counts: [String: Int] = [:]
        for (group, snaps) in grouped {
            counts[group] = snaps.count
        }

        // Build live entities (one representative row per process for visibility).
        var liveEntities: [MCPServerEntity] = []
        for (group, snaps) in grouped {
            let count = snaps.count
            for snap in snaps {
                let package = MCPPackageNormalizer.packageName(fromCommand: snap.command)
                let source = MCPPackageNormalizer.inferredSource(fromCommand: snap.command)
                liveEntities.append(
                    MCPServerEntity(
                        id: "mcp.live.\(group).\(snap.pid)",
                        packageName: package,
                        command: snap.command,
                        pid: snap.pid,
                        memoryMB: snap.memoryMB,
                        duplicateGroup: group,
                        source: source,
                        liveInstanceCount: count,
                        isLive: true
                    )
                )
            }
        }

        // Annotate config seeds with live counts for the same duplicate group.
        // Seeds stay config-only (`isLive == false`); live process rows carry pids.
        let annotatedSeeds = Self.catalogSeeds().map { seed -> MCPServerEntity in
            var copy = seed
            copy.liveInstanceCount = counts[seed.duplicateGroup] ?? 0
            copy.isLive = false
            return copy
        }

        // Roster = annotated seeds + live rows (live rows carry pid detail).
        roster = annotatedSeeds + liveEntities
        let result = MCPRegistryScanResult(
            entities: roster,
            processCount: live.count,
            duplicateGroups: counts,
            scannedAt: now
        )
        lastScan = result

        emitTelemetry(for: result)
        return result
    }

    /// 🌟 Immutable scan returning an updated registry copy.
    public func scanning(now: Date = Date()) -> (MCPServerRegistry, MCPRegistryScanResult) {
        var copy = self
        let result = copy.scan(now: now)
        return (copy, result)
    }

    // MARK: Telemetry

    /// 📡 Fire structured events for the observability agent.
    private func emitTelemetry(for result: MCPRegistryScanResult) {
        telemetry.emit(
            .registryScan(
                processCount: result.processCount,
                uniqueGroups: result.duplicateGroups.count,
                sprawlGroups: result.sprawlGroups.count
            )
        )
        telemetry.emit(.processCount(result.processCount))
        for (group, count) in result.sprawlGroups.sorted(by: { $0.key < $1.key }) {
            telemetry.emit(.duplicateDetected(group: group, count: count))
        }
    }
}
