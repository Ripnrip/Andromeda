import Foundation

/// Runtime configuration for the Hummingbird gateway Autocache surface.
///
/// Secrets may arrive via environment; only ports, host, strategy, and feature
/// flags are intended as bounded operational overrides.
public struct GatewayConfig: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var anthropicURL: String
    public var anthropicAPIKey: String?
    public var cacheStrategy: String
    public var enableMetrics: Bool
    public var enableDetailedROI: Bool
    public var maxCacheBreakpoints: Int
    public var savingsHistorySize: Int
    public var logLevel: String

    public static let `default` = GatewayConfig(
        host: "127.0.0.1",
        port: 8080,
        anthropicURL: "https://api.anthropic.com",
        anthropicAPIKey: nil,
        cacheStrategy: "moderate",
        enableMetrics: true,
        enableDetailedROI: true,
        maxCacheBreakpoints: 4,
        savingsHistorySize: 100,
        logLevel: "info"
    )

    public init(
        host: String,
        port: Int,
        anthropicURL: String,
        anthropicAPIKey: String?,
        cacheStrategy: String,
        enableMetrics: Bool,
        enableDetailedROI: Bool,
        maxCacheBreakpoints: Int,
        savingsHistorySize: Int,
        logLevel: String
    ) {
        self.host = host
        self.port = port
        self.anthropicURL = anthropicURL
        self.anthropicAPIKey = anthropicAPIKey
        self.cacheStrategy = cacheStrategy
        self.enableMetrics = enableMetrics
        self.enableDetailedROI = enableDetailedROI
        self.maxCacheBreakpoints = maxCacheBreakpoints
        self.savingsHistorySize = savingsHistorySize
        self.logLevel = logLevel
    }

    /// Loads configuration from process environment with Autocache-compatible keys.
    public static func loadFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> GatewayConfig {
        var config = GatewayConfig.default
        if let host = environment["HOST"], !host.isEmpty { config.host = host }
        if let port = environment["PORT"].flatMap(Int.init) { config.port = port }
        if let url = environment["ANTHROPIC_API_URL"], !url.isEmpty { config.anthropicURL = url }
        if let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty { config.anthropicAPIKey = key }
        if let strategy = environment["CACHE_STRATEGY"], !strategy.isEmpty {
            config.cacheStrategy = strategy
        }
        if let metrics = environment["ENABLE_METRICS"] {
            config.enableMetrics = parseBool(metrics, default: true)
        }
        if let roi = environment["ENABLE_DETAILED_ROI"] {
            config.enableDetailedROI = parseBool(roi, default: true)
        }
        if let maxBP = environment["MAX_CACHE_BREAKPOINTS"].flatMap(Int.init) {
            config.maxCacheBreakpoints = maxBP
        }
        if let history = environment["SAVINGS_HISTORY_SIZE"].flatMap(Int.init) {
            config.savingsHistorySize = history
        }
        if let level = environment["LOG_LEVEL"], !level.isEmpty { config.logLevel = level }
        try config.validate()
        return config
    }

    public func validate() throws {
        guard !host.isEmpty else {
            throw AndromedaError.invalidConfiguration("host cannot be empty")
        }
        guard (1...65535).contains(port) else {
            throw AndromedaError.invalidConfiguration("port must be 1...65535")
        }
        guard !anthropicURL.isEmpty else {
            throw AndromedaError.invalidConfiguration("anthropic URL cannot be empty")
        }
        let strategies: Set<String> = ["conservative", "moderate", "aggressive"]
        guard strategies.contains(cacheStrategy) else {
            throw AndromedaError.invalidConfiguration(
                "invalid cache strategy: \(cacheStrategy)"
            )
        }
        guard (1...4).contains(maxCacheBreakpoints) else {
            throw AndromedaError.invalidConfiguration(
                "max cache breakpoints must be between 1 and 4"
            )
        }
        guard savingsHistorySize >= 0 else {
            throw AndromedaError.invalidConfiguration(
                "savings history size cannot be negative"
            )
        }
    }

    public var serverAddress: String { "\(host):\(port)" }

    public var apiKeyConfigured: Bool {
        !(anthropicAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func parseBool(_ value: String, default defaultValue: Bool) -> Bool {
        switch value.lowercased() {
        case "true", "1", "yes", "on": true
        case "false", "0", "no", "off": false
        default: defaultValue
        }
    }
}
