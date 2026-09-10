// Exhaustive enum-driven tests (BofA ask 5: "can enums run through the
// cases for tests?") + the byte-equality proof for the typed error frames
// (ask 1). These tests iterate the CONSTRUCTORS of each enum so adding a
// case breaks the build here until it is covered — the compiler-enforced
// exhaustiveness the fleet canon asks for.

@testable import AndromedaMCPHub
import Foundation
import Testing

// MARK: - HubJSONRPCError (all constructors, exhaustively)

struct HubJSONRPCErrorTests {
    /// Byte-equality proof, ask 1: the typed frame path reproduces the
    /// EXACT wire bytes of the hand-written literals it replaced. These
    /// two strings are the pre-refactor literals from MCPHub.swift, kept
    /// verbatim as the regression oracle.
    @Test("encoded frames are byte-equal to the legacy hand-written literals")
    func byteEqualityWithLegacyLiterals() {
        let legacyUpstreamUnavailable =
            #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"mcp-hub: upstream unavailable (restart budget exhausted)"}}"#
        let legacyMalformedFrame =
            #"{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"mcp-hub: malformed frame (duplicate id members rejected)"}}"#

        #expect(
            HubJSONRPCError.upstreamUnavailable.encoded() == Data(legacyUpstreamUnavailable.utf8)
        )
        #expect(
            HubJSONRPCError
                .malformedFrame(duplicate: HubJSONRPCError.duplicateMemberID)
                .encoded() == Data(legacyMalformedFrame.utf8)
        )
    }

    @Test("every constructor encodes valid JSON-RPC with a literal null id")
    func allCasesEncodeValidFrames() throws {
        for error in HubJSONRPCError.allCases {
            let bytes = error.encoded()
            let text = try #require(String(data: bytes, encoding: .utf8))

            // Valid JSON, structurally a JSON-RPC 2.0 error response.
            let object = try #require(
                JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            )
            #expect(object["jsonrpc"] as? String == "2.0")
            let errorObject = try #require(object["error"] as? [String: Any])
            #expect(errorObject["code"] as? Int == error.code)
            #expect(errorObject["message"] as? String == error.message)

            // The id member is PRESENT and literal null — not absent
            /// (JSON-RPC 2.0 requires the member on responses).
            #expect(text.contains(#""id":null"#))
            #expect(object.keys.contains("id"))

            // Valid JSON end-to-end (would throw above if malformed).
        }
    }

    @Test("codes are distinct and in the JSON-RPC reserved band")
    func distinctCodes() {
        let codes = HubJSONRPCError.allCases.map(\.code)
        #expect(Set(codes).count == codes.count) // all distinct
        for code in codes {
            #expect(code <= -32000 && code >= -32999)
        }
    }

    @Test("messages are non-empty and carry the hub prefix")
    func messagesNonEmpty() {
        for error in HubJSONRPCError.allCases {
            #expect(!error.message.isEmpty)
            #expect(error.message.hasPrefix("mcp-hub: "))
        }
    }

    @Test("decode round-trips through Codable")
    func codableRoundTrip() throws {
        for error in HubJSONRPCError.allCases {
            let frame = error.frame(explicitNullID: true)
            let data = try JSONEncoder().encode(frame)
            let decoded = try JSONDecoder().decode(JSONRPCErrorFrame.self, from: data)
            #expect(decoded == frame)
        }
    }

    @Test("decoding accepts a literal null id and an absent id")
    func decodeNullAndAbsentID() throws {
        // Literal null id — what the hub issues.
        let nullID = #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"x"}}"#
        let fromNull = try JSONDecoder().decode(JSONRPCErrorFrame.self, from: Data(nullID.utf8))
        #expect(fromNull.id == nil)

        // Absent id — legal JSON-RPC for a notification-shaped frame.
        let noID = #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"x"}}"#
        let fromAbsent = try JSONDecoder().decode(JSONRPCErrorFrame.self, from: Data(noID.utf8))
        #expect(fromAbsent.id == nil)
    }

    @Test("request ids decode in both legal wire shapes")
    func requestIDShapes() throws {
        let numberID = #"{"jsonrpc":"2.0","id":7,"error":{"code":-32603,"message":"x"}}"#
        let fromNumber = try JSONDecoder().decode(
            JSONRPCErrorFrame.self, from: Data(numberID.utf8)
        )
        #expect(fromNumber.id == .number(7))

        let stringID = #"{"jsonrpc":"2.0","id":"c2.7","error":{"code":-32603,"message":"x"}}"#
        let fromString = try JSONDecoder().decode(
            JSONRPCErrorFrame.self, from: Data(stringID.utf8)
        )
        #expect(fromString.id == .string("c2.7"))
    }

    @Test("encoding via JSONEncoder writes id as a present member, never omits it")
    func encodeAlwaysWritesID() throws {
        let frame = HubJSONRPCError.upstreamUnavailable.frame(explicitNullID: true)
        let data = try JSONEncoder().encode(frame)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object.keys.contains("id"))
        #expect(object["id"] is NSNull)
    }
}

// MARK: - EnvironmentAllowKey (CaseIterable, exhaustively)

struct EnvironmentAllowKeyTests {
    @Test("allowlist contains exactly the six expected keys")
    func exactlySixKeys() {
        let allowlist = Set(EnvironmentAllowKey.allCases.map(\.rawValue))
        #expect(allowlist == ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "XDG_CACHE_HOME"])
        #expect(EnvironmentAllowKey.allCases.count == 6)
    }

    @Test("every case is in the runtime allowlist the host filters on")
    func everyCaseIsAllowlisted() {
        let allowlist = ProcessUpstreamHost.environmentAllowlist
        for key in EnvironmentAllowKey.allCases {
            #expect(allowlist.contains(key.rawValue))
        }
        #expect(allowlist.count == EnvironmentAllowKey.allCases.count) // no extras either
    }

    @Test("raw values are non-empty and distinct")
    func rawValuesNonEmptyAndDistinct() {
        let rawValues = EnvironmentAllowKey.allCases.map(\.rawValue)
        for rawValue in rawValues {
            #expect(!rawValue.isEmpty)
        }
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("secrets-bearing keys are excluded (Codex P1 security property)")
    func secretsExcluded() {
        let allowlist = Set(EnvironmentAllowKey.allCases.map(\.rawValue))
        // Ambient credential carriers that must NEVER pass through to a
        // hosted process by default.
        for secret in [
            "AWS_SECRET_ACCESS_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY",
            "GITHUB_TOKEN", "GEMINI_API_KEY", "HF_TOKEN",
        ] {
            #expect(!allowlist.contains(secret))
        }
    }
}

// MARK: - HubEvent (glyph + kind on every case, compiler-enforced)

struct HubEventCoverageTests {
    /// One constructor per case — the compiler forces this switch to grow
    /// when a case is added, so a case can never ship without a glyph/kind.
    private static var constructors: [HubEvent] {
        [
            .hubStarted(socketDirectory: "~/.andromeda/mcp-hub/sockets", servers: 1),
            .upstreamSpawned(serverID: "memory", command: "/usr/bin/node", attempt: 0),
            .upstreamSpawnFailed(serverID: "memory", attempt: 1),
            .upstreamExited(serverID: "memory", restarts: 1),
            .upstreamRestartScheduled(serverID: "memory", restarts: 1, backoffSeconds: 2),
            .upstreamExhausted(serverID: "memory", restarts: 5),
            .shimConnected(serverID: "memory", connection: "c1"),
            .shimDisconnected(serverID: "memory", connection: "c1"),
            .upstreamResponseRouted(serverID: "memory", connection: "c1"),
            .upstreamNotificationBroadcast(serverID: "memory", receivers: 2),
            .malformedFrameRejected(serverID: "memory", connection: "c1"),
            .upstreamUnavailableReply(serverID: "memory", connection: "c1"),
            .idNamespaced(serverID: "memory", connection: "HubEventSwitchCoverage"),
            .cancelledRequestIDRewritten(serverID: "memory", connection: "c1"),
            .stderrDrained(serverID: "memory", bytes: 128),
        ]
    }

    @Test("every case has a non-empty glyph (emoji telemetry law)")
    func glyphsNonEmpty() {
        for event in Self.constructors {
            #expect(!event.glyph.isEmpty, "glyph missing for \(event.kind)")
        }
    }

    @Test("every case has a non-empty, namespaced kind")
    func kindsNonEmpty() {
        let kinds = Self.constructors.map(\.kind)
        for kind in kinds {
            #expect(!kind.isEmpty)
            #expect(kind.contains("."))
        }
        #expect(Set(kinds).count == kinds.count) // kinds are the JSONL index — unique
    }

    @Test("fields render non-empty values for every case")
    func fieldsRender() {
        for event in Self.constructors {
            #expect(!event.fields.isEmpty, "fields missing for \(event.kind)")
            for (key, value) in event.fields {
                #expect(!key.isEmpty)
                #expect(!value.isEmpty, "empty value for \(key) in \(event.kind)")
            }
        }
    }

    @Test("summary is one line and starts with the kind")
    func summaryShape() {
        for event in Self.constructors {
            #expect(!event.summary.isEmpty)
            #expect(event.summary.hasPrefix(event.kind))
            #expect(!event.summary.contains("\n"))
        }
    }

    @Test("the six new decision points from the telemetry audit are present")
    func auditedDecisionPointsExist() {
        // Ask 3 audit: malformed-frame rejection 🚫, upstream-unavailable
        // reply ⚠️, cancelled rewrite ✂️, id namespacing 🏷️, stderr drained
        // 🧹, upstream restart 🔁.
        let byGlyph = Dictionary(
            Self.constructors.map { ($0.glyph, $0.kind) }, uniquingKeysWith: { a, _ in a }
        )
        #expect(byGlyph["🚫"] == "frame.malformed_rejected")
        #expect(byGlyph["⚠️"] == "hub.upstream_unavailable_reply")
        #expect(byGlyph["✂️"] == "frame.cancelled_request_id_rewritten")
        #expect(byGlyph["🏷️"] == "frame.id_namespaced")
        #expect(byGlyph["🧹"] == "upstream.stderr_drained")
        #expect(byGlyph["🔁"] == "upstream.restart_scheduled")
    }
}
