import AndromedaCore
import Foundation
import Testing
@testable import AndromedaMCP

@Suite("MCPShimHub")
struct MCPShimHubTests {
    /// Guest can list only allowlisted tools when host secrets + broker token are present.
    @Test("tools/list returns allowlisted tools and requires broker auth")
    func listToolsAuthorized() async throws {
        let vault = SecretVault(secrets: [
            .slackProxy: "xoxb-test-slack-secret",
            .githubProxy: "ghp_test_github_secret",
        ])
        let hub = makeHub(vault: vault, broker: "broker-secret")

        let denied = await hub.handle(
            request: MCPJSONRPCRequest(id: .number(1), method: "tools/list"),
            authorizationHeader: nil
        )
        #expect(denied.error?.code == MCPShimError.unauthorized.code)

        let ok = await hub.handle(
            request: MCPJSONRPCRequest(id: .number(2), method: "tools/list"),
            authorizationHeader: "Bearer broker-secret"
        )
        #expect(ok.error == nil)
        let result = ok.result?.value as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]] ?? []
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names.contains("slack_post_message"))
        #expect(names.contains("create_issue"))
        #expect(!names.contains("totally_unknown_tool"))
    }

    /// Host forwards an allowlisted call; response is scrubbed of upstream secrets.
    @Test("tools/call forwards allowlisted tool and scrubs secrets")
    func callToolScrubsSecrets() async throws {
        let slackSecret = "xoxb-should-never-leak"
        let vault = SecretVault(secrets: [
            .slackProxy: slackSecret,
            .githubProxy: "ghp_also-secret",
        ])
        let slack = MockUpstreamMCPProvider(
            capability: .slackProxy,
            tools: [
                MCPToolDescriptor(name: "slack_post_message", description: "post"),
            ],
            responses: [
                "slack_post_message": .text("posted with \(slackSecret) in body"),
            ],
            authPresent: true
        )
        let hub = MCPShimHub(
            vault: vault,
            providers: [.slackProxy: slack],
            brokerToken: "broker-secret"
        )

        let response = await hub.handle(
            request: MCPJSONRPCRequest(
                id: .string("call-1"),
                method: "tools/call",
                params: [
                    "name": AnyCodable("slack_post_message"),
                    "arguments": AnyCodable(["channel": "C123", "text": "hi"]),
                ]
            ),
            authorizationHeader: "Bearer broker-secret"
        )
        #expect(response.error == nil)
        let encoded = try JSONEncoder().encode(response)
        let text = String(data: encoded, encoding: .utf8) ?? ""
        #expect(!text.contains(slackSecret))
        #expect(text.contains("[REDACTED]") || text.contains("posted with"))
        #expect(!SecretScrubber(vault: vault).containsSecret(text) || text.contains("[REDACTED]"))
    }

    @Test("tools/call denies tools outside allowlist")
    func denyUnknownTool() async throws {
        let vault = SecretVault(secrets: [.githubProxy: "ghp_test"])
        let hub = makeHub(vault: vault, broker: "broker-secret")
        let response = await hub.handle(
            request: MCPJSONRPCRequest(
                id: .number(9),
                method: "tools/call",
                params: ["name": AnyCodable("rm_rf_production")]
            ),
            authorizationHeader: "Bearer broker-secret"
        )
        #expect(response.error?.code == MCPShimError.toolNotAllowed("x").code)
    }

    @Test("missing host secret marks capability unavailable")
    func missingHostSecret() async throws {
        let vault = SecretVault(secrets: [:])
        let hub = makeHub(vault: vault, broker: "broker-secret")
        let response = await hub.handle(
            request: MCPJSONRPCRequest(
                id: .number(3),
                method: "tools/call",
                params: ["name": AnyCodable("create_issue")]
            ),
            authorizationHeader: "Bearer broker-secret"
        )
        #expect(response.error?.code == MCPShimError.capabilityUnavailable(.githubProxy).code)
    }

    private func makeHub(vault: SecretVault, broker: String) -> MCPShimHub {
        MCPShimHub.makeDefault(vault: vault, brokerToken: broker)
    }
}

@Suite("GuestMCPConfig")
struct GuestMCPConfigTests {
    @Test("guest mcp.json has no upstream secret markers")
    func noUpstreamSecrets() throws {
        let config = GuestMCPConfig.make(
            gatewayBaseURL: "http://host.tailnet:8080",
            brokerToken: "broker-only",
            includeBrokerTokenInline: false
        )
        let json = try config.renderMCPJSON()
        #expect(json.contains("v1") && json.contains("mcp"))
        #expect(json.contains("ANDROMEDA_BROKER_TOKEN"))
        #expect(!GuestMCPConfig.containsUpstreamSecrets(json))
        #expect(!json.contains("xoxb-"))
        #expect(!json.contains("ghp_"))
        #expect(!json.contains("SLACK_BOT_TOKEN"))
        #expect(!json.contains("GITHUB_TOKEN"))
    }

    @Test("scrubber replaces secret substrings")
    func scrubber() {
        let scrubber = SecretScrubber(secrets: ["super-secret-value"])
        #expect(scrubber.scrub("token=super-secret-value") == "token=[REDACTED]")
        #expect(scrubber.containsSecret("super-secret-value"))
    }
}

@Suite("HostDiagnostics")
struct HostDiagnosticsTests {
    @Test("doctor fails dirty guest config and missing broker")
    func doctorDirtyGuest() {
        let vault = SecretVault(secrets: [.slackProxy: "xoxb-abc"])
        let dirty = #"{ "token": "xoxb-abc" }"#
        let report = HostDiagnostics.doctor(
            vault: vault,
            brokerTokenConfigured: false,
            gatewayReachable: false,
            guestConfigText: dirty,
            menubarAvailable: false
        )
        #expect(report.failedCount >= 2)
        #expect(report.items.contains { $0.id == "guest.mcp" && $0.status == .fail })
        #expect(report.items.contains { $0.id == "broker" && $0.status == .fail })
    }

    @Test("setup plan is idempotent and emits guest endpoint")
    func setupPlan() throws {
        let vault = SecretVault(secrets: [.githubProxy: "ghp_x"])
        let plan = HostDiagnostics.setupPlan(
            vault: vault,
            brokerToken: "broker",
            gatewayBaseURL: "http://127.0.0.1:8080",
            vmDetected: false,
            dryRun: true,
            menubarAvailable: false
        )
        #expect(plan.dryRun)
        #expect(plan.guestConfig.url.hasSuffix("/v1/mcp"))
        let json = try plan.guestConfig.renderMCPJSON()
        #expect(!GuestMCPConfig.containsUpstreamSecrets(json))
        let again = HostDiagnostics.setupPlan(
            vault: vault,
            brokerToken: "broker",
            gatewayBaseURL: "http://127.0.0.1:8080",
            vmDetected: false,
            dryRun: true,
            menubarAvailable: false
        )
        #expect(plan.guestConfig == again.guestConfig)
    }
}

@Suite("ToolAllowlist")
struct ToolAllowlistTests {
    @Test("router maps slack and github tool names")
    func router() {
        #expect(ToolCapabilityRouter.capability(for: "slack_post_message") == .slackProxy)
        #expect(ToolCapabilityRouter.capability(for: "create_pull_request") == .githubProxy)
        #expect(ToolCapabilityRouter.capability(for: "unknown_thing") == nil)
    }
}
