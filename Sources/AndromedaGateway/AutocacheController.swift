import AndromedaAutoCache
import AndromedaCore
import Foundation
import Logging
import NIOCore

/// Orchestrates Autocache injection, Anthropic proxying, and savings history.
public struct AutocacheController: Sendable {
    public let config: GatewayConfig
    public let injector: CacheInjector
    public let proxy: AnthropicProxyClient
    public let history: SavingsHistory
    public let logger: Logger
    public let version: String

    public init(
        config: GatewayConfig,
        logger: Logger = Logger(label: "andromeda.gateway.autocache"),
        version: String = AndromedaVersion.string
    ) {
        self.config = config
        let strategy = CacheStrategy(rawValue: config.cacheStrategy) ?? .moderate
        // 🌙 Pass MAX_CACHE_BREAKPOINTS so injector ceiling matches /metrics
        self.injector = CacheInjector(
            strategy: strategy,
            maxBreakpoints: config.maxCacheBreakpoints,
            logger: logger
        )
        self.proxy = AnthropicProxyClient(anthropicURL: config.anthropicURL, logger: logger)
        self.history = SavingsHistory(capacity: config.savingsHistorySize)
        self.logger = logger
        self.version = version
    }

    public func resolveAPIKey(from requestHeaders: [String: String]) -> String? {
        for (key, value) in requestHeaders {
            let lower = key.lowercased()
            if lower == "x-api-key" || lower == "authorization" {
                if lower == "authorization", value.lowercased().hasPrefix("bearer ") {
                    return String(value.dropFirst(7))
                }
                return value
            }
        }
        return config.anthropicAPIKey
    }

    public func processMessages(
        body: Data,
        requestHeaders: [String: String],
        bypass: Bool
    ) async throws -> ProcessedMessagesResponse {
        let decoder = JSONDecoder()
        var request: AnthropicRequest
        do {
            request = try decoder.decode(AnthropicRequest.self, from: body)
        } catch {
            throw AndromedaError.decodingFailed("Invalid JSON in request body")
        }

        try proxy.validate(request)

        guard let apiKey = resolveAPIKey(from: requestHeaders), !apiKey.isEmpty else {
            throw AndromedaError.missingAPIKey
        }

        var metadata: CacheMetadata?
        if !bypass {
            metadata = injector.injectCacheControl(into: &request)
        }

        var forwardHeaders = requestHeaders
        forwardHeaders["x-api-key"] = apiKey
        if forwardHeaders["anthropic-version"] == nil {
            forwardHeaders["anthropic-version"] = "2023-06-01"
        }

        // 🌊 Stream SSE when client asked for stream:true — never buffer the whole show
        if request.isStreaming {
            let upstream = try await proxy.forwardMessagesStreaming(request, headers: forwardHeaders)
            if let metadata {
                await history.record(metadata)
            }
            return ProcessedMessagesResponse(
                statusCode: upstream.statusCode,
                headers: upstream.headers,
                body: .stream(upstream.body),
                metadata: metadata,
                bypassed: bypass
            )
        }

        let upstream = try await proxy.forwardMessages(request, headers: forwardHeaders)
        if let metadata {
            await history.record(metadata)
        }

        return ProcessedMessagesResponse(
            statusCode: upstream.statusCode,
            headers: upstream.headers,
            body: .data(upstream.body),
            metadata: metadata,
            bypassed: bypass
        )
    }

    public func healthPayload() -> [String: String] {
        [
            "status": "healthy",
            "version": version,
            "strategy": config.cacheStrategy,
            "surface": "autocache",
        ]
    }

    public func metricsPayload() -> [String: Any] {
        [
            "supported_models": injector.pricingCalculator.supportedModels(),
            "strategies": CacheStrategy.allCases.map(\.rawValue),
            "cache_limits": [
                "max_breakpoints": config.maxCacheBreakpoints,
                "min_tokens_default": 1024,
                "min_tokens_haiku": 2048,
                "ttl_options": ["5m", "1h"],
            ],
            "tokenizer": [
                "mode": "heuristic",
            ],
            "gateway": [
                "product": AndromedaVersion.productName,
                "version": version,
            ],
        ]
    }

    public func savingsPayload() async -> [String: Any] {
        let recent = await history.snapshot()
        let aggregates = await history.aggregatedStats()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let recentJSON: Any
        if let data = try? encoder.encode(recent),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            recentJSON = object
        } else {
            recentJSON = []
        }

        return [
            "recent_requests": recentJSON,
            "aggregated_stats": [
                "total_requests": aggregates.totalRequests,
                "requests_with_cache": aggregates.requestsWithCache,
                "total_tokens_processed": aggregates.totalTokensProcessed,
                "total_tokens_cached": aggregates.totalTokensCached,
                "average_cache_ratio": aggregates.averageCacheRatio,
                "total_savings_after_10_reqs": aggregates.totalSavingsAfter10Reqs,
                "total_savings_after_100_reqs": aggregates.totalSavingsAfter100Reqs,
            ],
            "debug_info": [
                "breakpoints_by_type": aggregates.breakpointsByType,
                "average_tokens_by_type": aggregates.averageTokensByType,
            ],
            "config": [
                "history_size": config.savingsHistorySize,
                "strategy": config.cacheStrategy,
            ],
        ]
    }
}

/// 🎭 Upstream body — buffered JSON or live SSE ByteBuffer stream.
public enum ProcessedUpstreamBody: Sendable {
    case data(Data)
    case stream(AsyncThrowingStream<ByteBuffer, Error>)
}

public struct ProcessedMessagesResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: ProcessedUpstreamBody
    public var metadata: CacheMetadata?
    public var bypassed: Bool

    /// Legacy convenience for buffered responses (tests / non-stream path).
    public var upstream: UpstreamResponse {
        switch body {
        case .data(let data):
            return UpstreamResponse(statusCode: statusCode, headers: headers, body: data)
        case .stream:
            return UpstreamResponse(statusCode: statusCode, headers: headers, body: Data())
        }
    }
}
