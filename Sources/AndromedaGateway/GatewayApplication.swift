import AndromedaCore
import AndromedaMCP
import Foundation
import Hummingbird
import Logging

/// Builds and runs the Andromeda Hummingbird gateway with Autocache + MCP shim routes.
public struct GatewayApplication {
    public let config: GatewayConfig
    public let logger: Logger
    public let mcpHub: MCPShimHub?

    public init(
        config: GatewayConfig,
        logger: Logger = Logger(label: "andromeda.gateway"),
        vault: SecretVault? = nil
    ) {
        self.config = config
        self.logger = logger
        if config.enableMCPShim {
            let resolvedVault = vault ?? SecretVault.loadFromEnvironment()
            let broker = config.brokerToken ?? ""
            self.mcpHub = MCPShimHub.makeDefault(
                vault: resolvedVault,
                brokerToken: broker,
                slackUpstreamURL: config.slackUpstreamMCPURL.flatMap(URL.init(string:)),
                githubUpstreamURL: config.githubUpstreamMCPURL.flatMap(URL.init(string:)),
                logger: Logger(label: "andromeda.mcp.shim")
            )
        } else {
            self.mcpHub = nil
        }
    }

    public func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let controller = AutocacheController(config: config, logger: logger)
        let router = GatewayRouter(controller: controller, mcpHub: mcpHub).build()
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(config.host, port: config.port),
                serverName: "AndromedaGateway/\(AndromedaVersion.string)"
            ),
            logger: logger
        )
        return app
    }

    public func run() async throws {
        logger.info(
            "Starting Andromeda Hummingbird gateway",
            metadata: [
                "address": .string(config.serverAddress),
                "strategy": .string(config.cacheStrategy),
                "version": .string(AndromedaVersion.string),
                "mcp_shim": .stringConvertible(mcpHub != nil),
            ]
        )
        let app = makeApplication()
        try await app.runService()
    }
}
