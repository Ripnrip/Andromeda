import AndromedaAutoCache
import AndromedaCore
import AndromedaMCP
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing
@testable import AndromedaGateway

@Suite("GatewayMCPRoutes")
struct GatewayMCPRoutesTests {
    @Test("MCP health reports shim surface")
    func mcpHealth() async throws {
        let vault = SecretVault(secrets: [
            .slackProxy: "xoxb-test",
            .githubProxy: "ghp_test",
        ])
        let hub = MCPShimHub.makeDefault(vault: vault, brokerToken: "broker-test")
        let controller = AutocacheController(config: .default)
        let app = Application(router: GatewayRouter(controller: controller, mcpHub: hub).build())

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/mcp/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("mcp_shim"))
                #expect(body.contains("slack_proxy"))
                #expect(body.contains("github_proxy"))
            }
        }
    }

    @Test("MCP tools/call over HTTP requires broker token and forwards")
    func mcpToolCallHTTP() async throws {
        let vault = SecretVault(secrets: [.githubProxy: "ghp_test"])
        let hub = MCPShimHub.makeDefault(vault: vault, brokerToken: "broker-test")
        let controller = AutocacheController(config: .default)
        let app = Application(router: GatewayRouter(controller: controller, mcpHub: hub).build())

        let payload = """
        {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_issues","arguments":{"owner":"acme"}}}
        """

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/mcp",
                method: .post,
                headers: [.authorization: "Bearer broker-test"],
                body: ByteBuffer(string: payload)
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("list_issues") || body.contains("ok:github_proxy") || body.contains("result"))
                #expect(!body.contains("ghp_test"))
            }

            try await client.execute(
                uri: "/v1/mcp",
                method: .post,
                body: ByteBuffer(string: payload)
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("unauthorized") || body.contains("-32001"))
            }
        }
    }
}
