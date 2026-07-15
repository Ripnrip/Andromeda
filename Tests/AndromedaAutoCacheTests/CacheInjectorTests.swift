import Foundation
import Testing
@testable import AndromedaAutoCache

@Suite("CacheInjector")
struct CacheInjectorTests {
    @Test("injects cache_control on large system prompt with moderate strategy")
    func largeSystemModerate() {
        var request = AnthropicRequest(
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            messages: [Message(role: "user", content: [ContentBlock(type: "text", text: "Hello")])],
            system: .text(
                String(
                    repeating: "You are a helpful assistant with detailed instructions and context. ",
                    count: 100
                )
            )
        )

        let injector = CacheInjector(strategy: .moderate)
        let metadata = injector.injectCacheControl(into: &request)

        #expect(metadata.cacheInjected)
        #expect(metadata.breakpoints.count == 1)
        #expect(metadata.cacheRatio >= 0.5)

        if case .blocks(let blocks) = request.system {
            #expect(blocks.last?.cacheControl?.type == "ephemeral")
            #expect(blocks.last?.cacheControl?.ttl == "1h")
        } else {
            Issue.record("Expected system blocks after injection")
        }
    }

    @Test("skips tiny system prompts under conservative strategy")
    func tinySystemConservative() {
        var request = AnthropicRequest(
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            messages: [Message(role: "user", content: [ContentBlock(type: "text", text: "Hello")])],
            system: .text("You are helpful.")
        )

        let metadata = CacheInjector(strategy: .conservative).injectCacheControl(into: &request)
        #expect(!metadata.cacheInjected)
        #expect(metadata.breakpoints.isEmpty)
    }

    @Test("injects system and tools under aggressive strategy")
    func systemAndToolsAggressive() {
        var request = AnthropicRequest(
            model: "claude-3-5-sonnet-20241022",
            maxTokens: 100,
            messages: [
                Message(role: "user", content: [ContentBlock(type: "text", text: "Calculate 2+2")])
            ],
            system: .text(
                String(repeating: "You are a helpful assistant with detailed instructions. ", count: 100)
            ),
            tools: [
                ToolDefinition(
                    name: "calculator",
                    description: String(repeating: "A tool for calculations. ", count: 50),
                    inputSchema: JSONValue.from([
                        "type": "object",
                        "properties": [
                            "expression": [
                                "type": "string",
                                "description": "Mathematical expression to evaluate",
                            ],
                        ],
                    ] as [String: Any])
                ),
            ]
        )

        let metadata = CacheInjector(strategy: .aggressive).injectCacheControl(into: &request)
        #expect(metadata.cacheInjected)
        #expect(metadata.breakpoints.count == 2)
        #expect(metadata.cacheRatio >= 0.6)
        #expect(request.tools?.last?.cacheControl != nil)
    }

    @Test("haiku models require larger minimum tokens")
    func haikuThreshold() {
        var small = AnthropicRequest(
            model: "claude-3-haiku-20240307",
            maxTokens: 100,
            messages: [Message(role: "user", content: [ContentBlock(type: "text", text: "Help")])],
            system: .text(String(repeating: "Context. ", count: 80))
        )
        let smallMeta = CacheInjector(strategy: .moderate).injectCacheControl(into: &small)
        #expect(!smallMeta.cacheInjected)

        var large = AnthropicRequest(
            model: "claude-3-haiku-20240307",
            maxTokens: 100,
            messages: [Message(role: "user", content: [ContentBlock(type: "text", text: "Help")])],
            system: .text(
                String(
                    repeating: "You are a helpful assistant with very detailed instructions. ",
                    count: 200
                )
            )
        )
        let largeMeta = CacheInjector(strategy: .moderate).injectCacheControl(into: &large)
        #expect(largeMeta.cacheInjected)
        #expect(largeMeta.breakpoints.count == 1)
    }

    @Test("decodes string system and string message content")
    func flexibleDecoding() throws {
        let json = """
        {
          "model": "claude-3-5-sonnet-20241022",
          "max_tokens": 32,
          "system": "You are helpful.",
          "messages": [{"role": "user", "content": "Hi"}]
        }
        """.data(using: .utf8)!

        let request = try JSONDecoder().decode(AnthropicRequest.self, from: json)
        #expect(request.system == .text("You are helpful."))
        #expect(request.messages.first?.content.first?.text == "Hi")
    }

    @Test("ROI headers include injected and ratio fields")
    func metadataHeaders() {
        let metadata = CacheMetadata(
            cacheInjected: true,
            totalTokens: 2000,
            cachedTokens: 1500,
            cacheRatio: 0.75,
            breakpoints: [
                CacheBreakpoint(
                    position: "system",
                    tokens: 1500,
                    ttl: "1h",
                    type: "system",
                    writePrice: 0.01,
                    readSavings: 0.004
                ),
            ],
            roi: ROIMetrics(
                baseInputCost: 0.006,
                cacheWriteCost: 0.009,
                cacheReadCost: 0.0006,
                firstRequestCost: 0.009,
                subsequentSavings: 0.0054,
                breakEvenRequests: 2,
                savingsAt10Requests: 0.04,
                savingsAt100Requests: 0.5,
                percentSavings: 85.2
            ),
            strategy: "moderate",
            model: "claude-3-5-sonnet-20241022"
        )

        let headers = Dictionary(uniqueKeysWithValues: CacheMetadataHeaders.make(from: metadata).map {
            ($0.name, $0.value)
        })
        #expect(headers[AutocacheHeader.injected] == "true")
        #expect(headers[AutocacheHeader.cacheRatio] == "0.750")
        #expect(headers[AutocacheHeader.breakpoints] == "system:1500:1h")
        #expect(headers[AutocacheHeader.roiPercent] == "85.2")
    }
}
