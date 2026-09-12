import Foundation

// MARK: - Placement

/// How a server participates in the hub. Classification is a Phase-0
/// deliverable (spike S3); only `shared` servers cut over in wave 1.
public enum HubPlacement: String, Sendable, Codable, CaseIterable {
    /// One upstream for every agent session (filesystem, memory stores).
    case shared
    /// N upstreams handed out by lease (stateful but parallelizable).
    case pooled
    /// Shim spawns the legacy command itself; the hub only observes/names
    /// it (per-session UI state — browsermcp, playwright).
    case passthrough
}

// MARK: - Server configuration

/// One hosted MCP server: resolved executable (no `npm exec` at runtime),
/// placement, and naming metadata.
public struct HubServerConfig: Sendable, Equatable, Codable, Identifiable {
    /// Short server key used in socket/shim names (`filesystem`, `memory`).
    public let id: String
    /// npm / uv package or logical identity (registry-consistent).
    public let packageName: String
    /// Resolved real executable (node entrypoint .js, uv binary, Swift bin).
    public let command: String
    /// Arguments for the resolved executable (never `exec`/`-e` blobs).
    public let arguments: [String]
    /// Extra environment for THIS server only (secrets are host-side;
    /// MVP servers are secret-free per the plan).
    public let environment: [String: String]
    /// Placement mode — `shared` for the Phase-1 roster.
    public let placement: HubPlacement
    /// Dedupe key consistent with MCPServerEntity.duplicateGroup.
    public let duplicateGroup: String

    public init(
        id: String,
        packageName: String,
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        placement: HubPlacement = .shared,
        duplicateGroup: String
    ) {
        self.id = id
        self.packageName = packageName
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.placement = placement
        self.duplicateGroup = duplicateGroup
    }
}

// MARK: - Hub configuration (root document)

/// Root document of `~/.andromeda/mcp-hub/servers.json`.
public struct MCPHubConfiguration: Sendable, Equatable, Codable {
    public let socketDirectory: String
    public let logDirectory: String
    public let servers: [HubServerConfig]

    public init(
        socketDirectory: String = "~/.andromeda/mcp-hub/sockets",
        logDirectory: String = "~/.andromeda/logs",
        servers: [HubServerConfig]
    ) {
        self.socketDirectory = socketDirectory
        self.logDirectory = logDirectory
        self.servers = servers
    }

    // MARK: Paths (resolved, no ~ at runtime)

    /// Resolved socket path for a server: `<socketDirectory>/<id>.sock`.
    /// (The per-shim socket design in the plan doc was per-instance; the
    /// ADR simplified to one listening socket per server — the hub routes
    /// by connection, so one endpoint per server is sufficient and keeps
    /// the socket dir auditable.)
    public func socketPath(for serverID: String) -> String {
        resolved(socketDirectory) + "/\(serverID).sock"
    }

    /// Resolved telemetry log path.
    public var telemetryLogPath: String {
        resolved(logDirectory) + "/mcp-hub.jsonl"
    }

    private func resolved(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// True when the path exists on this host and is a directory (the
    /// shape a pinned sandbox root must have).
    private static func isDirectoryPath(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // MARK: Validation (ADR invariants)

    public enum ConfigurationError: Error, Equatable, Sendable {
        case duplicateServerID(String)
        case emptyServerID
        case invalidServerID(String)
        case emptyCommand(String)
        case placementNotSharedInWave1(String)
        case secretLookingEnvironmentKey(serverID: String, key: String)
        /// A filesystem-class server (server-filesystem) declared no
        /// allowed-directory arguments — its sandbox would fall back to
        /// client-supplied roots, which the hub never forwards (Cursor
        /// security review: last-writer-wins on the process-global
        /// allowlist). The sandbox MUST be pinned at spawn time.
        case filesystemSandboxUnpinned(serverID: String)
    }

    /// Server packages whose sandbox is a process-global filesystem
    /// allowlist pinned by CLI arguments at spawn (official
    /// `@modelcontextprotocol/server-filesystem` semantics).
    private static let filesystemSandboxPackages = ["server-filesystem"]

    /// Arguments that carry no sandbox authority — the launcher script
    /// itself is argv[0] of the node invocation, not an allowed directory
    /// (Codex round 3: `arguments = [launcher.js]` alone passed the
    /// nonempty check while pinning nothing).
    private static func isLauncherArgument(_ argument: String) -> Bool {
        argument.hasSuffix(".js")
    }

    /// True when this server's sandbox is filesystem-allowlist based and
    /// therefore must carry at least one allowed-directory argument.
    private func requiresPinnedSandbox(_ server: HubServerConfig) -> Bool {
        Self.filesystemSandboxPackages.contains { server.packageName.contains($0) }
    }

    /// ADR invariants: ids are unique, short, `[a-z0-9-]` only (they name
    /// sockets and shim binaries); commands resolve to real executables;
    /// wave-1 roster is `shared` placement only; filesystem-class servers
    /// pin their sandbox directories as spawn-time arguments.
    public func validated() throws -> MCPHubConfiguration {
        var seen = Set<String>()
        for server in servers {
            guard !server.id.isEmpty else { throw ConfigurationError.emptyServerID }
            guard server.id.allSatisfy({ ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "-" }) else {
                throw ConfigurationError.invalidServerID(server.id)
            }
            guard seen.insert(server.id).inserted else {
                throw ConfigurationError.duplicateServerID(server.id)
            }
            guard !server.command.isEmpty else { throw ConfigurationError.emptyCommand(server.id) }
            guard server.placement == .shared else {
                throw ConfigurationError.placementNotSharedInWave1(server.id)
            }
            // Cursor style review: env-bearing servers are gated, not just
            // avoided by convention — keys that look like credentials are
            // rejected until the SecretsBroker lane can inject them properly
            // (plan §2.3: "no raw keys in client env"; hub env injection is
            // host-side and allowed, but secrets route via the broker once
            // real). Benign config keys (paths, flags) pass.
            for key in server.environment.keys where Self.looksLikeSecretKey(key) {
                throw ConfigurationError.secretLookingEnvironmentKey(serverID: server.id, key: key)
            }
            // Cursor security review (HIGH): the hub — not any client —
            // owns the filesystem sandbox. Client roots are never
            // forwarded (see JSONRPCRelay), so a filesystem server with no
            // allowed-directory argument would run UNSANDBOXED (its CLI
            // default is cwd-only, and the hub's cwd is not a sandbox).
            // Pinning at config time makes the sandbox auditable.
            // Codex P2: a launcher-only config (nonempty args, no dir) pins
            // nothing; a typo'd nonexistent path pins nothing either —
            // require an argument that exists ON THIS HOST as a directory.
            if requiresPinnedSandbox(server) {
                let pinnedDirectory = server.arguments.first {
                    !$0.hasSuffix(".js") && Self.isDirectoryPath($0)
                }
                guard pinnedDirectory != nil else {
                    throw ConfigurationError.filesystemSandboxUnpinned(serverID: server.id)
                }
            }
        }
        return self
    }

    // MARK: Load / save

    public static func load(from path: String) throws -> MCPHubConfiguration {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(MCPHubConfiguration.self, from: data)
        return try decoded.validated()
    }

    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    /// Credential-shaped env-key markers (case-insensitive substrings) —
    /// the wave-1 gate until the broker lands. An ENUM, not a bare string
    /// array: membership is exhaustive by construction, CaseIterable drives
    /// the tests, and a marker cannot drift in as an unreviewed string.
    public enum SecretKeyMarker: String, CaseIterable, Sendable {
        case secret, token, key, api, credential, password, passwd
    }

    public static func looksLikeSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return SecretKeyMarker.allCases.contains { lowered.contains($0.rawValue) }
    }

    /// Default config path (ADR-locked location).
    public static var defaultPath: String {
        "~/.andromeda/mcp-hub/servers.json"
    }
}
