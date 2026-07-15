import Foundation

/// Anthropic model pricing used for Autocache ROI analytics.
public struct ModelPricing: Sendable, Equatable {
    public var modelName: String
    public var inputTokens: Double
    public var outputTokens: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    public var cacheRead: Double
}

/// Calculates cache write/read costs and break-even ROI.
///
/// - Purpose: Honest savings measurement for Autocache breakpoints.
/// - Concurrency: immutable after init; `Sendable`.
public struct PricingCalculator: Sendable {
    private let models: [String: ModelPricing]

    public init(models: [String: ModelPricing]? = nil) {
        self.models = models ?? Self.defaultModels
    }

    public func pricing(for model: String) -> ModelPricing {
        if let exact = models[model] { return exact }
        if model.contains("haiku") {
            return models["claude-3-5-haiku-20241022"]
                ?? Self.defaultModels["claude-3-5-haiku-20241022"]!
        }
        if model.contains("opus") {
            return models["claude-opus-4-20250514"]
                ?? Self.defaultModels["claude-opus-4-20250514"]!
        }
        return models["claude-3-5-sonnet-20241022"]
            ?? Self.defaultModels["claude-3-5-sonnet-20241022"]!
    }

    public func supportedModels() -> [String] {
        Array(models.keys).sorted()
    }

    public func baseCost(model: String, inputTokens: Int, outputTokens: Int = 0) -> Double {
        let pricing = pricing(for: model)
        let input = (Double(inputTokens) / 1_000_000) * pricing.inputTokens
        let output = (Double(outputTokens) / 1_000_000) * pricing.outputTokens
        return input + output
    }

    public func cacheWriteCost(model: String, tokens: Int, ttl: String) -> Double {
        let pricing = pricing(for: model)
        let rate = ttl == "1h" ? pricing.cacheWrite1h : pricing.cacheWrite5m
        return (Double(tokens) / 1_000_000) * rate
    }

    public func cacheReadCost(model: String, tokens: Int) -> Double {
        let pricing = pricing(for: model)
        return (Double(tokens) / 1_000_000) * pricing.cacheRead
    }

    public func estimateBreakpointROI(
        model: String,
        tokens: Int,
        ttl: String
    ) -> (writeCost: Double, readSavings: Double, breakEven: Int) {
        let base = baseCost(model: model, inputTokens: tokens)
        let write = cacheWriteCost(model: model, tokens: tokens, ttl: ttl)
        let read = cacheReadCost(model: model, tokens: tokens)
        let savingsPerRead = base - read
        let extraCost = write - base
        let breakEven: Int
        if savingsPerRead > 0 {
            let readsNeeded = Int(ceil(extraCost / savingsPerRead))
            breakEven = 1 + readsNeeded
        } else {
            breakEven = -1
        }
        return (write, savingsPerRead, breakEven)
    }

    public func calculateROI(
        model: String,
        totalTokens: Int,
        cachedTokens: Int,
        breakpoints: [CacheBreakpoint]
    ) -> ROIMetrics {
        let pricing = pricing(for: model)
        let baseCost = (Double(totalTokens) / 1_000_000) * pricing.inputTokens
        let totalCacheWriteCost = breakpoints.reduce(0.0) { partial, bp in
            partial + cacheWriteCost(model: model, tokens: bp.tokens, ttl: bp.ttl)
        }
        let cacheRead = cacheReadCost(model: model, tokens: cachedTokens)
        let nonCachedTokens = max(totalTokens - cachedTokens, 0)
        let nonCachedCost = (Double(nonCachedTokens) / 1_000_000) * pricing.inputTokens
        let firstRequestCost = totalCacheWriteCost + nonCachedCost
        let subsequentRequestCost = cacheRead + nonCachedCost
        let subsequentSavings = baseCost - subsequentRequestCost

        let breakEven: Int
        if subsequentSavings > 0 {
            let extraCost = firstRequestCost - baseCost
            breakEven = Int(extraCost / subsequentSavings) + 1
        } else {
            breakEven = -1
        }

        let percentSavings = baseCost > 0 ? (subsequentSavings / baseCost) * 100 : 0
        return ROIMetrics(
            baseInputCost: baseCost,
            cacheWriteCost: totalCacheWriteCost,
            cacheReadCost: cacheRead,
            firstRequestCost: firstRequestCost,
            subsequentSavings: subsequentSavings,
            breakEvenRequests: breakEven,
            savingsAt10Requests: savingsAtN(
                baseCost: baseCost,
                firstRequestCost: firstRequestCost,
                subsequentRequestCost: subsequentRequestCost,
                n: 10
            ),
            savingsAt100Requests: savingsAtN(
                baseCost: baseCost,
                firstRequestCost: firstRequestCost,
                subsequentRequestCost: subsequentRequestCost,
                n: 100
            ),
            percentSavings: percentSavings
        )
    }

    public static func formatCost(_ cost: Double) -> String {
        if cost < 0.001 { return String(format: "$%.6f", cost) }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        if cost < 1.0 { return String(format: "$%.3f", cost) }
        return String(format: "$%.2f", cost)
    }

    private func savingsAtN(
        baseCost: Double,
        firstRequestCost: Double,
        subsequentRequestCost: Double,
        n: Int
    ) -> Double {
        guard n > 0 else { return 0 }
        let without = baseCost * Double(n)
        let with = firstRequestCost + (subsequentRequestCost * Double(n - 1))
        return without - with
    }

    private static let defaultModels: [String: ModelPricing] = [
        "claude-sonnet-4-5-20250929": .init(
            modelName: "claude-sonnet-4-5-20250929",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-sonnet-4-20250514": .init(
            modelName: "claude-sonnet-4-20250514",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-3-7-sonnet-20250219": .init(
            modelName: "claude-3-7-sonnet-20250219",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-3-5-sonnet-20241022": .init(
            modelName: "claude-3-5-sonnet-20241022",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-3-5-sonnet-20240620": .init(
            modelName: "claude-3-5-sonnet-20240620",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-opus-4-1-20250805": .init(
            modelName: "claude-opus-4-1-20250805",
            inputTokens: 15, outputTokens: 75,
            cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50
        ),
        "claude-opus-4-20250514": .init(
            modelName: "claude-opus-4-20250514",
            inputTokens: 15, outputTokens: 75,
            cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50
        ),
        "claude-opus-4-5-20251101": .init(
            modelName: "claude-opus-4-5-20251101",
            inputTokens: 15, outputTokens: 75,
            cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50
        ),
        "claude-3-5-haiku-20241022": .init(
            modelName: "claude-3-5-haiku-20241022",
            inputTokens: 0.80, outputTokens: 4,
            cacheWrite5m: 1.00, cacheWrite1h: 1.60, cacheRead: 0.08
        ),
        "claude-3-opus-20240229": .init(
            modelName: "claude-3-opus-20240229",
            inputTokens: 15, outputTokens: 75,
            cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50
        ),
        "claude-3-sonnet-20240229": .init(
            modelName: "claude-3-sonnet-20240229",
            inputTokens: 3, outputTokens: 15,
            cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30
        ),
        "claude-3-haiku-20240307": .init(
            modelName: "claude-3-haiku-20240307",
            inputTokens: 0.25, outputTokens: 1.25,
            cacheWrite5m: 0.3125, cacheWrite1h: 0.50, cacheRead: 0.025
        ),
    ]
}
