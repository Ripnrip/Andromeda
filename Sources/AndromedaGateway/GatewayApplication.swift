import AndromedaCore
import Hummingbird
import Logging

/// Builds and runs the Andromeda Hummingbird gateway with Autocache routes.
public struct GatewayApplication {
    public let config: GatewayConfig
    public let logger: Logger

    public init(config: GatewayConfig, logger: Logger = Logger(label: "andromeda.gateway")) {
        self.config = config
        self.logger = logger
    }

    public func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let controller = AutocacheController(config: config, logger: logger)
        let router = GatewayRouter(controller: controller).build()
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
            "Starting Andromeda Hummingbird Autocache gateway",
            metadata: [
                "address": .string(config.serverAddress),
                "strategy": .string(config.cacheStrategy),
                "version": .string(AndromedaVersion.string),
            ]
        )
        let app = makeApplication()
        try await app.runService()
    }
}
