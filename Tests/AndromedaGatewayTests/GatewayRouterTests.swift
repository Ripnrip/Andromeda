import AndromedaAutoCache
import AndromedaCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import AndromedaGateway

@Suite("GatewayRouter")
struct GatewayRouterTests {
    @Test("health endpoint reports autocache surface")
    func health() async throws {
        let config = GatewayConfig(
            host: "127.0.0.1",
            port: 0,
            anthropicURL: "https://api.anthropic.com",
            anthropicAPIKey: nil,
            cacheStrategy: "moderate",
            enableMetrics: true,
            enableDetailedROI: true,
            maxCacheBreakpoints: 4,
            savingsHistorySize: 10,
            logLevel: "info"
        )
        let controller = AutocacheController(config: config)
        let app = Application(router: GatewayRouter(controller: controller).build())

        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("healthy"))
                #expect(body.contains("autocache"))
                #expect(body.contains("moderate"))
            }
        }
    }

    @Test("messages without API key returns typed autocache error")
    func missingAPIKey() async throws {
        let config = GatewayConfig.default
        let controller = AutocacheController(config: config)
        let app = Application(router: GatewayRouter(controller: controller).build())

        let payload = """
        {"model":"claude-3-5-sonnet-20241022","max_tokens":16,"messages":[{"role":"user","content":"Hi"}]}
        """

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/messages",
                method: .post,
                body: ByteBuffer(string: payload)
            ) { response in
                #expect(response.status == .badRequest)
                let body = String(buffer: response.body)
                #expect(body.contains("autocache_error"))
                #expect(body.contains("missing_api_key"))
            }
        }
    }

    @Test("metrics lists strategies and models")
    func metrics() async throws {
        let controller = AutocacheController(config: .default)
        let app = Application(router: GatewayRouter(controller: controller).build())

        try await app.test(.router) { client in
            try await client.execute(uri: "/metrics", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("moderate"))
                #expect(body.contains("supported_models"))
                #expect(body.contains("heuristic"))
            }
        }
    }
}
