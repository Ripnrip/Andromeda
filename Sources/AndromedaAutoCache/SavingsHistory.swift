import Foundation

/// Thread-safe ring buffer of recent Autocache decisions for `/savings`.
public actor SavingsHistory {
    private var entries: [CacheMetadata] = []
    private let capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = max(0, capacity)
    }

    public func record(_ metadata: CacheMetadata) {
        guard capacity > 0 else { return }
        entries.append(metadata)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func snapshot() -> [CacheMetadata] { entries }

    public func aggregatedStats() -> SavingsAggregates {
        var requestsWithCache = 0
        var totalTokensProcessed = 0
        var totalTokensCached = 0
        var totalSavingsAt10 = 0.0
        var totalSavingsAt100 = 0.0
        var breakpointsByType: [String: Int] = ["system": 0, "tools": 0, "content": 0]
        var tokensByType: [String: [Int]] = ["system": [], "tools": [], "content": []]

        for meta in entries {
            totalTokensProcessed += meta.totalTokens
            totalTokensCached += meta.cachedTokens
            if meta.cacheInjected {
                requestsWithCache += 1
                totalSavingsAt10 += meta.roi.savingsAt10Requests
                totalSavingsAt100 += meta.roi.savingsAt100Requests
            }
            for bp in meta.breakpoints {
                breakpointsByType[bp.type, default: 0] += 1
                tokensByType[bp.type, default: []].append(bp.tokens)
            }
        }

        let avgCacheRatio = totalTokensProcessed > 0
            ? Double(totalTokensCached) / Double(totalTokensProcessed)
            : 0

        var avgTokensByType: [String: Int] = [:]
        for (type, tokens) in tokensByType {
            avgTokensByType[type] = tokens.isEmpty ? 0 : tokens.reduce(0, +) / tokens.count
        }

        return SavingsAggregates(
            totalRequests: entries.count,
            requestsWithCache: requestsWithCache,
            totalTokensProcessed: totalTokensProcessed,
            totalTokensCached: totalTokensCached,
            averageCacheRatio: avgCacheRatio,
            totalSavingsAfter10Reqs: PricingCalculator.formatCost(totalSavingsAt10),
            totalSavingsAfter100Reqs: PricingCalculator.formatCost(totalSavingsAt100),
            breakpointsByType: breakpointsByType,
            averageTokensByType: avgTokensByType
        )
    }
}

public struct SavingsAggregates: Sendable, Equatable {
    public var totalRequests: Int
    public var requestsWithCache: Int
    public var totalTokensProcessed: Int
    public var totalTokensCached: Int
    public var averageCacheRatio: Double
    public var totalSavingsAfter10Reqs: String
    public var totalSavingsAfter100Reqs: String
    public var breakpointsByType: [String: Int]
    public var averageTokensByType: [String: Int]
}
