import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Upstream MCP provider that Andromeda proxies on behalf of guests.
public protocol UpstreamMCPProviding: Sendable {
    var capability: MCPCapabilityID { get }

    /// Lists tools from the upstream (pre-allowlist).
    func listTools() async throws -> [MCPToolDescriptor]

    /// Invokes a tool on the upstream. Host injects auth before this runs.
    func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult
}

/// In-memory upstream used by tests and dry-run demos.
public struct MockUpstreamMCPProvider: UpstreamMCPProviding {
    public let capability: MCPCapabilityID
    public let tools: [MCPToolDescriptor]
    public let responses: [String: MCPToolCallResult]
    public let authPresent: Bool

    public init(
        capability: MCPCapabilityID,
        tools: [MCPToolDescriptor],
        responses: [String: MCPToolCallResult] = [:],
        authPresent: Bool = true
    ) {
        self.capability = capability
        self.tools = tools
        self.responses = responses
        self.authPresent = authPresent
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        tools
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult {
        if !authPresent {
            return .text("upstream auth missing on host", isError: true)
        }
        if let canned = responses[name] {
            return canned
        }
        let argSummary = arguments.keys.sorted().joined(separator: ",")
        return .text("ok:\(capability.rawValue):\(name):\(argSummary)")
    }
}

/// Pass-through HTTP JSON-RPC upstream (option-2 literal wrapper).
///
/// Host credentials are attached as `Authorization: Bearer` on the upstream
/// request only — never returned to the guest.
public struct HTTPUpstreamMCPProvider: UpstreamMCPProviding, @unchecked Sendable {
    public let capability: MCPCapabilityID
    public let endpoint: URL
    public let credential: String?
    private let session: URLSession

    public init(
        capability: MCPCapabilityID,
        endpoint: URL,
        credential: String?,
        session: URLSession = .shared
    ) {
        self.capability = capability
        self.endpoint = endpoint
        self.credential = credential
        self.session = session
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        let request = MCPJSONRPCRequest(id: .number(1), method: "tools/list", params: [:])
        let response = try await post(request)
        guard let result = response.result?.value as? [String: Any],
              let tools = result["tools"] as? [[String: Any]]
        else {
            return []
        }
        return tools.compactMap { raw in
            guard let name = raw["name"] as? String else { return nil }
            let description = raw["description"] as? String ?? ""
            let schema = (raw["inputSchema"] as? [String: Any]) ?? [:]
            return MCPToolDescriptor(
                name: name,
                description: description,
                inputSchema: schema.mapValues(AnyCodable.init)
            )
        }
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolCallResult {
        let params: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(arguments.mapValues(\.value)),
        ]
        let request = MCPJSONRPCRequest(id: .number(1), method: "tools/call", params: params)
        let response = try await post(request)
        if let error = response.error {
            return .text(error.message, isError: true)
        }
        guard let result = response.result?.value as? [String: Any] else {
            return .text("empty upstream result", isError: true)
        }
        let isError = result["isError"] as? Bool ?? false
        let blocks = (result["content"] as? [[String: Any]] ?? []).map { block in
            MCPContentBlock(type: block["type"] as? String ?? "text", text: block["text"] as? String)
        }
        return MCPToolCallResult(content: blocks, isError: isError)
    }

    private func post(_ rpc: MCPJSONRPCRequest) async throws -> MCPJSONRPCResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credential, !credential.isEmpty {
            urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONEncoder().encode(rpc)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw MCPShimError.upstreamFailure(status: status, message: "upstream HTTP \(status)")
        }
        return try JSONDecoder().decode(MCPJSONRPCResponse.self, from: data)
    }
}

public enum MCPShimError: Error, Sendable, Equatable {
    case unauthorized
    case toolNotAllowed(String)
    case capabilityUnavailable(MCPCapabilityID)
    case unknownMethod(String)
    case upstreamFailure(status: Int, message: String)
    case invalidRequest(String)

    public var code: Int {
        switch self {
        case .unauthorized: -32001
        case .toolNotAllowed: -32002
        case .capabilityUnavailable: -32003
        case .unknownMethod: -32601
        case .upstreamFailure: -32004
        case .invalidRequest: -32600
        }
    }

    public var message: String {
        switch self {
        case .unauthorized:
            "Broker token missing or invalid"
        case .toolNotAllowed(let name):
            "Tool not on allowlist: \(name)"
        case .capabilityUnavailable(let capability):
            "Capability unavailable: \(capability.rawValue)"
        case .unknownMethod(let method):
            "Method not found: \(method)"
        case .upstreamFailure(_, let message):
            message
        case .invalidRequest(let detail):
            detail
        }
    }
}
