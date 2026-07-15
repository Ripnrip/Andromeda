import Foundation

/// Ephemeral Anthropic prompt-cache control block.
public struct CacheControl: Codable, Sendable, Equatable {
    public var type: String
    public var ttl: String

    public init(type: String = "ephemeral", ttl: String) {
        self.type = type
        self.ttl = ttl
    }
}

/// Anthropic content block with optional cache control.
public struct ContentBlock: Codable, Sendable, Equatable {
    public var type: String
    public var text: String?
    public var source: ImageSource?
    public var cacheControl: CacheControl?
    public var id: String?
    public var name: String?
    public var input: AnyCodable?
    public var toolUseID: String?
    public var content: AnyCodable?
    public var isError: Bool?

    public init(
        type: String,
        text: String? = nil,
        source: ImageSource? = nil,
        cacheControl: CacheControl? = nil,
        id: String? = nil,
        name: String? = nil,
        input: AnyCodable? = nil,
        toolUseID: String? = nil,
        content: AnyCodable? = nil,
        isError: Bool? = nil
    ) {
        self.type = type
        self.text = text
        self.source = source
        self.cacheControl = cacheControl
        self.id = id
        self.name = name
        self.input = input
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source
        case cacheControl = "cache_control"
        case id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

public struct ImageSource: Codable, Sendable, Equatable {
    public var type: String
    public var mediaType: String
    public var data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

/// Conversation message supporting string or block content on decode.
public struct Message: Codable, Sendable, Equatable {
    public var role: String
    public var content: [ContentBlock]

    public init(role: String, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = [ContentBlock(type: "text", text: text)]
        } else {
            content = try container.decode([ContentBlock].self, forKey: .content)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }

    private enum CodingKeys: String, CodingKey {
        case role, content
    }
}

public struct ToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: AnyCodable
    public var cacheControl: CacheControl?

    public init(
        name: String,
        description: String,
        inputSchema: AnyCodable,
        cacheControl: CacheControl? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.cacheControl = cacheControl
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
        case cacheControl = "cache_control"
    }
}

/// System prompt as either a plain string or content blocks.
public enum SystemPrompt: Sendable, Equatable {
    case text(String)
    case blocks([ContentBlock])

    public var isEmpty: Bool {
        switch self {
        case .text(let value): value.isEmpty
        case .blocks(let blocks): blocks.isEmpty
        }
    }
}

/// Anthropic Messages API request with Autocache-friendly system handling.
public struct AnthropicRequest: Codable, Sendable, Equatable {
    public var model: String
    public var maxTokens: Int
    public var messages: [Message]
    public var system: SystemPrompt?
    public var tools: [ToolDefinition]?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var stream: Bool?
    public var stopSequences: [String]?

    public init(
        model: String,
        maxTokens: Int,
        messages: [Message],
        system: SystemPrompt? = nil,
        tools: [ToolDefinition]? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        stream: Bool? = nil,
        stopSequences: [String]? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.messages = messages
        self.system = system
        self.tools = tools
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.stream = stream
        self.stopSequences = stopSequences
    }

    public var isStreaming: Bool { stream == true }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages, system, tools, temperature
        case topP = "top_p"
        case topK = "top_k"
        case stream
        case stopSequences = "stop_sequences"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        messages = try container.decode([Message].self, forKey: .messages)
        tools = try container.decodeIfPresent([ToolDefinition].self, forKey: .tools)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        topK = try container.decodeIfPresent(Int.self, forKey: .topK)
        stream = try container.decodeIfPresent(Bool.self, forKey: .stream)
        stopSequences = try container.decodeIfPresent([String].self, forKey: .stopSequences)

        if container.contains(.system) {
            if let text = try? container.decode(String.self, forKey: .system) {
                system = .text(text)
            } else if let blocks = try? container.decode([ContentBlock].self, forKey: .system) {
                system = .blocks(blocks)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .system,
                    in: container,
                    debugDescription: "system must be a string or content block array"
                )
            }
        } else {
            system = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(stream, forKey: .stream)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)

        switch system {
        case .text(let text):
            try container.encode(text, forKey: .system)
        case .blocks(let blocks):
            try container.encode(blocks, forKey: .system)
        case .none:
            break
        }
    }
}

public struct CacheBreakpoint: Codable, Sendable, Equatable {
    public var position: String
    public var tokens: Int
    public var ttl: String
    public var type: String
    public var writePrice: Double
    public var readSavings: Double
    public var timestamp: Date

    public init(
        position: String,
        tokens: Int,
        ttl: String,
        type: String,
        writePrice: Double,
        readSavings: Double,
        timestamp: Date = Date()
    ) {
        self.position = position
        self.tokens = tokens
        self.ttl = ttl
        self.type = type
        self.writePrice = writePrice
        self.readSavings = readSavings
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case position, tokens, ttl, type
        case writePrice = "write_price"
        case readSavings = "read_savings"
        case timestamp
    }
}

public struct ROIMetrics: Codable, Sendable, Equatable {
    public var baseInputCost: Double
    public var cacheWriteCost: Double
    public var cacheReadCost: Double
    public var firstRequestCost: Double
    public var subsequentSavings: Double
    public var breakEvenRequests: Int
    public var savingsAt10Requests: Double
    public var savingsAt100Requests: Double
    public var percentSavings: Double

    public static let zero = ROIMetrics(
        baseInputCost: 0,
        cacheWriteCost: 0,
        cacheReadCost: 0,
        firstRequestCost: 0,
        subsequentSavings: 0,
        breakEvenRequests: -1,
        savingsAt10Requests: 0,
        savingsAt100Requests: 0,
        percentSavings: 0
    )

    enum CodingKeys: String, CodingKey {
        case baseInputCost = "base_input_cost"
        case cacheWriteCost = "cache_write_cost"
        case cacheReadCost = "cache_read_cost"
        case firstRequestCost = "first_request_cost"
        case subsequentSavings = "subsequent_savings"
        case breakEvenRequests = "break_even_requests"
        case savingsAt10Requests = "savings_at_10_requests"
        case savingsAt100Requests = "savings_at_100_requests"
        case percentSavings = "percent_savings"
    }
}

public struct CacheMetadata: Codable, Sendable, Equatable {
    public var cacheInjected: Bool
    public var totalTokens: Int
    public var cachedTokens: Int
    public var cacheRatio: Double
    public var breakpoints: [CacheBreakpoint]
    public var roi: ROIMetrics
    public var strategy: String
    public var model: String
    public var timestamp: Date

    public init(
        cacheInjected: Bool,
        totalTokens: Int,
        cachedTokens: Int,
        cacheRatio: Double,
        breakpoints: [CacheBreakpoint],
        roi: ROIMetrics,
        strategy: String,
        model: String,
        timestamp: Date = Date()
    ) {
        self.cacheInjected = cacheInjected
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.cacheRatio = cacheRatio
        self.breakpoints = breakpoints
        self.roi = roi
        self.strategy = strategy
        self.model = model
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case cacheInjected = "cache_injected"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
        case cacheRatio = "cache_ratio"
        case breakpoints, roi, strategy, model, timestamp
    }

    /// Compact breakpoint summary for `X-Autocache-Breakpoints`.
    public var breakpointsHeader: String {
        breakpoints.map { "\($0.position):\($0.tokens):\($0.ttl)" }.joined(separator: ",")
    }
}

public enum CacheStrategy: String, Sendable, Codable, CaseIterable {
    case conservative
    case moderate
    case aggressive
}

public struct StrategyConfig: Sendable, Equatable {
    public var maxBreakpoints: Int
    public var minTokensMultiplier: Double
    public var systemTTL: String
    public var toolsTTL: String
    public var contentTTL: String
    public var priority: [String]

    public static func config(for strategy: CacheStrategy) -> StrategyConfig {
        switch strategy {
        case .conservative:
            StrategyConfig(
                maxBreakpoints: 2,
                minTokensMultiplier: 2.0,
                systemTTL: "1h",
                toolsTTL: "1h",
                contentTTL: "5m",
                priority: ["system", "tools"]
            )
        case .moderate:
            StrategyConfig(
                maxBreakpoints: 3,
                minTokensMultiplier: 1.0,
                systemTTL: "1h",
                toolsTTL: "1h",
                contentTTL: "5m",
                priority: ["system", "tools", "content"]
            )
        case .aggressive:
            StrategyConfig(
                maxBreakpoints: 4,
                minTokensMultiplier: 0.8,
                systemTTL: "1h",
                toolsTTL: "1h",
                contentTTL: "5m",
                priority: ["system", "tools", "content", "large_content"]
            )
        }
    }
}
