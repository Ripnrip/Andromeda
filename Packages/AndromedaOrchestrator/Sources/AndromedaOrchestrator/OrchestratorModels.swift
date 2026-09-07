import Foundation

// MARK: - Domain

//
// Pure value types. No view knows how to build one; no model knows how one
// looks. Everything here is `Sendable` so it crosses task boundaries under
// Swift 6 strict concurrency without ceremony.

public enum Dialect: String, Sendable, CaseIterable, Identifiable {
    case messages
    case responses
    case completions

    public var id: String {
        rawValue
    }

    /// The path clients actually POST to.
    public var path: String {
        switch self {
        case .messages: "/v1/messages"
        case .responses: "/v1/responses"
        case .completions: "/v1/chat/completions"
        }
    }

    public var note: String {
        switch self {
        case .messages: "Anthropic dialect, native. Cache breakpoints injected on the way through."
        case .responses: "OpenAI responses, shape-translated both ways."
        case .completions: "Legacy completions for anything that still speaks it."
        }
    }

    public var clients: String {
        switch self {
        case .messages: "Claude Code · Claude Desktop"
        case .responses: "Codex · custom agents"
        case .completions: "Cursor · Zed · scripts"
        }
    }
}

public struct GatewayRequest: Sendable, Identifiable {
    public let id = UUID()
    public var dialect: Dialect
    public var alias: String
    public var route: String
    public var latencyMS: Int
    public var tokens: Int
    public var cached: Bool
    public var failedOver: Bool
    public var status: OrchestratorStatus
}

public struct MCPServer: Sendable, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var origin: String
    public var transport: String
    public var tools: Int
    public var exposedTools: Int
    public var calls: Int
    public var p95: String
    public var scopes: String
    public var status: OrchestratorStatus
}

public struct Provider: Sendable, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var endpoint: String
    /// Circuit-breaker position, not a vibe: closed = passing traffic.
    public var breaker: BreakerState
    public var p95: String
    public var errorRate: String
    public var models: Int
    public var spend: String
    public var trafficShare: Double

    public enum BreakerState: String, Sendable {
        case closed = "CLOSED"
        case halfOpen = "HALF-OPEN"
        case open = "OPEN"

        public var status: OrchestratorStatus {
            switch self {
            case .closed: .healthy
            case .halfOpen: .degraded
            case .open: .failed
            }
        }
    }
}

/// What clients call. The alias is the contract; the target is ours to move.
public struct ModelAlias: Sendable, Identifiable {
    public var id: String {
        alias
    }

    public var alias: String
    public var target: String
    public var provider: String
    public var context: String
    public var price: String
    public var p95: String
    public var capabilities: [String]
    public var status: OrchestratorStatus
}

public struct AliasSpend: Sendable, Identifiable {
    public var id: String {
        alias
    }

    public var alias: String
    public var spend: Double
    public var requests: Int
    public var cacheHitRate: Double
    public var share: Double
}

// MARK: - Sample data

//
// Demo fixtures, explicitly named as such per the review canon: this is the
// shape of real telemetry, not a claim that any of it shipped.

public enum SampleData {
    public static let mcpServers: [MCPServer] = [
        .init(name: "github", origin: "npx @modelcontextprotocol/server-github", transport: "stdio",
              tools: 14, exposedTools: 12, calls: 212, p95: "184ms",
              scopes: "repo:read, issues:write", status: .healthy),
        .init(name: "slack", origin: "npx @andromeda/mcp-slack", transport: "stdio",
              tools: 9, exposedTools: 9, calls: 96, p95: "240ms",
              scopes: "chat:write, search:read", status: .healthy),
        .init(name: "postgres", origin: "https://mcp.internal/pg", transport: "http",
              tools: 5, exposedTools: 4, calls: 61, p95: "88ms",
              scopes: "query:read", status: .healthy),
        .init(name: "filesystem", origin: "built-in · sandboxed to ~/dev", transport: "stdio",
              tools: 7, exposedTools: 5, calls: 143, p95: "12ms",
              scopes: "read, write:scoped", status: .healthy),
        .init(name: "sentry", origin: "https://mcp.sentry.dev", transport: "http",
              tools: 6, exposedTools: 6, calls: 24, p95: "402ms",
              scopes: "issues:read", status: .degraded),
        .init(name: "linear", origin: "npx @linear/mcp", transport: "stdio",
              tools: 8, exposedTools: 8, calls: 37, p95: "196ms",
              scopes: "issues:write", status: .healthy),
        .init(name: "browser", origin: "npx @andromeda/mcp-browser", transport: "stdio",
              tools: 6, exposedTools: 3, calls: 12, p95: "1.2s",
              scopes: "navigate, read", status: .degraded),
        .init(name: "memory", origin: "built-in · MemoryKit", transport: "in-process",
              tools: 5, exposedTools: 5, calls: 308, p95: "6ms",
              scopes: "recall, write", status: .healthy),
        .init(name: "notion", origin: "npx @notionhq/mcp", transport: "stdio",
              tools: 11, exposedTools: 0, calls: 0, p95: "—",
              scopes: "none granted", status: .idle),
    ]

    public static let providers: [Provider] = [
        .init(name: "Anthropic", endpoint: "api.anthropic.com", breaker: .closed,
              p95: "412ms", errorRate: "0.2%", models: 6, spend: "$71", trafficShare: 0.46),
        .init(name: "OpenAI", endpoint: "api.openai.com", breaker: .halfOpen,
              p95: "508ms", errorRate: "8.4%", models: 7, spend: "$38", trafficShare: 0.22),
        .init(name: "Google", endpoint: "generativelanguage.googleapis.com", breaker: .closed,
              p95: "286ms", errorRate: "0.4%", models: 5, spend: "$14", trafficShare: 0.12),
        .init(name: "Groq", endpoint: "api.groq.com", breaker: .closed,
              p95: "119ms", errorRate: "0.9%", models: 4, spend: "$6", trafficShare: 0.09),
        .init(name: "Bedrock", endpoint: "bedrock-runtime.us-west-2", breaker: .closed,
              p95: "604ms", errorRate: "0.3%", models: 5, spend: "$9", trafficShare: 0.05),
        .init(name: "Ollama", endpoint: "127.0.0.1:11434 · local", breaker: .closed,
              p95: "204ms", errorRate: "1.8%", models: 3, spend: "$0", trafficShare: 0.06),
    ]

    public static let aliases: [ModelAlias] = [
        .init(alias: "sonnet-latest", target: "claude-sonnet-4.5", provider: "anthropic",
              context: "200k", price: "3.00 · 15.0", p95: "412ms",
              capabilities: ["reasoning", "vision", "tools", "cache"], status: .healthy),
        .init(alias: "haiku-fast", target: "claude-haiku-4.5", provider: "anthropic",
              context: "200k", price: "0.80 · 4.00", p95: "198ms",
              capabilities: ["tools", "cache"], status: .healthy),
        .init(alias: "gpt-omni", target: "gpt-5.1", provider: "openai → bedrock",
              context: "400k", price: "2.50 · 10.0", p95: "508ms",
              capabilities: ["reasoning", "vision", "tools"], status: .degraded),
        .init(alias: "flash-cheap", target: "gemini-2.5-flash", provider: "google",
              context: "1M", price: "0.30 · 2.50", p95: "286ms",
              capabilities: ["vision", "tools", "long-context"], status: .healthy),
        .init(alias: "turbo-local", target: "qwen3-14b", provider: "ollama",
              context: "32k", price: "free", p95: "204ms",
              capabilities: ["tools"], status: .healthy),
        .init(alias: "reasoner", target: "o4-mini", provider: "openai",
              context: "200k", price: "1.10 · 4.40", p95: "1.4s",
              capabilities: ["reasoning", "json-mode"], status: .idle),
    ]

    public static let spend: [AliasSpend] = [
        .init(alias: "sonnet-latest", spend: 71.40, requests: 12418, cacheHitRate: 0.38, share: 0.51),
        .init(alias: "gpt-omni", spend: 38.10, requests: 6204, cacheHitRate: 0.19, share: 0.27),
        .init(alias: "flash-cheap", spend: 14.20, requests: 9881, cacheHitRate: 0.44, share: 0.10),
        .init(alias: "haiku-fast", spend: 9.80, requests: 15260, cacheHitRate: 0.61, share: 0.07),
        .init(alias: "reasoner", spend: 6.30, requests: 412, cacheHitRate: 0.02, share: 0.05),
        .init(alias: "turbo-local", spend: 0, requests: 3140, cacheHitRate: 0, share: 0),
    ]
}
