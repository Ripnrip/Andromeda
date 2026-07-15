import Foundation
import Logging

/// Potential cache breakpoint before selection.
struct CacheCandidate: Sendable {
    var position: String
    var tokens: Int
    var contentType: String
    var ttl: String
    var roiScore: Double
    var writeCost: Double
    var readSavings: Double
    var breakEven: Int
    var target: CacheTarget
}

enum CacheTarget: Sendable {
    case systemBlocks
    case tools
    case messageBlock(messageIndex: Int, blockIndex: Int)
}

/// Intelligent Anthropic `cache_control` injector ported from montevive/autocache.
///
/// Collects candidates in deterministic order (system → tools → messages),
/// respects strategy breakpoint limits, and returns ROI metadata.
public struct CacheInjector: Sendable {
    private let tokenizer: HeuristicTokenizer
    private let pricing: PricingCalculator
    private let strategy: CacheStrategy
    /// 🌙 Operator ceiling from `MAX_CACHE_BREAKPOINTS` / GatewayConfig — never exceed this.
    private let maxBreakpointsLimit: Int
    private let logger: Logger

    public init(
        strategy: CacheStrategy = .moderate,
        maxBreakpoints: Int = 4,
        tokenizer: HeuristicTokenizer = HeuristicTokenizer(),
        pricing: PricingCalculator = PricingCalculator(),
        logger: Logger = Logger(label: "andromeda.autocache")
    ) {
        self.tokenizer = tokenizer
        self.pricing = pricing
        self.strategy = strategy
        self.maxBreakpointsLimit = max(1, min(4, maxBreakpoints))
        self.logger = logger
    }

    public var pricingCalculator: PricingCalculator { pricing }

    /// Mutates `request` by injecting optimal `cache_control` breakpoints.
    public func injectCacheControl(into request: inout AnthropicRequest) -> CacheMetadata {
        let strategyConfig = StrategyConfig.config(for: strategy)
        let minimumTokens = tokenizer.modelMinimumTokens(for: request.model)
        let adjustedMinimum = Int(Double(minimumTokens) * strategyConfig.minTokensMultiplier)

        var candidates = collectCandidates(
            from: &request,
            minTokens: adjustedMinimum,
            strategyConfig: strategyConfig
        )

        // ✨ Honor both strategy default and operator MAX_CACHE_BREAKPOINTS ceiling
        let maxBreakpoints = min(strategyConfig.maxBreakpoints, maxBreakpointsLimit)
        if candidates.count > maxBreakpoints {
            candidates = Array(candidates.prefix(maxBreakpoints))
        }

        let breakpoints = applyCacheControl(candidates: candidates, to: &request)
        return calculateMetadata(request: request, breakpoints: breakpoints)
    }

    private func collectCandidates(
        from request: inout AnthropicRequest,
        minTokens: Int,
        strategyConfig: StrategyConfig
    ) -> [CacheCandidate] {
        var candidates: [CacheCandidate] = []

        switch request.system {
        case .text(let text) where !text.isEmpty:
            let tokens = tokenizer.countSystemTokens(text)
            if tokens >= minTokens {
                request.system = .blocks([ContentBlock(type: "text", text: text)])
                candidates.append(
                    makeCandidate(
                        position: "system",
                        tokens: tokens,
                        contentType: "system",
                        ttl: strategyConfig.systemTTL,
                        model: request.model,
                        target: .systemBlocks
                    )
                )
            }
        case .blocks(let blocks) where !blocks.isEmpty:
            let tokens = tokenizer.countSystemBlocksTokens(blocks)
            if tokens >= minTokens {
                candidates.append(
                    makeCandidate(
                        position: "system_blocks",
                        tokens: tokens,
                        contentType: "system",
                        ttl: strategyConfig.systemTTL,
                        model: request.model,
                        target: .systemBlocks
                    )
                )
            }
        default:
            break
        }

        if let tools = request.tools, !tools.isEmpty {
            let totalToolTokens = tools.reduce(0) { $0 + tokenizer.countToolTokens($1) }
            if totalToolTokens >= minTokens {
                candidates.append(
                    makeCandidate(
                        position: "tools",
                        tokens: totalToolTokens,
                        contentType: "tools",
                        ttl: strategyConfig.toolsTTL,
                        model: request.model,
                        target: .tools
                    )
                )
            }
        }

        for (msgIdx, message) in request.messages.enumerated() {
            for (blockIdx, block) in message.content.enumerated()
            where block.type == "text" && !(block.text ?? "").isEmpty {
                let text = block.text ?? ""
                let tokens = tokenizer.countTokens(text)
                if tokens >= minTokens {
                    let ttl = determineTTL(for: text, strategyConfig: strategyConfig)
                    candidates.append(
                        makeCandidate(
                            position: "message_\(msgIdx)_block_\(blockIdx)",
                            tokens: tokens,
                            contentType: "content",
                            ttl: ttl,
                            model: request.model,
                            target: .messageBlock(messageIndex: msgIdx, blockIndex: blockIdx)
                        )
                    )
                }
            }
        }

        return candidates
    }

    private func makeCandidate(
        position: String,
        tokens: Int,
        contentType: String,
        ttl: String,
        model: String,
        target: CacheTarget
    ) -> CacheCandidate {
        let estimate = pricing.estimateBreakpointROI(model: model, tokens: tokens, ttl: ttl)
        let score = roiScore(
            tokens: tokens,
            writeCost: estimate.writeCost,
            readSavings: estimate.readSavings,
            breakEven: estimate.breakEven,
            contentType: contentType
        )
        return CacheCandidate(
            position: position,
            tokens: tokens,
            contentType: contentType,
            ttl: ttl,
            roiScore: score,
            writeCost: estimate.writeCost,
            readSavings: estimate.readSavings,
            breakEven: estimate.breakEven,
            target: target
        )
    }

    private func roiScore(
        tokens: Int,
        writeCost: Double,
        readSavings: Double,
        breakEven: Int,
        contentType: String
    ) -> Double {
        _ = writeCost
        var score = readSavings * 100
        if tokens > 2048 { score *= 1.2 }
        if tokens > 5000 { score *= 1.3 }
        switch contentType {
        case "system": score *= 2.0
        case "tools": score *= 1.5
        case "content":
            if breakEven <= 2 { score *= 1.3 }
            else if breakEven <= 5 { score *= 1.1 }
        default: break
        }
        if breakEven > 20 { score *= 0.2 }
        else if breakEven > 10 { score *= 0.5 }
        return score
    }

    private func determineTTL(for text: String, strategyConfig: StrategyConfig) -> String {
        let patterns = [
            "You are", "Your role", "Instructions:", "Guidelines:",
            "System:", "Context:", "Background:", "Reference:",
        ]
        if text.count > 1000 {
            let lower = text.lowercased()
            for pattern in patterns where lower.contains(pattern.lowercased()) {
                return "1h"
            }
        }
        return strategyConfig.contentTTL
    }

    private func applyCacheControl(
        candidates: [CacheCandidate],
        to request: inout AnthropicRequest
    ) -> [CacheBreakpoint] {
        var breakpoints: [CacheBreakpoint] = []
        for candidate in candidates {
            let control = CacheControl(ttl: candidate.ttl)
            let applied: Bool
            switch candidate.target {
            case .systemBlocks:
                if case .blocks(var blocks) = request.system, !blocks.isEmpty {
                    blocks[blocks.count - 1].cacheControl = control
                    request.system = .blocks(blocks)
                    applied = true
                } else {
                    applied = false
                }
            case .tools:
                if var tools = request.tools, !tools.isEmpty {
                    tools[tools.count - 1].cacheControl = control
                    request.tools = tools
                    applied = true
                } else {
                    applied = false
                }
            case .messageBlock(let messageIndex, let blockIndex):
                guard request.messages.indices.contains(messageIndex),
                      request.messages[messageIndex].content.indices.contains(blockIndex)
                else {
                    applied = false
                    break
                }
                request.messages[messageIndex].content[blockIndex].cacheControl = control
                applied = true
            }

            if applied {
                breakpoints.append(
                    CacheBreakpoint(
                        position: candidate.position,
                        tokens: candidate.tokens,
                        ttl: candidate.ttl,
                        type: candidate.contentType,
                        writePrice: candidate.writeCost,
                        readSavings: candidate.readSavings
                    )
                )
            }
        }
        return breakpoints
    }

    private func calculateMetadata(
        request: AnthropicRequest,
        breakpoints: [CacheBreakpoint]
    ) -> CacheMetadata {
        let totalTokens = tokenizer.estimateRequestTokens(request)
        let cachedTokens = breakpoints.reduce(0) { $0 + $1.tokens }
        let cacheRatio = totalTokens > 0 ? Double(cachedTokens) / Double(totalTokens) : 0
        let roi = pricing.calculateROI(
            model: request.model,
            totalTokens: totalTokens,
            cachedTokens: cachedTokens,
            breakpoints: breakpoints
        )
        return CacheMetadata(
            cacheInjected: !breakpoints.isEmpty,
            totalTokens: totalTokens,
            cachedTokens: cachedTokens,
            cacheRatio: cacheRatio,
            breakpoints: breakpoints,
            roi: roi,
            strategy: strategy.rawValue,
            model: request.model
        )
    }
}
