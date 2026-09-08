import AndromedaMCPHub
import ArgumentParser
import Foundation

struct MCPHubCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-hub",
        abstract: "Shared MCP hub — host upstream servers behind per-agent shims.",
        subcommands: [Run.self, Validate.self, Status.self],
        defaultSubcommand: Status.self
    )

    // MARK: - Common

    static func loadConfiguration(path: String?) throws -> MCPHubConfiguration {
        let resolved = path ?? MCPHubConfiguration.defaultPath
        guard FileManager.default.fileExists(
            atPath: (resolved as NSString).expandingTildeInPath
        ) else {
            throw ValidationError(
                "no hub config at \(resolved) — see docs/adr/ADR-0019-mcp-hub-config-schema.md"
            )
        }
        do {
            return try MCPHubConfiguration.load(from: resolved)
        } catch let error as MCPHubConfiguration.ConfigurationError {
            throw ValidationError("invalid hub config: \(error)")
        }
    }

    // MARK: - Subcommands

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run the hub daemon (launchd entry — KeepAlive owns restarts)."
        )

        @Option(help: "Path to servers.json (default ~/.andromeda/mcp-hub/servers.json).")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            let hub = MCPHub(configuration: configuration)
            do {
                try hub.start()
            } catch let error as MCPHub.MCPHubError {
                throw ValidationError("hub failed to start: \(error)")
            }
            // Keep alive; readability handlers do the work.
            print("mcp-hub: hosting \(configuration.servers.count) server(s) — sockets in \(configuration.socketDirectory)")
            try await Task.sleep(for: .seconds(Double.greatestFiniteMagnitude))
        }
    }

    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Validate servers.json against the ADR-0019 invariants."
        )

        @Option(help: "Path to servers.json.")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            var allHealthy = true
            for server in configuration.servers {
                let executableExists = FileManager.default.isExecutableFile(
                    atPath: (server.command as NSString).expandingTildeInPath
                )
                let marker = executableExists ? "✅" : "❌"
                print(
                    "\(marker) \(server.id) — \(server.packageName) [\(server.placement.rawValue)] → \(server.command) \(server.arguments.joined(separator: " "))"
                )
                if !executableExists {
                    allHealthy = false
                    print("     ⚠️ executable not found/resolvable — hub spawn would fail")
                }
            }
            if !allHealthy {
                throw ValidationError("one or more executables unresolved — fix before install (Codex P2)")
            }
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show hub socket census (up + accepting, or down)."
        )

        @Option(help: "Path to servers.json.")
        var config: String?

        func run() async throws {
            let configuration = try MCPHubCommand.loadConfiguration(path: config)
            for server in configuration.servers {
                let socketPath = configuration.socketPath(for: server.id)
                let listening = Self.probeListening(path: configuration.socketPath(for: server.id))
                let marker = listening ? "🟢" : "⚪️"
                print("\(marker) \(server.id) — \(socketPath)\(listening ? " (listening)" : " (no hub)")")
            }
            let telemetryPath = configuration.telemetryLogPath
            print("📊 telemetry: \(telemetryPath)")
        }

        /// A stale socket pathname survives crashes — existence is not
        /// health (Codex P2). Probe by connecting: a live listener accepts;
        /// a dead file refuses.
        static func probeListening(path: String) -> Bool {
            let expanded = (path as NSString).expandingTildeInPath
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(expanded.utf8)
            guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
            withUnsafeMutableBytes(of: &addr.sun_path) { dest in
                _ = pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest.baseAddress!, src.baseAddress!, pathBytes.count)
                }
            }
            let result = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            return result == 0
        }
    }
}
