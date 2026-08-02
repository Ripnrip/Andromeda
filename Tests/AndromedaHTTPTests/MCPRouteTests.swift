import AndromedaHTTP
import AndromedaSecrets
import AndromedaTools
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@Suite("AndromedaHTTP.MCPRoute")
struct MCPRouteTests {
    static let bearerToken = "vm-to-andromeda-token"
    static let githubCanary = "ghp_ROUTECANARY-NO-LEAK"

    actor MockUpstreamHTTP: UpstreamHTTPExecuting {
        private var queuedResponses: [UpstreamHTTPResponse]

        init(responses: [UpstreamHTTPResponse]) {
            self.queuedResponses = responses
        }

        func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
            if queuedResponses.isEmpty {
                return UpstreamHTTPResponse(status: 200, body: Data("{}".utf8))
            }
            return queuedResponses.removeFirst()
        }
    }

    private func makeApp(
        upstreamResponses: [UpstreamHTTPResponse] = [
            UpstreamHTTPResponse(status: 200, body: Data(#"{"login":"Ripnrip"}"#.utf8)),
        ]
    ) throws -> Application<RouterResponder<BasicRequestContext>> {
        let broker = CuratedToolBroker(
            configuration: try ToolsBrokerConfiguration(
                automationAllowed: false,
                github: .init(tokenReference: SecretReference(service: "andromeda.github", account: "token")),
                slack: .init(tokenReference: SecretReference(service: "andromeda.slack", account: "token"))
            ),
            secrets: InMemorySecretProvider(values: [
                SecretReference(service: "andromeda.github", account: "token"): Self.githubCanary,
            ]),
            http: MockUpstreamHTTP(responses: upstreamResponses)
        )
        let router = Router(context: BasicRequestContext.self)
        MCPRoute(
            broker: broker,
            auth: MCPBearerAuth(token: Self.bearerToken),
            serverVersion: "test-m4"
        ).register(on: router)
        return Application(router: router)
    }

    private func rpcBody(_ method: String, id: Int = 1, params: [String: JSONValue]? = nil) throws -> ByteBuffer {
        var envelope: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
        ]
        if let params {
            envelope["params"] = .object(params)
        }
        return ByteBuffer(data: try JSONEncoder().encode(JSONValue.object(envelope)))
    }

    private func decodeRPC(_ body: ByteBuffer) throws -> [String: JSONValue] {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(body.readableBytesView))
        guard case let .object(object) = value else {
            Issue.record("expected JSON-RPC object, got \(value)")
            return [:]
        }
        return object
    }

    @Test("initialize negotiates protocol and advertises server info")
    func initialize() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: rpcBody("initialize", params: ["protocolVersion": .string("2024-11-05")])
            ) { response in
                #expect(response.status == .ok)
                let rpc = try decodeRPC(response.body)
                guard case let .object(result)? = rpc["result"] else {
                    Issue.record("missing result")
                    return
                }
                #expect(result["protocolVersion"]?.stringValue == MCPRoute.protocolVersion)
                guard case let .object(serverInfo)? = result["serverInfo"] else {
                    Issue.record("missing serverInfo")
                    return
                }
                #expect(serverInfo["name"]?.stringValue == "andromeda")
                #expect(serverInfo["version"]?.stringValue == "test-m4")
            }
        }
    }

    @Test("tools/list returns only the curated surface")
    func toolsList() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: rpcBody("tools/list")
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("andromeda_github_get_me"))
                #expect(body.contains("andromeda_slack_request"))
                #expect(!body.contains(Self.githubCanary))
            }
        }
    }

    @Test("tools/call round-trips through the broker with host-side auth")
    func toolsCall() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: rpcBody("tools/call", params: [
                    "name": .string("andromeda_github_get_me"),
                    "arguments": .object([:]),
                ])
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("Ripnrip"))
                #expect(body.contains(#""isError":false"#))
                #expect(!body.contains(Self.githubCanary))
            }
        }
    }

    @Test("missing bearer token is rejected with 401")
    func missingToken() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: rpcBody("tools/list")
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("wrong bearer token is rejected with 401")
    func wrongToken() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer not-the-token",
                ],
                body: rpcBody("tools/list")
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("unknown methods return JSON-RPC -32601")
    func unknownMethod() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: rpcBody("resources/list")
            ) { response in
                #expect(response.status == .ok)
                let rpc = try decodeRPC(response.body)
                guard case let .object(error)? = rpc["error"] else {
                    Issue.record("expected error object")
                    return
                }
                #expect(error["code"] == .number(-32601))
            }
        }
    }

    @Test("notifications are accepted without a response body")
    func notificationAccepted() async throws {
        let notification = ByteBuffer(data: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: notification
            ) { response in
                #expect(response.status == .accepted)
            }
        }
    }

    @Test("malformed JSON returns JSON-RPC -32700 parse error")
    func parseError() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer \(Self.bearerToken)",
                ],
                body: ByteBuffer(string: "{not json")
            ) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("-32700"))
            }
        }
    }
}
