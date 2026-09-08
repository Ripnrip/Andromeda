// AndromedaMCPHub tests — relay round-trips, collisions, notifications,
// cancelled rewriting, config validation, shim naming.
//
// Pure-logic: no real processes, no real sockets (canon: fixtures +
// protocol injection). The hub E2E uses an in-process upstream double.

@testable import AndromedaMCPHub
import Foundation
import Testing

// MARK: - Relay tests

struct JSONRPCRelayTests {
    let connA = RelayConnectionKey(value: "c1")
    let connB = RelayConnectionKey(value: "c2")

    @Test("client request id gets namespaced with the connection key")
    func namespacingNumericID() throws {
        let message = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c1.1""#))
        #expect(str.contains(#""method":"tools/list""#))
    }

    @Test("string ids nest inside the composite")
    func namespacingStringID() throws {
        let message = #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connB)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c2.abc""#))
    }

    @Test("notifications pass through byte-identical")
    func notificationsUntouched() {
        let message = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
        #expect(out == Data(message.utf8))
    }

    @Test("cancelled notification requestId gets namespaced")
    func cancelledRewriting() throws {
        let message =
            #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7}}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""requestId":"c1.7""#))
        #expect(!str.contains(#""requestId":7"#))
    }

    @Test("upstream response routes back with the original id shape")
    func upstreamRouting() throws {
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
        let namespaced = JSONRPCRelay.namespaceClientMessage(Data(request.utf8), connection: connA)
        let str = try #require(String(data: namespaced, encoding: .utf8))
        #expect(str.contains(#""id":"c1.1""#))

        // Upstream replies with the namespaced id in a response.
        let response = #"{"jsonrpc":"2.0","id":"c1.1","result":{"tools":[]}}"#
        let routed = JSONRPCRelay.routeUpstreamMessage(Data(response.utf8))
        #expect(routed?.key == "c1")
        let originalData = try #require(routed?.original)
        let restored = String(decoding: originalData, as: UTF8.self)
        #expect(restored.contains(#""id":1"#)) // numeric original restores bare
        #expect(restored.contains(#""result""#))
    }

    @Test("collision: both connections use id 1 — responses route correctly")
    func idCollision() throws {
        let requestA = #"{"jsonrpc":"2.0","id":1,"method":"a"}"#
        let requestB = #"{"jsonrpc":"2.0","id":1,"method":"b"}"#
        let a = JSONRPCRelay.namespaceClientMessage(Data(requestA.utf8), connection: connA)
        let b = JSONRPCRelay.namespaceClientMessage(Data(requestB.utf8), connection: connB)
        #expect(String(decoding: a, as: UTF8.self).contains(#""id":"c1.1""#))
        #expect(String(decoding: b, as: UTF8.self).contains(#""id":"c2.1""#))

        let responseToA = #"{"jsonrpc":"2.0","id":"c1.1","result":"for A"}"#
        let responseToB = #"{"jsonrpc":"2.0","id":"c2.1","result":"for B"}"#
        let ra = JSONRPCRelay.routeUpstreamMessage(Data(responseToA.utf8))
        let rb = JSONRPCRelay.routeUpstreamMessage(Data(responseToB.utf8))
        #expect(ra?.key == "c1")
        #expect(rb?.key == "c2")
        #expect(try String(decoding: #require(ra?.original), as: UTF8.self).contains("for A"))
        #expect(try String(decoding: #require(rb?.original), as: UTF8.self).contains("for B"))
    }

    @Test("duplicate top-level id members are rejected, never namespaced (hijack vector)")
    func duplicateIDRejection() {
        // A shim could smuggle a second, unnamespaced id past the first-span
        // rewriter; node JSON.parse is last-key-wins upstream — the frame
        // would route into another connection's namespace. Rejected instead.
        let attack = #"{"jsonrpc":"2.0","id":1,"id":"c2.5","method":"tools/list"}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(attack.utf8)) == true)

        let normal = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(normal.utf8)) == false)

        // Duplicate requestId inside cancelled params — same vector.
        let cancelledAttack = #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7,"requestId":"c2.7"}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(cancelledAttack.utf8)) == true)

        // Nested duplicates (inside params.arguments) are NOT the vector —
        // they pass (only top-level and params.requestId matter).
        let nested = #"{"jsonrpc":"2.0","id":1,"method":"m","params":{"x":{"id":1,"id":2}}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(nested.utf8)) == false)
    }

    @Test("server notifications (no id) broadcast — route returns nil")
    func serverNotificationBroadcasts() {
        let notification = #"{"jsonrpc":"2.0","method":"notifications/message","params":{}}"#
        #expect(JSONRPCRelay.routeUpstreamMessage(Data(notification.utf8)) == nil)
    }

    @Test("nested ids are not confused with the top-level id")
    func nestedIDNotTouched() throws {
        let message =
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"arguments":{"id":99}}}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c1.5""#))
        #expect(str.contains(#""id":99"#)) // nested untouched
    }

    @Test("unknown fields preserved verbatim")
    func unknownFieldsPreserved() throws {
        let message =
            #"{"jsonrpc":"2.0","id":3,"method":"x","futureField":{"deep":[1,2,3]},"z":null}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""futureField":{"deep":[1,2,3]}"#))
        #expect(str.contains(#""z":null"#))
    }

    @Test("float and large ids survive the round trip")
    func unusualIDShapes() throws {
        for original in ["1.5", "9007199254740993", "\"with spaces and . dots\""] {
            let message = #"{"jsonrpc":"2.0","id":\#(original),"method":"m"}"#
            let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
            let routed = JSONRPCRelay.routeUpstreamMessage(out)
            #expect(routed?.key == "c1")
            let restored = try String(decoding: #require(routed?.original), as: UTF8.self)
            #expect(restored.contains(#""id":\#(original)"#))
        }
    }
}

// MARK: - Config tests

struct HubConfigurationTests {
    private func server(id: String, placement: HubPlacement = .shared) -> HubServerConfig {
        HubServerConfig(
            id: id, packageName: "pkg/\(id)", command: "/usr/bin/true",
            placement: placement, duplicateGroup: id
        )
    }

    @Test("valid config passes")
    func valid() throws {
        let config = MCPHubConfiguration(servers: [server(id: "filesystem")])
        #expect(throws: Never.self) { try config.validated() }
    }

    @Test("duplicate ids rejected")
    func duplicates() {
        let config = MCPHubConfiguration(servers: [server(id: "memory"), server(id: "memory")])
        #expect(throws: MCPHubConfiguration.ConfigurationError.duplicateServerID("memory")) {
            try config.validated()
        }
    }

    @Test("non-lowercase ids rejected (they name sockets and binaries)")
    func invalidID() {
        let config = MCPHubConfiguration(servers: [server(id: "Filesystem")])
        #expect(throws: MCPHubConfiguration.ConfigurationError.self) { try config.validated() }
    }

    @Test("wave-1 roster must be shared placement only")
    func placementGate() {
        let config = MCPHubConfiguration(servers: [server(id: "browser", placement: .pooled)])
        #expect(throws: MCPHubConfiguration.ConfigurationError.placementNotSharedInWave1("browser")) {
            try config.validated()
        }
    }

    @Test("secret-looking env keys are rejected (wave-1 gate)")
    func secretEnvGate() {
        let secret = HubServerConfig(
            id: "firecrawl", packageName: "p", command: "/usr/bin/true",
            environment: ["FIRECRAWL_API_KEY": "x"], duplicateGroup: "g"
        )
        #expect(throws: MCPHubConfiguration.ConfigurationError.self) {
            try MCPHubConfiguration(servers: [secret]).validated()
        }

        let benign = HubServerConfig(
            id: "memory", packageName: "p", command: "/usr/bin/true",
            environment: ["MEMORY_FILE_PATH": "/tmp/m.json"], duplicateGroup: "g"
        )
        #expect(throws: Never.self) {
            try MCPHubConfiguration(servers: [benign]).validated()
        }
    }

    @Test("socket path derivation")
    func socketPath() {
        let config = MCPHubConfiguration(servers: [server(id: "filesystem")])
        #expect(
            config.socketPath(for: "filesystem")
                == NSHomeDirectory() + "/.andromeda/mcp-hub/sockets/filesystem.sock"
        )
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        let config = MCPHubConfiguration(servers: [server(id: "filesystem")])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPHubConfiguration.self, from: data)
        #expect(decoded == config)
    }
}

// MARK: - Shim naming tests

struct ShimNamingTests {
    @Test("byte-copy name derives the server id")
    func derivesID() {
        #expect(
            AndromedaShimNaming.serverIDFromBinaryName("/usr/local/bin/andromeda-mcp-filesystem")
                == "filesystem"
        )
        #expect(
            AndromedaShimNaming.serverIDFromBinaryName("andromeda-mcp-memory") == "memory"
        )
    }

    @Test("unrelated binaries return nil")
    func rejectsForeign() {
        #expect(AndromedaShimNaming.serverIDFromBinaryName("/usr/bin/node") == nil)
        #expect(AndromedaShimNaming.serverIDFromBinaryName("andromeda-mcp-") == nil)
    }
}

/// Naming logic mirrored from the shim executable target (testable copy —
/// the executable target is not importable; keep these two functions in
/// sync, the shim is 1:1 with this).
enum AndromedaShimNaming {
    static func serverIDFromBinaryName(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix("andromeda-mcp-") else { return nil }
        let id = String(name.dropFirst("andromeda-mcp-".count))
        return id.isEmpty ? nil : id
    }
}
