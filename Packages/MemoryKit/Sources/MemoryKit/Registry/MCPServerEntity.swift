/**
 * 🎭 The MCPServerEntity - Visible MCP Process Citizen
 *
 * "No more silent npm exec twins lurking in Activity Monitor's wings —
 * each server steps forward with a name, a pid, a host source,
 * and a duplicate-group badge when the chorus sings fifteen times."
 *
 * - The Spellbinding Museum Director of MCP Observability
 */

import Foundation

// MARK: - Source host / tool

/// 🌟 Which agent host configured or spawned this MCP server.
/// Never expose tracker brands (Linear / Multica) — only runtime sources.
public enum MCPServerSource: String, Sendable, Codable, CaseIterable, Equatable {
    case cursor
    case claude
    case codex
    case hermes
    case gemini
    case pi
    case plugin
    case unknown

    /// 🎨 Short roster label for the console.
    public var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .hermes: return "Hermes"
        case .gemini: return "Gemini"
        case .pi: return "Pi"
        case .plugin: return "Plugin"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Live process snapshot

/// 🌟 One row from an injectable process enumerator (ps / pgrep / mock).
/// Tests supply fixtures — production never kills from this type.
public struct MCPProcessSnapshot: Sendable, Equatable, Codable {
    public let pid: Int
    public let command: String
    /// Resident set size in megabytes when known (Activity Monitor–style tax).
    public let memoryMB: Double?

    public init(pid: Int, command: String, memoryMB: Double? = nil) {
        self.pid = pid
        self.command = command
        self.memoryMB = memoryMB
    }
}

// MARK: - Entity

/**
 * 🎭 MCPServerEntity — one configured and/or live MCP server as a Swift citizen.
 *
 * Stable `id` + package + command + optional live pid/RSS + duplicate group + source.
 * Capability sketch (clients never see Linear/Multica): `infra.mcp.list` / `infra.mcp.scan`.
 */
public struct MCPServerEntity: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    /// npm / uv package or logical server key (e.g. `@modelcontextprotocol/server-filesystem`).
    public let packageName: String
    /// Raw command line or config command (e.g. `npm exec …`).
    public let command: String
    /// Live process id when observed; nil for config-only seeds.
    public var pid: Int?
    /// Approximate RSS in MB when observed.
    public var memoryMB: Double?
    /// Dedupe key — same package/normalized name collapses sprawl (filesystem ×15).
    public let duplicateGroup: String
    public let source: MCPServerSource
    /// How many live processes share this `duplicateGroup` after a scan (1 = unique).
    public var liveInstanceCount: Int
    /// True when this row came from a live process (vs config seed only).
    public var isLive: Bool

    public init(
        id: String,
        packageName: String,
        command: String,
        pid: Int? = nil,
        memoryMB: Double? = nil,
        duplicateGroup: String,
        source: MCPServerSource,
        liveInstanceCount: Int = 1,
        isLive: Bool = false
    ) {
        self.id = id
        self.packageName = packageName
        self.command = command
        self.pid = pid
        self.memoryMB = memoryMB
        self.duplicateGroup = duplicateGroup
        self.source = source
        self.liveInstanceCount = liveInstanceCount
        self.isLive = isLive
    }

    /// 🌊 Sprawl badge — more than one live twin in the same duplicate group.
    public var isDuplicate: Bool { liveInstanceCount > 1 }

    /// 🎨 Console badge copy (no tracker brand names).
    public var duplicateBadgeLabel: String? {
        guard isDuplicate else { return nil }
        return "×\(liveInstanceCount)"
    }
}

// MARK: - Capability IDs (client-facing; hide operator trackers)

/// 🌟 Stable capability identifiers for Andromeda clients / satellite agents.
public enum MCPCapabilityID: String, Sendable, Codable, CaseIterable {
    /// Read the current roster (seeds + last scan).
    case list = "infra.mcp.list"
    /// Re-scan live processes and emit telemetry.
    case scan = "infra.mcp.scan"
}

// MARK: - Package normalization

/// 🔮 Alchemy that turns noisy argv into a stable duplicate-group key.
public enum MCPPackageNormalizer: Sendable {
    /// ✨ Extract a package / server identity from an `npm exec` / node / python command.
    public static func packageName(fromCommand command: String) -> String {
        let lowered = command.lowercased()

        // npm exec / npx @scope/pkg[@version]
        if let match = firstMatch(
            in: command,
            pattern: #"@(?:modelcontextprotocol|[^/\s]+)/[A-Za-z0-9._-]+(?:@[^\s]+)?"#
        ) {
            return stripVersionSuffix(match)
        }

        // Unscoped npm packages commonly used as MCP servers
        let unscoped = [
            "firecrawl-mcp",
            "chrome-devtools-mcp",
            "ios-simulator-mcp",
            "openai-websearch-mcp",
            "xcodebuildmcp",
            "browsermcp",
        ]
        for name in unscoped where lowered.contains(name) {
            return name
        }

        // Child node binaries: mcp-server-filesystem
        if let match = firstMatch(in: command, pattern: #"mcp-server-[A-Za-z0-9._-]+"#) {
            return "@modelcontextprotocol/server-\(match.replacingOccurrences(of: "mcp-server-", with: ""))"
        }

        // Python / cjs alternate servers
        if lowered.contains("pageindex") { return "pageindex-mcp-server" }
        if lowered.contains("claude-mem") && lowered.contains("mcp-server") {
            return "claude-mem-mcp"
        }
        if lowered.contains("qdrant-mcp") || lowered.contains("qdrant_mcp") {
            return "qdrant-mcp-server"
        }
        if lowered.contains("mcp-server-time") { return "mcp-server-time" }

        // Fallback: last path component of the executable-ish token
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let npmIndex = tokens.firstIndex(where: { $0.hasSuffix("npm") || $0.hasSuffix("npx") }),
           npmIndex + 1 < tokens.count {
            let candidate = tokens[npmIndex + 1]
            if candidate != "exec" {
                return stripVersionSuffix(candidate)
            }
            if npmIndex + 2 < tokens.count {
                return stripVersionSuffix(tokens[npmIndex + 2])
            }
        }

        return tokens.last.map(stripVersionSuffix) ?? "unknown"
    }

    /// 🎭 Duplicate group is the package name without version pins.
    public static func duplicateGroup(forPackage packageName: String) -> String {
        stripVersionSuffix(packageName).lowercased()
    }

    /// 🎨 Guess source host from command heuristics when config seed is absent.
    public static func inferredSource(fromCommand command: String) -> MCPServerSource {
        let lowered = command.lowercased()
        if lowered.contains(".cursor") || lowered.contains("cursor") { return .cursor }
        if lowered.contains(".claude") || lowered.contains("claude") { return .claude }
        if lowered.contains(".codex") || lowered.contains("codex") { return .codex }
        if lowered.contains("hermes") { return .hermes }
        if lowered.contains(".gemini") { return .gemini }
        if lowered.contains("/.pi/") || lowered.contains(" pi ") { return .pi }
        if lowered.contains("plugin") { return .plugin }
        return .unknown
    }

    // MARK: Internals

    private static func stripVersionSuffix(_ value: String) -> String {
        // Keep scope/name; drop trailing @1.2.3
        if let at = value.lastIndex(of: "@"), at != value.startIndex {
            let before = value[..<at]
            if before.contains("/") || before.contains("mcp") {
                return String(before)
            }
        }
        return value
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}
