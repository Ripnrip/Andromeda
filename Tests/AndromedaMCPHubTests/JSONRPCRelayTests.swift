// AndromedaMCPHub tests — relay round-trips, collisions, notifications,
// cancelled rewriting, config validation, shim naming.
//
// Pure-logic: no real processes, no real sockets (canon: fixtures +
// protocol injection). The hub E2E uses an in-process upstream double.
//
// Frames are built from typed Codable fixtures (JSONRPCFixtures) wherever
// the frame is VALID JSON-RPC — no hand-written JSON. The literals that
// remain are deliberate and each says why: duplicate-member attack frames
// cannot be built from Codable (JSONEncoder forbids duplicate keys — that
// illegality IS the security property under test), and byte-layout tests
// (span/rewriter/escaped-key cases) assert on exact bytes that a builder
// would normalize away.

@testable import AndromedaMCPHub
import Foundation
import Testing

// MARK: - Relay tests

struct JSONRPCRelayTests {
    let connA = RelayConnectionKey(value: "c1")
    let connB = RelayConnectionKey(value: "c2")

    @Test("client request id gets namespaced with the connection key")
    func namespacingNumericID() throws {
        let message = JSONRPCFixtures.makeClientRequest(id: 1, method: "tools/list")
        let out = JSONRPCRelay.namespaceClientMessage(message, connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c1.1""#))
        #expect(str.contains(#""method":"tools/list""#))
    }

    @Test("string ids nest inside the composite")
    func namespacingStringID() throws {
        let message = JSONRPCFixtures.makeClientRequest(id: "abc", method: "ping")
        let out = JSONRPCRelay.namespaceClientMessage(message, connection: connB)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c2.abc""#))
    }

    @Test("notifications pass through byte-identical")
    func notificationsUntouched() {
        let message = JSONRPCFixtures.makeNotification(method: "notifications/initialized")
        let out = JSONRPCRelay.namespaceClientMessage(message, connection: connA)
        #expect(out == message)
    }

    @Test("cancelled notification requestId gets namespaced (both wire shapes)")
    func cancelledRewriting() throws {
        // Integer requestId — built from the same typed builder as the
        // string shape below (BofA: one builder, both shapes).
        let intFrame = JSONRPCFixtures.makeCancelledNotification(requestId: 7)
        let intOut = JSONRPCRelay.namespaceClientMessage(intFrame, connection: connA)
        let intStr = try #require(String(data: intOut, encoding: .utf8))
        #expect(intStr.contains(#""requestId":"c1.7""#))
        #expect(!intStr.contains(#""requestId":7"#))

        // String requestId (e.g. a server that issued string ids).
        let stringFrame = JSONRPCFixtures.makeCancelledNotification(requestId: "c2.7")
        let stringOut = JSONRPCRelay.namespaceClientMessage(stringFrame, connection: connA)
        let stringStr = try #require(String(data: stringOut, encoding: .utf8))
        #expect(stringStr.contains(#""requestId":"c1.c2.7""#))
    }

    @Test("upstream response routes back with the original id shape")
    func upstreamRouting() throws {
        let request = JSONRPCFixtures.makeClientRequest(id: 1, method: "tools/list")
        let namespaced = JSONRPCRelay.namespaceClientMessage(request, connection: connA)
        let str = try #require(String(data: namespaced, encoding: .utf8))
        #expect(str.contains(#""id":"c1.1""#))

        // Upstream replies with the namespaced id in a response.
        let response = JSONRPCFixtures.makeUpstreamResponse(
            id: .string("c1.1"), result: .object(["tools": .array([])])
        )
        let routed = JSONRPCRelay.routeUpstreamMessage(response)
        #expect(routed?.key == "c1")
        let originalData = try #require(routed?.original)
        let restored = String(decoding: originalData, as: UTF8.self)
        #expect(restored.contains(#""id":1"#)) // numeric original restores bare
        #expect(restored.contains(#""result""#))
    }

    @Test("collision: both connections use id 1 — responses route correctly")
    func idCollision() throws {
        let requestA = JSONRPCFixtures.makeClientRequest(id: 1, method: "a")
        let requestB = JSONRPCFixtures.makeClientRequest(id: 1, method: "b")
        let a = JSONRPCRelay.namespaceClientMessage(requestA, connection: connA)
        let b = JSONRPCRelay.namespaceClientMessage(requestB, connection: connB)
        #expect(String(decoding: a, as: UTF8.self).contains(#""id":"c1.1""#))
        #expect(String(decoding: b, as: UTF8.self).contains(#""id":"c2.1""#))

        let responseToA = JSONRPCFixtures.makeUpstreamResponse(
            id: .string("c1.1"), result: .string("for A")
        )
        let responseToB = JSONRPCFixtures.makeUpstreamResponse(
            id: .string("c2.1"), result: .string("for B")
        )
        let ra = JSONRPCRelay.routeUpstreamMessage(responseToA)
        let rb = JSONRPCRelay.routeUpstreamMessage(responseToB)
        #expect(ra?.key == "c1")
        #expect(rb?.key == "c2")
        #expect(try String(decoding: #require(ra?.original), as: UTF8.self).contains("for A"))
        #expect(try String(decoding: #require(rb?.original), as: UTF8.self).contains("for B"))
    }

    @Test("duplicate top-level id members are rejected, never namespaced (hijack vector)")
    func duplicateIDRejection() {
        // RAW LITERAL, deliberately not builder-built: duplicate object
        // members are RFC-8259-illegal and JSONEncoder refuses to produce
        // them — the illegality is the security property under test.
        let attack = #"{"jsonrpc":"2.0","id":1,"id":"c2.5","method":"tools/list"}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(attack.utf8)) == true)

        let normal = JSONRPCFixtures.makeClientRequest(id: 1, method: "tools/list")
        #expect(JSONRPCRelay.clientMessageIsMalformed(normal) == false)

        // RAW LITERAL: duplicate requestId inside cancelled params — same
        // builder-impossible duplicate-member vector.
        let cancelledAttack = #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7,"requestId":"c2.7"}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(cancelledAttack.utf8)) == true)

        // Nested duplicates (inside params.arguments) are NOT the vector —
        // they pass (only top-level and params.requestId matter).
        // RAW LITERAL: duplicate members nested one level deeper.
        let nested = #"{"jsonrpc":"2.0","id":1,"method":"m","params":{"x":{"id":1,"id":2}}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(nested.utf8)) == false)
    }

    @Test("Unicode-escaped id members are caught — literal-byte keys don't bypass the guard")
    func unicodeEscapedKeys() {
        // ALL LITERALS IN THIS TEST ARE RAW BY DESIGN: they assert exact
        // byte layouts (Unicode-escaped key forms) that a Codable builder
        // would normalize to plain "id"/"requestId", destroying the case.

        // RFC 8259: `\uXXXX` escapes in object keys decode to the same key,
        // so `"\u0069d"` IS an id member upstream (JSON.parse collapses it).
        // A literal-byte scanner counted only the unescaped one — the
        // duplicate smuggled past the guard (Cursor follow-up to d72ddcf).
        let escapedDuplicate = #"{"jsonrpc":"2.0","\u0069d":1,"id":"c2.5","method":"tools/list"}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(escapedDuplicate.utf8)) == true)

        // Escaped duplicate requestId inside cancelled params — same vector.
        let escapedCancelled =
            #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requ\u0065stId":7,"requestId":"c2.7"}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(escapedCancelled.utf8)) == true)

        // Escaped `params` key still found — the cancelled rewrite works.
        let escapedParams =
            #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requ\u0065stId":7}}"#
        let out = JSONRPCRelay.namespaceClientMessage(Data(escapedParams.utf8), connection: connA)
        #expect(String(decoding: out, as: UTF8.self).contains(#""requ\u0065stId":"c1.7""#))

        // A SINGLE escaped id still gets namespaced (key bytes preserved,
        // value span rewritten).
        let escapedSingle = #"{"jsonrpc":"2.0","\u0069d":5,"method":"m"}"#
        let single = JSONRPCRelay.namespaceClientMessage(Data(escapedSingle.utf8), connection: connA)
        let singleStr = String(decoding: single, as: UTF8.self)
        #expect(singleStr.contains(#""\u0069d":"c1.5""#))
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(escapedSingle.utf8)) == false)

        // Escapes inside unrelated string VALUES don't perturb the scan.
        let valueEscape = #"{"jsonrpc":"2.0","id":1,"method":"m","params":{"a":"\u0069d\u0069d"}}"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(valueEscape.utf8)) == false)
        let routed = JSONRPCRelay.namespaceClientMessage(Data(valueEscape.utf8), connection: connA)
        #expect(String(decoding: routed, as: UTF8.self).contains(#""id":"c1.1""#))
    }

    @Test("server notifications (no id) broadcast — route returns nil")
    func serverNotificationBroadcasts() {
        let notification = JSONRPCFixtures.makeNotification(
            method: "notifications/message", params: .object([:])
        )
        #expect(JSONRPCRelay.routeUpstreamMessage(notification) == nil)
    }

    @Test("nested ids are not confused with the top-level id")
    func nestedIDNotTouched() throws {
        let message = JSONRPCFixtures.makeClientRequest(
            id: 5, method: "tools/call",
            params: .object(["arguments": .object(["id": .number(99)])])
        )
        let out = JSONRPCRelay.namespaceClientMessage(message, connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""id":"c1.5""#))
        #expect(str.contains(#""id":99"#)) // nested untouched
    }

    @Test("unknown fields preserved verbatim")
    func unknownFieldsPreserved() throws {
        let message = JSONRPCFixtures.makeClientRequest(
            id: 3, method: "x",
            params: .object(["futureField": .object(["deep": .array([.number(1), .number(2), .number(3)])])]),
            extras: ["z": .null]
        )
        let out = JSONRPCRelay.namespaceClientMessage(message, connection: connA)
        let str = try #require(String(data: out, encoding: .utf8))
        #expect(str.contains(#""futureField":{"deep":[1,2,3]}"#))
        #expect(str.contains(#""z":null"#))
    }

    @Test("float and large ids survive the round trip")
    func unusualIDShapes() throws {
        // RAW LITERAL, deliberately not builder-built: this test pins the
        // id's exact wire bytes (a float `1.5` and an Int64-overflow-safe
        // large integer). The typed id enum models Int-or-String only —
        // the whole point is that arbitrary numeric SHAPES round-trip
        // byte-preserved by the span rewriter, not by a typed decode.
        for original in ["1.5", "9007199254740993", "\"with spaces and . dots\""] {
            let message = #"{"jsonrpc":"2.0","id":\#(original),"method":"m"}"#
            let out = JSONRPCRelay.namespaceClientMessage(Data(message.utf8), connection: connA)
            let routed = JSONRPCRelay.routeUpstreamMessage(out)
            #expect(routed?.key == "c1")
            let restored = try String(decoding: #require(routed?.original), as: UTF8.self)
            #expect(restored.contains(#""id":\#(original)"#))
        }
    }

    @Test("relayClientMessage reports which rewrites were applied")
    func relayOutcomeFlags() {
        let request = JSONRPCFixtures.makeClientRequest(id: 1, method: "tools/list")
        let requestOutcome = JSONRPCRelay.relayClientMessage(request, connection: connA)
        #expect(requestOutcome.namespacedID == true)
        #expect(requestOutcome.namespacedCancelledRequestID == false)
        #expect(requestOutcome.frame == JSONRPCRelay.namespaceClientMessage(request, connection: connA))

        let cancelled = JSONRPCFixtures.makeCancelledNotification(requestId: 7)
        let cancelledOutcome = JSONRPCRelay.relayClientMessage(cancelled, connection: connA)
        #expect(cancelledOutcome.namespacedID == false) // notification: no top-level id
        #expect(cancelledOutcome.namespacedCancelledRequestID == true)

        let initialized = JSONRPCFixtures.makeNotification(method: "notifications/initialized")
        let initializedOutcome = JSONRPCRelay.relayClientMessage(initialized, connection: connA)
        #expect(initializedOutcome.namespacedID == false)
        #expect(initializedOutcome.namespacedCancelledRequestID == false)
        #expect(initializedOutcome.frame == initialized) // byte-identical passthrough
    }

    // MARK: Security policy (Cursor HIGH + MEDIUM review)

    @Test("client roots notifications are dropped, never forwarded (sandbox hijack vector)")
    func rootsNotificationDropped() {
        // official server-filesystem REPLACES its process-global allowlist
        // from client roots — forwarding this notification lets any session
        // widen/replace the sandbox every other session shares.
        let attack = JSONRPCFixtures.makeNotification(method: "notifications/roots/list_changed")
        #expect(
            JSONRPCRelay.dispositionForClientFrame(attack) == .dropRootsNotification
        )

        // Requests (id present) and other notifications still forward.
        let request = JSONRPCFixtures.makeClientRequest(id: 1, method: "tools/list")
        #expect(JSONRPCRelay.dispositionForClientFrame(request) == .forward)
        let initialized = JSONRPCFixtures.makeNotification(method: "notifications/initialized")
        #expect(JSONRPCRelay.dispositionForClientFrame(initialized) == .forward)

        // A roots/list REQUEST (id present) is not the notification — it
        // forwards (the namespacer handles it; upstreams that ask for roots
        // get the hub's empty answer on the server-initiated path instead).
        let rootsRequest = JSONRPCFixtures.makeClientRequest(id: 2, method: "roots/list")
        #expect(JSONRPCRelay.dispositionForClientFrame(rootsRequest) == .forward)
    }

    @Test("JSON-RPC batch arrays are rejected — they bypass depth-1 id namespacing")
    func batchArraysRejected() {
        // RAW LITERAL: a batch is a top-level array; no depth-1 id exists,
        // so the old namespacer passed it through byte-identical and its
        // unnamespaced response ids broadcast to every shim (Cursor
        // security review). Rejected with -32600 now.
        let batch = #"[{"jsonrpc":"2.0","id":1,"method":"tools/list"},{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"x"}}]"#
        if case let .reject(reason) = JSONRPCRelay.dispositionForClientFrame(Data(batch.utf8)) {
            #expect(reason == .topLevelArray)
        } else {
            Issue.record("batch frame must be rejected, not forwarded")
        }
        // Whitespace-led arrays are caught too.
        let spaced = #" [{"jsonrpc":"2.0","id":1,"method":"tools/list"}]"#
        #expect(JSONRPCRelay.clientMessageIsMalformed(Data(spaced.utf8)) == true)

        // The rejection is observable on the wire: -32600 + the batch message.
        let encoded = HubJSONRPCError.batchFrameRejected.encoded()
        let wireText = String(decoding: encoded, as: UTF8.self)
        #expect(wireText.contains(#""code":-32600"#))
        #expect(wireText.contains("batch frames rejected"))
    }

    @Test("server-initiated roots requests are recognized for hub answering")
    func upstreamRootsRequestDetected() {
        // RAW LITERALS: exact wire shapes the upstream emits — the hub must
        // answer these itself (empty roots) and never broadcast them.
        let rootsList = #"{"jsonrpc":"2.0","id":1,"method":"roots/list"}"#
        #expect(JSONRPCRelay.isUpstreamRootsRequest(Data(rootsList.utf8)) == true)

        let rootsListChanged = #"{"jsonrpc":"2.0","id":"srv-1","method":"roots/list_changed"}"#
        #expect(JSONRPCRelay.isUpstreamRootsRequest(Data(rootsListChanged.utf8)) == true)

        // Responses (no method) and notifications (no id) don't match.
        let response = #"{"jsonrpc":"2.0","id":1,"result":{}}"#
        #expect(JSONRPCRelay.isUpstreamRootsRequest(Data(response.utf8)) == false)
        let notification = JSONRPCFixtures.makeNotification(method: "notifications/message")
        #expect(JSONRPCRelay.isUpstreamRootsRequest(notification) == false)
    }

    @Test("hub roots reply carries empty roots and echoes the request id")
    func emptyRootsReplyShape() throws {
        let numeric = #"{"jsonrpc":"2.0","id":1,"method":"roots/list"}"#
        let reply = try HubJSONRPCError.emptyRootsResult(id: .number(1))
        let text = String(decoding: reply, as: UTF8.self)
        #expect(text == #"{"jsonrpc":"2.0","id":1,"result":{"roots":[]}}"#)

        let string = try HubJSONRPCError.emptyRootsResult(id: .string("srv-1"))
        #expect(String(decoding: string, as: UTF8.self) == #"{"jsonrpc":"2.0","id":"srv-1","result":{"roots":[]}}"#)
        _ = numeric
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

    @Test("every SecretKeyMarker case rejects a key carrying it — enum exhaustivity")
    func secretMarkerEnumExhaustive() {
        // CaseIterable drives the check: a marker added to the enum without
        // this gate catching its shape is a compile-time gap, not a runtime
        // surprise (Q1: enums over magic strings).
        for marker in MCPHubConfiguration.SecretKeyMarker.allCases {
            let key = "MY_\(marker.rawValue.uppercased())_THING"
            #expect(MCPHubConfiguration.looksLikeSecretKey(key), "marker \(marker.rawValue) must match")
        }
        // And a genuinely clean key stays clean.
        #expect(!MCPHubConfiguration.looksLikeSecretKey("MEMORY_FILE_PATH"))
        #expect(!MCPHubConfiguration.looksLikeSecretKey("LOG_LEVEL"))
    }

    @Test("socket path derivation") func socketPath() {
        let config = MCPHubConfiguration(servers: [server(id: "filesystem")])
        #expect(
            config.socketPath(for: "filesystem")
                == NSHomeDirectory() + "/.andromeda/mcp-hub/sockets/filesystem.sock"
        )
    }

    @Test("filesystem servers must pin sandbox directories (Cursor HIGH)")
    func filesystemSandboxPinned() {
        // A filesystem-class server with NO allowed-directory arguments
        // would run unsandboxed once client roots stop being forwarded —
        // rejected at validation time.
        let unpinned = HubServerConfig(
            id: "filesystem", packageName: "@modelcontextprotocol/server-filesystem",
            command: "/usr/bin/node",
            arguments: [], // ← the bug shape: no allowed dirs
            duplicateGroup: "server-filesystem"
        )
        #expect(throws: MCPHubConfiguration.ConfigurationError.filesystemSandboxUnpinned(serverID: "filesystem")) {
            try MCPHubConfiguration(servers: [unpinned]).validated()
        }

        // Pinned at spawn time: allowed dirs as arguments — passes.
        let pinned = HubServerConfig(
            id: "filesystem", packageName: "@modelcontextprotocol/server-filesystem",
            command: "/usr/bin/node",
            arguments: ["/Users/admin/Developer/sandbox"],
            duplicateGroup: "server-filesystem"
        )
        #expect(throws: Never.self) {
            try MCPHubConfiguration(servers: [pinned]).validated()
        }

        // Non-filesystem servers are unaffected.
        #expect(throws: Never.self) {
            try MCPHubConfiguration(servers: [server(id: "memory")]).validated()
        }
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
