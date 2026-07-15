import AndromedaCore
import AndromedaGateway
import ArgumentParser
import Foundation
import Logging

@main
struct Andromeda: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda",
        abstract: "Andromeda — Swift-native control plane and Hummingbird model gateway.",
        version: AndromedaVersion.string,
        subcommands: [Serve.self, Status.self],
        defaultSubcommand: Status.self
    )
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show gateway identity and Autocache surface readiness."
    )

    func run() async throws {
        let config = try GatewayConfig.loadFromEnvironment()
        print("\(AndromedaVersion.productName) \(AndromedaVersion.string)")
        print("surface: autocache (Anthropic prompt-cache proxy)")
        print("bind: \(config.serverAddress)")
        print("strategy: \(config.cacheStrategy)")
        print("anthropic: \(config.anthropicURL)")
        print("api_key: \(config.apiKeyConfigured ? "configured" : "per-request headers")")
        print("ready: run `andromeda serve` to start the Hummingbird gateway")
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Hummingbird Autocache model gateway in the foreground."
    )

    @Option(name: .long, help: "Bind host (default from HOST or 127.0.0.1).")
    var host: String?

    @Option(name: .long, help: "Bind port (default from PORT or 8080).")
    var port: Int?

    @Option(name: .long, help: "Cache strategy: conservative|moderate|aggressive.")
    var strategy: String?

    func run() async throws {
        var config = try GatewayConfig.loadFromEnvironment()
        if let host { config.host = host }
        if let port { config.port = port }
        if let strategy { config.cacheStrategy = strategy }
        try config.validate()
        let resolvedLogLevel = Self.logLevel(from: config.logLevel)

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = resolvedLogLevel
            return handler
        }

        let logger = Logger(label: "andromeda.cli")
        logger.info(
            """

                 _            _
                / \\   _ __  | |_ __ ___  _ __ ___   ___  __| | __ _
               / _ \\ | '_ \\ | | '__/ _ \\| '_ ` _ \\ / _ \\/ _` |/ _` |
              / ___ \\| | | || | | | (_) | | | | | |  __/ (_| | (_| |
             /_/   \\_\\_| |_||_|_|  \\___/|_| |_| |_|\\___|\\__,_|\\__,_|

             Hummingbird Autocache Gateway — Anthropic prompt-cache proxy
            """
        )

        let gateway = GatewayApplication(config: config, logger: logger)
        try await gateway.run()
    }

    private static func logLevel(from value: String) -> Logger.Level {
        switch value.lowercased() {
        case "trace": .trace
        case "debug": .debug
        case "info": .info
        case "warn", "warning": .warning
        case "error": .error
        case "critical": .critical
        default: .info
        }
    }
}
