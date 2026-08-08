import AndromedaTools

/// Combines independently owned MCP capability providers without exposing their implementations.
public actor CompositeMCPToolServer: MCPToolServing {
    private let servers: [any MCPToolServing]

    public init(servers: [any MCPToolServing]) { self.servers = servers }

    /// Returns the stable capability catalog advertised to authenticated agent clients.
    public func listTools() async -> [ToolDefinition] {
        var definitions: [ToolDefinition] = []
        for server in servers { definitions.append(contentsOf: await server.listTools()) }
        return definitions
    }

    /// Routes a capability call to its owning provider.
    public func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult {
        for server in servers where await server.listTools().contains(where: { $0.name == name }) {
            return await server.callTool(name: name, arguments: arguments)
        }
        return ToolCallResult(text: "Unknown Andromeda capability: \(name)", isError: true)
    }
}
