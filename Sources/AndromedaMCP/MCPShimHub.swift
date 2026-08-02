import Foundation
import Logging

/// Redacted audit event for an MCP shim invocation.
public struct MCPShimAuditEvent: Sendable, Equatable, Codable {
    public let capability: String
    public let method: String
    public let toolName: String?
    public let allowed: Bool
    public let isError: Bool
    public let detail: String
    public let timestamp: Date

    public init(
        capability: String,
        method: String,
        toolName: String?,
        allowed: Bool,
        isError: Bool,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.capability = capability
        self.method = method
        self.toolName = toolName
        self.allowed = allowed
        self.isError = isError
        self.detail = detail
        self.timestamp = timestamp
    }
}

/// Central MCP shim hub: broker auth → allowlist → host-credentialed upstream.
///
/// Option-2 MVP: literal wrapper. Allowlists already slim discovery (option-1 seed).
public actor MCPShimHub {
    private let vault: SecretVault
    private let scrubber: SecretScrubber
    private let allowlists: [MCPCapabilityID: ToolAllowlist]
    private let providers: [MCPCapabilityID: any UpstreamMCPProviding]
    private let brokerToken: String
    private let logger: Logger
    private var auditLog: [MCPShimAuditEvent] = []

    public init(
        vault: SecretVault,
        providers: [MCPCapabilityID: any UpstreamMCPProviding],
        brokerToken: String,
        allowlists: [MCPCapabilityID: ToolAllowlist] = ToolAllowlist.defaults,
        logger: Logger = Logger(label: "andromeda.mcp.shim")
    ) {
        self.vault = vault
        self.scrubber = SecretScrubber(vault: vault)
        self.providers = providers
        self.brokerToken = brokerToken
        self.allowlists = allowlists
        self.logger = logger
    }

    /// Convenience builder: mock providers when upstream URLs are absent.
    public static func makeDefault(
        vault: SecretVault = .loadFromEnvironment(),
        brokerToken: String,
        slackUpstreamURL: URL? = nil,
        githubUpstreamURL: URL? = nil,
        logger: Logger = Logger(label: "andromeda.mcp.shim")
    ) -> MCPShimHub {
        var providers: [MCPCapabilityID: any UpstreamMCPProviding] = [:]

        if let slackUpstreamURL {
            providers[.slackProxy] = HTTPUpstreamMCPProvider(
                capability: .slackProxy,
                endpoint: slackUpstreamURL,
                credential: vault.credential(for: .slackProxy)
            )
        } else {
            providers[.slackProxy] = MockUpstreamMCPProvider(
                capability: .slackProxy,
                tools: ToolAllowlist.slackDefault.allowedTools.sorted().map {
                    MCPToolDescriptor(name: $0, description: "Slack tool (host-brokered)")
                },
                authPresent: vault.isConfigured(.slackProxy)
            )
        }

        if let githubUpstreamURL {
            providers[.githubProxy] = HTTPUpstreamMCPProvider(
                capability: .githubProxy,
                endpoint: githubUpstreamURL,
                credential: vault.credential(for: .githubProxy)
            )
        } else {
            providers[.githubProxy] = MockUpstreamMCPProvider(
                capability: .githubProxy,
                tools: ToolAllowlist.githubDefault.allowedTools.sorted().map {
                    MCPToolDescriptor(name: $0, description: "GitHub tool (host-brokered)")
                },
                authPresent: vault.isConfigured(.githubProxy)
            )
        }

        return MCPShimHub(
            vault: vault,
            providers: providers,
            brokerToken: brokerToken,
            logger: logger
        )
    }

    public func recentAudit(limit: Int = 50) -> [MCPShimAuditEvent] {
        Array(auditLog.suffix(limit))
    }

    public func healthPayload() -> Data {
        let object: [String: Any] = [
            "status": "healthy",
            "surface": "mcp_shim",
            "capabilities": MCPCapabilityID.allCases.map { capability -> [String: Any] in
                [
                    "id": capability.rawValue,
                    "secret_configured": vault.isConfigured(capability),
                    "provider_present": providers[capability] != nil,
                    "allowlist_count": allowlists[capability]?.allowedTools.count ?? 0,
                ]
            },
            "broker_token_configured": !brokerToken.isEmpty,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    /// Handles a JSON-RPC MCP request from a guest after broker-token validation.
    public func handle(
        request: MCPJSONRPCRequest,
        authorizationHeader: String?
    ) async -> MCPJSONRPCResponse {
        do {
            try authorize(authorizationHeader)
            switch request.method {
            case "initialize":
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: AnyCodable([
                        "protocolVersion": "2024-11-05",
                        "capabilities": ["tools": [:] as [String: Any]],
                        "serverInfo": [
                            "name": "andromeda-mcp-shim",
                            "version": "0.1.0",
                        ],
                    ] as [String: Any])
                )
            case "tools/list", "notifications/initialized":
                if request.method == "notifications/initialized" {
                    return MCPJSONRPCResponse(id: request.id, result: AnyCodable([:] as [String: Any]))
                }
                let tools = try await listAllowlistedTools()
                record(
                    capability: "all",
                    method: request.method,
                    toolName: nil,
                    allowed: true,
                    isError: false,
                    detail: "listed \(tools.count) tools"
                )
                let encoded: [[String: Any]] = tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "inputSchema": tool.inputSchema.mapValues(\.value),
                    ]
                }
                return MCPJSONRPCResponse(
                    id: request.id,
                    result: AnyCodable(["tools": encoded] as [String: Any])
                )
            case "tools/call":
                return try await handleToolCall(request)
            case "ping":
                return MCPJSONRPCResponse(id: request.id, result: AnyCodable([:] as [String: Any]))
            default:
                throw MCPShimError.unknownMethod(request.method)
            }
        } catch let error as MCPShimError {
            record(
                capability: "unknown",
                method: request.method,
                toolName: nil,
                allowed: false,
                isError: true,
                detail: scrubber.scrub(error.message)
            )
            return MCPJSONRPCResponse(
                id: request.id,
                error: MCPJSONRPCError(code: error.code, message: scrubber.scrub(error.message))
            )
        } catch {
            let message = scrubber.scrub(String(describing: error))
            record(
                capability: "unknown",
                method: request.method,
                toolName: nil,
                allowed: false,
                isError: true,
                detail: message
            )
            return MCPJSONRPCResponse(
                id: request.id,
                error: MCPJSONRPCError(code: -32603, message: message)
            )
        }
    }

    private func handleToolCall(_ request: MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse {
        guard let params = request.params,
              let nameValue = params["name"]?.value as? String
        else {
            throw MCPShimError.invalidRequest("tools/call requires params.name")
        }
        let arguments = (params["arguments"]?.value as? [String: Any])?
            .mapValues(AnyCodable.init) ?? [:]

        guard let capability = ToolCapabilityRouter.capability(for: nameValue) else {
            throw MCPShimError.toolNotAllowed(nameValue)
        }
        guard let allowlist = allowlists[capability], allowlist.allows(nameValue) else {
            throw MCPShimError.toolNotAllowed(nameValue)
        }
        guard let provider = providers[capability] else {
            throw MCPShimError.capabilityUnavailable(capability)
        }
        guard vault.isConfigured(capability) else {
            throw MCPShimError.capabilityUnavailable(capability)
        }

        let result = try await provider.callTool(name: nameValue, arguments: arguments)
        let scrubbedBlocks = result.content.map { block in
            MCPContentBlock(type: block.type, text: block.text.map(scrubber.scrub))
        }
        let scrubbed = MCPToolCallResult(content: scrubbedBlocks, isError: result.isError)
        record(
            capability: capability.rawValue,
            method: "tools/call",
            toolName: nameValue,
            allowed: true,
            isError: scrubbed.isError,
            detail: "forwarded"
        )
        logger.info(
            "mcp shim tool call",
            metadata: [
                "capability": .string(capability.rawValue),
                "tool": .string(nameValue),
                "error": .stringConvertible(scrubbed.isError),
            ]
        )
        let payload: [String: Any] = [
            "content": scrubbed.content.map { block -> [String: Any] in
                var item: [String: Any] = ["type": block.type]
                if let text = block.text {
                    item["text"] = text
                }
                return item
            },
            "isError": scrubbed.isError,
        ]
        return MCPJSONRPCResponse(id: request.id, result: AnyCodable(payload))
    }

    private func listAllowlistedTools() async throws -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = []
        for capability in MCPCapabilityID.allCases {
            guard let provider = providers[capability],
                  let allowlist = allowlists[capability],
                  vault.isConfigured(capability)
            else { continue }
            let upstream = try await provider.listTools()
            tools.append(contentsOf: upstream.filter { allowlist.allows($0.name) })
        }
        return tools.sorted { $0.name < $1.name }
    }

    private func authorize(_ header: String?) throws {
        guard !brokerToken.isEmpty else {
            // Empty broker token disables guest access entirely.
            throw MCPShimError.unauthorized
        }
        guard let header else { throw MCPShimError.unauthorized }
        let token: String
        if header.lowercased().hasPrefix("bearer ") {
            token = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else {
            token = header.trimmingCharacters(in: .whitespaces)
        }
        guard token == brokerToken else { throw MCPShimError.unauthorized }
    }

    private func record(
        capability: String,
        method: String,
        toolName: String?,
        allowed: Bool,
        isError: Bool,
        detail: String
    ) {
        auditLog.append(
            MCPShimAuditEvent(
                capability: capability,
                method: method,
                toolName: toolName,
                allowed: allowed,
                isError: isError,
                detail: scrubber.scrub(detail)
            )
        )
        if auditLog.count > 500 {
            auditLog.removeFirst(auditLog.count - 500)
        }
    }
}
