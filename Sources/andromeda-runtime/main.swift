import AndromedaSecrets
import AndromedaServer
import AndromedaTools
import ArgumentParser
import Foundation
import Logging

@main
struct AndromedaRuntimeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda-runtime",
        abstract: "Runnable Andromeda Runtime v2 server.",
        subcommands: [Serve.self],
        defaultSubcommand: Serve.self
    )
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Andromeda runtime memory server in the foreground."
    )

    @Option(name: .long, help: "Bind host. Defaults to 0.0.0.0.")
    var host: String = "0.0.0.0"

    @Option(name: .long, help: "Bind port. Defaults to 8788.")
    var port: Int = 8788

    @Option(name: .long, help: "Path to the canonical JSONL event journal.")
    var journalPath: String

    @Option(name: .long, help: "Directory for the Obsidian-compatible Markdown vault. Defaults to a sibling 'vault' directory next to the journal.")
    var vaultDir: String?

    @Option(name: .long, help: "Base URL for the Qdrant HTTP API. Defaults to http://localhost:6333.")
    var qdrantUrl: String = "http://localhost:6333"

    @Option(name: .long, help: "Bearer token VM agents use for POST /mcp. Env: ANDROMEDA_MCP_BEARER_TOKEN. Enables the tools/MCP endpoint when set.")
    var mcpBearerToken: String?

    @Option(name: .long, help: "Keychain service holding the GitHub token. Env: ANDROMEDA_GITHUB_TOKEN_SERVICE.")
    var githubTokenService: String?

    @Option(name: .long, help: "Keychain account holding the GitHub token. Env: ANDROMEDA_GITHUB_TOKEN_ACCOUNT.")
    var githubTokenAccount: String?

    @Option(name: .long, help: "Keychain service holding the Slack token. Env: ANDROMEDA_SLACK_TOKEN_SERVICE.")
    var slackTokenService: String?

    @Option(name: .long, help: "Keychain account holding the Slack token. Env: ANDROMEDA_SLACK_TOKEN_ACCOUNT.")
    var slackTokenAccount: String?

    @Flag(name: .long, help: "Allow write operations (GitHub POST/PATCH/PUT/DELETE, Slack writes) through the tools broker. Env: ANDROMEDA_TOOLS_AUTOMATION=1.")
    var automationAllowed = false

    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "andromeda.runtime.cli")
        guard let qdrantBaseURL = URL(string: qdrantUrl) else {
            throw ValidationError("Invalid Qdrant URL: \(qdrantUrl)")
        }

        let env = ProcessInfo.processInfo.environment
        func option(_ value: String?, _ envName: String) -> String? {
            value ?? env[envName]
        }

        var mcpConfiguration: MCPConfiguration?
        if let bearerToken = option(mcpBearerToken, "ANDROMEDA_MCP_BEARER_TOKEN"), !bearerToken.isEmpty {
            var github: ToolsBrokerConfiguration.GitHub?
            if let service = option(githubTokenService, "ANDROMEDA_GITHUB_TOKEN_SERVICE"),
               let account = option(githubTokenAccount, "ANDROMEDA_GITHUB_TOKEN_ACCOUNT")
            {
                github = .init(tokenReference: SecretReference(service: service, account: account))
            }
            var slack: ToolsBrokerConfiguration.Slack?
            if let service = option(slackTokenService, "ANDROMEDA_SLACK_TOKEN_SERVICE"),
               let account = option(slackTokenAccount, "ANDROMEDA_SLACK_TOKEN_ACCOUNT")
            {
                slack = .init(tokenReference: SecretReference(service: service, account: account))
            }
            let automation = automationAllowed || env["ANDROMEDA_TOOLS_AUTOMATION"] == "1"
            mcpConfiguration = try MCPConfiguration(
                bearerToken: bearerToken,
                tools: ToolsBrokerConfiguration(automationAllowed: automation, github: github, slack: slack)
            )
            logger.info(
                "Tools/MCP broker enabled",
                metadata: [
                    "github": .stringConvertible(github != nil),
                    "slack": .stringConvertible(slack != nil),
                    "automation": .stringConvertible(automation),
                ]
            )
        }

        let server = try AndromedaRuntimeServer(
            configuration: AndromedaRuntimeConfiguration(host: host, port: port, mcp: mcpConfiguration),
            journalFileURL: URL(fileURLWithPath: journalPath),
            vaultDirectoryURL: vaultDir.map { URL(fileURLWithPath: $0) },
            qdrantBaseURL: qdrantBaseURL,
            logger: logger
        )
        try await server.run()
    }
}
