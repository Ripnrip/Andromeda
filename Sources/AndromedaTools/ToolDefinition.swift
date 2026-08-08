import Foundation

/// A tool exposed to VM-side MCP clients. The curated surface is deliberately
/// small: VM agents see only these names, never the raw upstream surface.
public struct ToolDefinition: Sendable, Equatable, Codable {
    public let name: String
    public let description: String
    /// JSON Schema object describing the tool's arguments.
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Text content returned from a tool call, matching the MCP tool result shape.
public struct ToolCallResult: Sendable, Equatable, Codable {
    public struct Content: Sendable, Equatable, Codable {
        public let type: String
        public let text: String

        public init(text: String) {
            self.type = "text"
            self.text = text
        }
    }

    public let content: [Content]
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.content = [Content(text: text)]
        self.isError = isError
    }
}

/// A provider-neutral MCP tool surface that can be composed behind Andromeda's authenticated endpoint.
public protocol MCPToolServing: Sendable {
    func listTools() async -> [ToolDefinition]
    func callTool(name: String, arguments: [String: JSONValue]) async -> ToolCallResult
}
