import AndromedaSecrets
@testable import AndromedaTools
import Foundation
import Testing

/// Standalone safety regressions: fixtures are synthetic, deterministic, and
/// entirely injected. No live Keychain, network, environment, timers, sleeps,
/// detached tasks, or dependencies on CuratedToolBrokerTests are used.
@Suite("AndromedaTools.BrokerOutputSafety")
struct BrokerOutputSafetyTests {
    private static let token = "ghp_OUTPUT-SAFETY-CANARY-NOT-A-REAL-SECRET"
    private static let githubReference = SecretReference(service: "output-safety.github", account: "fixture")
    private static let slackReference = SecretReference(service: "output-safety.slack", account: "fixture")

    // MARK: - Sendable fixtures

    /// Exercises both arbitrary errors and forged public broker-error cases.
    /// The private broker-owned failure type must be the only trusted type.
    enum FailureKind: CaseIterable, Equatable, Sendable {
        case arbitrary
        case unknownTool
        case serviceNotConfigured
        case invalidConfiguration
        case policyDenied
        case invalidArguments
        case secretUnavailable
        case upstreamError
        case credentialNotFound
        case credentialBackendUnavailable
        case cancellation
    }

    /// Simulates an exception whose description contains credential/request
    /// data. A fixed result must replace the entire exception, not just a token.
    private struct PayloadError: Error, LocalizedError, Sendable {
        let payload: String

        /// Supplies hostile diagnostic text solely to the injected seam.
        var errorDescription: String? { payload }
    }

    /// Creates synthetic errors without touching external credential storage.
    private static func error(for kind: FailureKind) -> any Error {
        let payload = "private exception /caller/path?token=\(token)"
        switch kind {
        case .arbitrary:
            return PayloadError(payload: payload)
        case .unknownTool:
            return ToolBrokerError.unknownTool(payload)
        case .serviceNotConfigured:
            return ToolBrokerError.serviceNotConfigured(payload)
        case .invalidConfiguration:
            return ToolBrokerError.invalidConfiguration(payload)
        case .policyDenied:
            return ToolBrokerError.policyDenied(payload)
        case .invalidArguments:
            return ToolBrokerError.invalidArguments(payload)
        case .secretUnavailable:
            return ToolBrokerError.secretUnavailable(payload)
        case .upstreamError:
            return ToolBrokerError.upstreamError(service: payload, status: 401, body: payload)
        case .credentialNotFound:
            return SecretProviderError.notFound(service: payload, account: payload)
        case .credentialBackendUnavailable:
            return SecretProviderError.backendUnavailable(payload)
        case .cancellation:
            return CancellationError()
        }
    }

    /// A value-only provider returns one token or throws a controlled error.
    private struct FixtureSecrets: SecretProviding {
        let token: String
        let failure: FailureKind?

        /// Implements the existing secret seam; references are not resolved.
        func secret(for reference: SecretReference) async throws -> String {
            if let failure {
                throw BrokerOutputSafetyTests.error(for: failure)
            }
            return token
        }
    }

    /// An actor records requests for no-egress assertions. All returned data
    /// is immutable/Sendable; there is no background work or queued live I/O.
    private actor FixtureHTTP: UpstreamHTTPExecuting {
        private let response: UpstreamHTTPResponse
        private let failure: FailureKind?
        private(set) var requests: [UpstreamHTTPRequest] = []

        /// Constructs an immediate in-memory response or injected failure.
        init(body: Data = Data("{}".utf8), status: Int = 200, failure: FailureKind? = nil) {
            self.response = UpstreamHTTPResponse(status: status, body: body)
            self.failure = failure
        }

        /// Captures auth only in this synthetic fixture before returning.
        func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
            requests.append(request)
            if let failure {
                throw BrokerOutputSafetyTests.error(for: failure)
            }
            return response
        }
    }

    /// Uses the unchanged public initializer unless a deterministic internal
    /// output check is supplied. Synthetic references have no live side effects.
    private func makeBroker(
        http: FixtureHTTP,
        token: String = BrokerOutputSafetyTests.token,
        secretFailure: FailureKind? = nil,
        maxBytes: Int = 1_048_576,
        automationAllowed: Bool = true,
        github: Bool = true,
        slack: Bool = true,
        outputCancellationCheck: SafeBrokerOutput.CancellationCheck? = nil
    ) throws -> CuratedToolBroker {
        let configuration = try ToolsBrokerConfiguration(
            automationAllowed: automationAllowed,
            github: github ? .init(tokenReference: Self.githubReference) : nil,
            slack: slack ? .init(tokenReference: Self.slackReference) : nil,
            maxResponseBytes: maxBytes
        )
        let secrets = FixtureSecrets(token: token, failure: secretFailure)
        if let outputCancellationCheck {
            return CuratedToolBroker(
                configuration: configuration,
                secrets: secrets,
                http: http,
                outputCancellationCheck: outputCancellationCheck
            )
        }
        return CuratedToolBroker(
            configuration: configuration,
            secrets: secrets,
            http: http
        )
    }

    /// Requires the existing single-text-content contract without hiding a
    /// missing result behind an empty-string fallback.
    private func text(_ result: ToolCallResult) throws -> String {
        #expect(result.content.count == 1)
        return try #require(result.content.first?.text)
    }

    // MARK: - Pure text filtering

    @Test("a complete raw token crossing the original cap is redacted before truncation")
    func rawTokenStraddlesCap() {
        // The original cap would expose a credential prefix. After full-body
        // redaction the same budget fits the complete replacement, not that
        // prefix. An unredacted suffix also forces a real truncation marker.
        let prefix = "public:"
        let limit = prefix.utf8.count + "[redacted]".utf8.count
        let body = Data((prefix + Self.token + String(repeating: "z", count: limit)).utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: Self.token, maxBytes: limit)
        #expect(output.hasPrefix(prefix + "[redacted]\n[truncated: upstream body was"))
        #expect(!output.contains(Self.token))
        #expect(!output.contains(String(Self.token.prefix("[redacted]".count))))
    }

    @Test("all repeated literal occurrences are filtered, not only the first")
    func repeatedRawTokens() {
        let body = Data((Self.token + " public " + Self.token).utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: Self.token, maxBytes: Int.max)
        #expect(output == "[redacted] public [redacted]")
        let adjacent = Data((Self.token + Self.token).utf8)
        #expect(SafeBrokerOutput.bodyText(adjacent, resolvedToken: Self.token, maxBytes: Int.max) == "[redacted][redacted]")
    }

    @Test("overlapping raw occurrences are replaced as their complete union")
    func overlappingRawTokens() {
        // Both aba occurrences share the central a. No bytes of either match
        // may survive, and disjoint matches still receive individual markers.
        let output = SafeBrokerOutput.bodyText(Data("ababa public aba".utf8), resolvedToken: "aba", maxBytes: Int.max)
        #expect(output == "[redacted] public [redacted]")
    }

    @Test("decoded JSON overlaps and raw/JSON coverage coexist without surviving match bytes")
    func overlappingJSONAndRawTokens() throws {
        // Independently authored escape spelling decodes to ababa, not just aba.
        // One span also has an ordinary raw spelling; outside spans is raw prose.
        let body = Data(#"aba {"echo":"\u0061baba","raw":"ababa"} ababa"#.utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: "aba", maxBytes: Int.max)
        #expect(output == #"[redacted] {"echo":"[redacted]","raw":"[redacted]"} [redacted]"#)
        let quoted = SafeBrokerOutput.bodyText(Data(#""\u0061baba""#.utf8), resolvedToken: "aba", maxBytes: Int.max)
        #expect(try JSONDecoder().decode(String.self, from: Data(quoted.utf8)) == "[redacted]")
    }

    @Test("a replacement boundary that recreates the known token fails closed once")
    func replacementBoundaryFailsClosed() {
        // Review counterexample: [redacted] + retained a would be the token.
        // Both raw and escaped JSON forms must withhold, never loop replacing.
        let token = "[redacted]a"
        for original in ["[redacted]aa", #""\u005bredacted]aa""#] {
            let output = SafeBrokerOutput.bodyText(Data(original.utf8), resolvedToken: token, maxBytes: Int.max)
            #expect(output == "<upstream body withheld: output sanitization failed>")
            #expect(!output.contains(token))
        }
    }

    @Test("redaction marker collisions select a bounded token-free alternative")
    func replacementMarkerCollisions() throws {
        for token in ["[redacted]", "e", "a", "■"] {
            let raw = SafeBrokerOutput.bodyText(Data(token.utf8), resolvedToken: token, maxBytes: Int.max)
            let expected = token == "■" ? "[redacted]" : "■"
            #expect(raw == expected)
            let encoded = try JSONEncoder().encode(token)
            let output = SafeBrokerOutput.bodyText(encoded, resolvedToken: token, maxBytes: Int.max)
            #expect(try JSONDecoder().decode(String.self, from: Data(output.utf8)) == expected)
            #expect(!output.contains(token))
        }
    }

    @Test("metadata collision or prefix/metadata token recreation withholds the whole output")
    func metadataCollisionFailsClosed() {
        // The complete token is not in the body. It would be manufactured by
        // concatenating the retained public prefix with truncation metadata.
        let token = "x\n[truncated:"
        let output = SafeBrokerOutput.bodyText(Data("xyz".utf8), resolvedToken: token, maxBytes: 1)
        #expect(output == "<upstream body withheld: output sanitization failed>")
        #expect(!output.contains(token))
        // Even the fixed failure notice may collide with an arbitrary helper
        // token. Empty output is the fallback, not a retry or original body.
        #expect(SafeBrokerOutput.bodyText(Data("public padding".utf8), resolvedToken: "upstream", maxBytes: 1) == "")
    }

    @Test("mixed JSON escape representations decode to the resolved token")
    func escapedJSONRepresentations() throws {
        // These are literal JSON spellings, not JSONEncoder-produced fixtures;
        // they pin slash, quote, backslash, Unicode, surrogate-pair, newline,
        // and tab coverage independently of the encoder's platform defaults.
        let token = "canary/\"\\é😀\n\t"
        let literals = [
            #""canary\/\"\\\u00e9\uD83D\uDE00\n\t""#,
            #""canary/\"\\é😀\n\t""#,
            #""\u0063anary\/\u0022\u005C\u00E9\uD83d\uDe00\u000a\u0009""#,
        ]
        for literal in literals {
            // A successful decode proves each hand-authored oracle is the
            // intended token before checking the helper's independent behavior.
            let decoded = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
            #expect(decoded == token)
            let body = Data(("{\"echo\":" + literal + ",\"public\":\"ok\"}").utf8)
            let output = SafeBrokerOutput.bodyText(body, resolvedToken: token, maxBytes: Int.max)
            #expect(output == #"{"echo":"[redacted]","public":"ok"}"#)
        }
    }

    @Test("JSON keys and nested string values receive decoded-token filtering")
    func escapedKeysAndNestedValues() {
        let token = "key/token"
        let body = Data(#"{"\u006bey\/token":[{"echo":"key\/token"}]}"#.utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: token, maxBytes: Int.max)
        #expect(output == #"{"[redacted]":[{"echo":"[redacted]"}]}"#)
    }

    @Test("escaped token recognition happens before a cap inside its JSON spelling")
    func escapedTokenStraddlesCap() {
        let token = "canary/token-for-boundary"
        let prefix = #"{"echo":""#
        let escaped = #"\u0063anary\/token-for-boundary"#
        let limit = prefix.utf8.count + "[redacted]".utf8.count
        let body = Data((prefix + escaped + #"","public":"long enough to truncate"}"#).utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: token, maxBytes: limit)
        #expect(output.hasPrefix(prefix + "[redacted]\n[truncated: upstream body was"))
        #expect(!output.contains("\\u0063anary"))
        #expect(!output.contains(token))
    }

    @Test("nonmatching valid JSON preserves whitespace, key order, and escape spelling")
    func untouchedJSONPreservesBytes() {
        let original = #" { "public" : "pub\/lic", "n" : 1, "nested": ["ok"] } "#
        let output = SafeBrokerOutput.bodyText(Data(original.utf8), resolvedToken: Self.token, maxBytes: Int.max)
        #expect(output == original)
    }

    @Test("malformed quoted prose still gets the literal-token pass")
    func malformedQuotedLiteralToken() {
        // The invalid \q prevents JSON decoding. Literal-token filtering
        // still occurs over the full supplied text, without lossy decoding.
        let original = "\"echo \(Self.token)\\q\""
        let output = SafeBrokerOutput.bodyText(Data(original.utf8), resolvedToken: Self.token, maxBytes: Int.max)
        #expect(output == "\"echo [redacted]\\q\"")
    }

    @Test("invalid UTF-8 with a public or credential prefix is withheld wholesale")
    func invalidUTF8IsWithheld() {
        var body = Data(("public " + Self.token).utf8)
        body.append(0xFF)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: Self.token, maxBytes: 1)
        #expect(output == "<non-utf8 body: \(body.count) bytes>")
        #expect(!output.contains("public"))
        #expect(!output.contains(Self.token))
        #expect(!output.contains("�"))
    }

    @Test("caps inside multibyte scalars keep a valid UTF-8 public prefix", arguments: ["é", "€", "😀"])
    func utf8ScalarBoundary(_ scalar: String) {
        // Exercise every interior byte position for 2-, 3-, and 4-byte scalar
        // fixtures, without assuming the scalar width equals Character count.
        let prefix = "A"
        let body = Data((prefix + scalar + "Z").utf8)
        for interior in 1 ..< scalar.utf8.count {
            let limit = prefix.utf8.count + interior
            let output = SafeBrokerOutput.bodyText(body, resolvedToken: Self.token, maxBytes: limit)
            #expect(output.hasPrefix(prefix + "\n[truncated: upstream body was"))
            #expect(!output.contains("non-utf8"))
            #expect(!output.contains("�"))
        }
    }

    @Test("a scalar-safe cap can shorten a grapheme without inventing replacement characters")
    func combiningScalarBoundary() {
        let body = Data("e\u{0301}Z".utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: Self.token, maxBytes: "e".utf8.count)
        #expect(output.hasPrefix("e\n[truncated: upstream body was"))
        #expect(!output.contains("�"))
    }

    @Test("an exact UTF-8 byte budget preserves the entire body without a marker")
    func exactBudget() {
        let original = "é€😀"
        let output = SafeBrokerOutput.bodyText(Data(original.utf8), resolvedToken: Self.token, maxBytes: original.utf8.count)
        #expect(output == original)
    }

    @Test("zero and negative budgets clamp safely, including Int.min", arguments: [0, -1, Int.min])
    func nonpositiveBudget(_ limit: Int) {
        let output = SafeBrokerOutput.bodyText(Data("public".utf8), resolvedToken: Self.token, maxBytes: limit)
        #expect(output.hasPrefix("\n[truncated: upstream body was"))
        #expect(output.hasSuffix("limit is 0]"))
    }

    @Test("redaction growth is budgeted using sanitized bytes, not original bytes")
    func replacementGrowth() {
        // A short synthetic token expands into the fixed replacement. The
        // result must still cap sanitized body bytes and report both sizes.
        let token = "key"
        let body = Data(token.utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: token, maxBytes: body.count)
        #expect(output.hasPrefix(String("[redacted]".prefix(body.count)) + "\n[truncated:"))
        #expect(output.contains("sanitized body was \("[redacted]".utf8.count) bytes"))
    }

    @Test("an empty token does not match every substring or suppress ordinary public text")
    func emptyTokenAndEmptyBody() {
        #expect(SafeBrokerOutput.bodyText(Data("public".utf8), resolvedToken: "", maxBytes: Int.max) == "public")
        #expect(SafeBrokerOutput.bodyText(Data(), resolvedToken: Self.token, maxBytes: 0) == "")
    }

    @Test("unknown values remain outside known-token filtering, not a generic DLP claim")
    func knownTokenScope() {
        // This oracle explicitly preserves public/unknown body data. It must
        // not be cited as evidence of secret discovery or all-egress protection.
        let original = "ordinary public text with another unrecognized value"
        #expect(SafeBrokerOutput.bodyText(Data(original.utf8), resolvedToken: Self.token, maxBytes: Int.max) == original)
    }

    @Test("accepted helper body ceiling is inclusive and ceiling-plus-one is withheld before UTF-8 decode")
    func helperAcceptedBodyCeiling() throws {
        let ceiling = SafeBrokerOutput.maxAcceptedBodyBytes
        let accepted = Data(repeating: 0x7A, count: ceiling)
        let output = SafeBrokerOutput.bodyText(accepted, resolvedToken: Self.token, maxBytes: Int.max)
        #expect(output.utf8.count == ceiling)
        #expect(output == String(repeating: "z", count: ceiling))
        var oversized = accepted
        oversized.append(0xFF) // Must select size rejection, not invalid UTF-8.
        let withheld = try SafeBrokerOutput.checkedBodyText(oversized, resolvedToken: Self.token, maxBytes: 1) { checkpoint in
            // Any UTF-8 decode bracket would instead throw cancellation.
            // A small fixed rejection notice can still check cancellation.
            if checkpoint == .beforeUTF8Decode || checkpoint == .afterUTF8Decode { throw CancellationError() }
        }
        #expect(withheld == "<upstream body withheld: accepted size limit exceeded>")
    }

    @Test("quoted-span count and byte-work limits are inclusive and fail closed when exceeded")
    func quotedWorkLimits() {
        let count = SafeBrokerOutput.maxQuotedSpans
        let acceptedSpans = String(repeating: #""""#, count: count)
        #expect(SafeBrokerOutput.bodyText(Data(acceptedSpans.utf8), resolvedToken: Self.token, maxBytes: Int.max) == acceptedSpans)
        let tooManySpans = acceptedSpans + #""""#
        #expect(SafeBrokerOutput.bodyText(Data(tooManySpans.utf8), resolvedToken: Self.token, maxBytes: 1)
            == "<upstream body withheld: output sanitization limit exceeded>")
        let span = "\"" + String(repeating: "z", count: SafeBrokerOutput.maxQuotedSpanBytes - 2) + "\""
        #expect(SafeBrokerOutput.bodyText(Data(span.utf8), resolvedToken: Self.token, maxBytes: Int.max) == span)
        let oversizedSpan = "\"" + String(repeating: "z", count: SafeBrokerOutput.maxQuotedSpanBytes - 1) + "\""
        #expect(SafeBrokerOutput.bodyText(Data(oversizedSpan.utf8), resolvedToken: Self.token, maxBytes: 1)
            == "<upstream body withheld: output sanitization limit exceeded>")
        // Initial spans fit every limit, but marker expansion exceeds the
        // cumulative decode-byte limit in the final, fixed invariant pass.
        let growingSpan = "\"" + String(repeating: "key", count: 1_000) + "\""
        let growingBody = Data(String(repeating: growingSpan, count: 128).utf8)
        #expect(growingBody.count <= SafeBrokerOutput.maxAcceptedBodyBytes)
        #expect(SafeBrokerOutput.bodyText(growingBody, resolvedToken: "key", maxBytes: Int.max)
            == "<upstream body withheld: output sanitization limit exceeded>")
    }

    @Test("intermediate marker growth has a work cap even with an unlimited output budget")
    func intermediateGrowthIsBounded() {
        // A one-byte token absent from [redacted] yields ten bytes per match.
        // A public separator exercises disjoint matches with retained bytes.
        let body = Data(String(repeating: "kz", count: SafeBrokerOutput.maxAcceptedBodyBytes / 2).utf8)
        let output = SafeBrokerOutput.bodyText(body, resolvedToken: "k", maxBytes: Int.max)
        // This fixture stays below 8 MiB: exact public bytes are retained.
        #expect(output.utf8.count == (SafeBrokerOutput.maxAcceptedBodyBytes / 2) * 11)
        // Adjacent disjoint one-byte occurrences get separate markers, and
        // their total growth exceeds the independent intermediate-text cap.
        let overgrowth = Data(String(repeating: "k", count: SafeBrokerOutput.maxAcceptedBodyBytes).utf8)
        #expect(SafeBrokerOutput.bodyText(overgrowth, resolvedToken: "k", maxBytes: Int.max)
            == "<upstream body withheld: output sanitization limit exceeded>")
    }

    @Test("synchronous helper loop checkpoints deterministically propagate cancellation", arguments: [
        SafeBrokerOutput.Checkpoint.quotedScan(4_096), .literalScan(4_096), .invariantScan(4_096), .truncation(4_096),
    ])
    func helperLoopCancellation(_ target: SafeBrokerOutput.Checkpoint) {
        // No task scheduling race, sleep, counter shared across tasks, or detached
        // work: the selected checkpoint itself throws, including mid-loop work.
        let body = Data(repeating: 0x7A, count: 12_288)
        #expect(throws: CancellationError.self) {
            try SafeBrokerOutput.checkedBodyText(body, resolvedToken: Self.token, maxBytes: 5_000) { checkpoint in
                if checkpoint == target { throw CancellationError() }
            }
        }
    }

    @Test("bounded UTF-8 and JSON codec checkpoints deterministically propagate cancellation", arguments: [
        SafeBrokerOutput.Checkpoint.beforeUTF8Decode, .afterUTF8Decode, .beforeStringDecode, .afterStringDecode,
    ])
    func helperCodecCancellation(_ target: SafeBrokerOutput.Checkpoint) {
        let body = Data(#"{"public":"ok"}"#.utf8)
        #expect(throws: CancellationError.self) {
            try SafeBrokerOutput.checkedBodyText(body, resolvedToken: Self.token, maxBytes: Int.max) { checkpoint in
                if checkpoint == target { throw CancellationError() }
            }
        }
    }

    @Test("bounded JSON string encoder checkpoints deterministically propagate cancellation", arguments: [
        SafeBrokerOutput.Checkpoint.beforeStringEncode, .afterStringEncode,
    ])
    func helperEncoderCancellation(_ target: SafeBrokerOutput.Checkpoint) {
        let body = Data(#"{"echo":"\#(Self.token)"}"#.utf8)
        #expect(throws: CancellationError.self) {
            try SafeBrokerOutput.checkedBodyText(body, resolvedToken: Self.token, maxBytes: Int.max) { checkpoint in
                if checkpoint == target { throw CancellationError() }
            }
        }
    }

    // MARK: - Broker integration and error boundaries

    @Test("both GitHub routes filter a token crossing the response cap", arguments: [CuratedToolBroker.githubGetMeTool, CuratedToolBroker.githubRequestTool])
    func githubRoutesFilterBeforeTruncation(_ tool: String) async throws {
        let prefix = "public:"
        let limit = prefix.utf8.count + "[redacted]".utf8.count
        let http = FixtureHTTP(body: Data((prefix + Self.token + String(repeating: "z", count: limit)).utf8))
        let broker = try makeBroker(http: http, maxBytes: limit)
        let result = await broker.callTool(name: tool, arguments: [
            "method": .string("GET"),
            "path": .string("/repos/public/fixture"),
        ])
        let output = try text(result)
        #expect(!result.isError)
        #expect(output.hasPrefix(prefix + "[redacted]\n[truncated:"))
        let requests = await http.requests
        #expect(requests.count == 1)
        #expect(requests.first?.headers["Authorization"] == "Bearer \(Self.token)")
    }

    @Test("Slack successful bodies use the same escaped-token and boundary filter")
    func slackSuccessFiltersEscapedToken() async throws {
        let token = "canary/token-for-boundary"
        let prefix = #"{"ok":true,"echo":""#
        let body = Data((prefix + #"\u0063anary\/token-for-boundary","public":"padding"}"#).utf8)
        let limit = prefix.utf8.count + "[redacted]".utf8.count
        let broker = try makeBroker(http: FixtureHTTP(body: body), token: token, maxBytes: limit)
        let result = await broker.callTool(name: CuratedToolBroker.slackPostMessageTool, arguments: [
            "channel": .string("fixture-channel"),
            "text": .string("public"),
        ])
        #expect(!result.isError)
        #expect(try text(result).hasPrefix(prefix + "[redacted]\n[truncated:"))
    }

    @Test("HTTP failures withhold all body data for GitHub and Slack")
    func httpErrorsAreStructural() async throws {
        // Whole-body withholding protects unknown/caller-controlled diagnostics
        // too, not just the resolved canary or a particular JSON error key.
        let body = Data(("private body /caller/path " + Self.token).utf8)
        for status in [401, 403, 500] {
            for tool in [CuratedToolBroker.githubGetMeTool, CuratedToolBroker.slackRequestTool] {
                let broker = try makeBroker(http: FixtureHTTP(body: body, status: status))
                let result = await broker.callTool(name: tool, arguments: ["method": .string("chat.postMessage")])
                let service = tool == CuratedToolBroker.githubGetMeTool ? "GitHub" : "Slack"
                #expect(result.isError)
                #expect(try text(result) == "\(service) upstream returned HTTP \(status): [redacted]")
            }
        }
    }

    @Test("arbitrary Slack ok:false error values and extra fields are not echoed")
    func slackArbitraryErrorIsWithheld() async throws {
        // Both error and extra fields contain synthetic private data; the
        // whole failure is classified instead of forwarding any field value.
        let body = Data(#"{"ok":false,"error":"private-\#(Self.token)","private":"/caller/path"}"#.utf8)
        let broker = try makeBroker(http: FixtureHTTP(body: body))
        let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
        #expect(result.isError)
        #expect(try text(result) == "Slack API error.")
    }

    @Test("only the exact channel_not_found compatibility code supplies detailed Slack copy")
    func slackKnownCodeCompatibility() async throws {
        let body = Data(#"{"ok":false,"error":"channel_not_found","private":"\#(Self.token)"}"#.utf8)
        let broker = try makeBroker(http: FixtureHTTP(body: body))
        let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
        #expect(result.isError)
        #expect(try text(result) == "Slack API error: channel_not_found")
    }

    @Test("incorrectly typed Slack error fields cannot escape via decoder diagnostics")
    func slackErrorShapeIsWithheld() async throws {
        let body = Data(#"{"ok":false,"error":{"private":"\#(Self.token)"}}"#.utf8)
        let broker = try makeBroker(http: FixtureHTTP(body: body))
        let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
        #expect(result.isError)
        #expect(try text(result) == "Slack API error.")
    }

    @Test("malformed Slack status documents become fixed errors, not decoder descriptions")
    func slackMalformedStatusIsStructural() async throws {
        // Include nonobjects and every non-Boolean status shape. Private error
        // fields never become apparent success just because ok is absent/null.
        for original in ["not JSON " + Self.token, "null", "[]", "true", "42", #""private""#,
                         #"{"ok":"false","private":"\#(Self.token)"}"#,
                         #"{"ok":1,"error":"private /caller/path?credential=another-value"}"#,
                         #"{"ok":{},"error":"private /caller/path"}"#,
                         #"{"ok":[],"error":"private /caller/path"}"#] {
            let broker = try makeBroker(http: FixtureHTTP(body: Data(original.utf8)))
            let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
            #expect(result.isError)
            #expect(try text(result) == "Slack API error: malformed response.")
        }
    }

    @Test("missing and null Slack status are fixed malformed errors, not diagnostic-body success")
    func slackMissingOrNullStatusIsMalformed() async throws {
        // Intentional compatibility tightening: the old optional-ok success
        // behavior is not safe for malformed private diagnostic envelopes.
        for original in [#"{"public":"ok"}"#,
                         #"{"error":"private /caller/path?credential=another-value"}"#,
                         #"{"ok":null,"error":"private /caller/path?credential=another-value"}"#] {
            let broker = try makeBroker(http: FixtureHTTP(body: Data(original.utf8)))
            let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
            #expect(result.isError)
            #expect(try text(result) == "Slack API error: malformed response.")
        }
    }

    @Test("a typed Boolean Slack ok:true permits a benign successful body")
    func slackPositiveStatusSuccess() async throws {
        let original = #"{"ok":true,"public":"ok"}"#
        let broker = try makeBroker(http: FixtureHTTP(body: Data(original.utf8)))
        let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
        #expect(!result.isError)
        #expect(try text(result) == original)
    }

    @Test("non-2xx HTTP classification precedes Slack ok:false and malformed status decoding")
    func slackHTTPErrorPrecedence() async throws {
        for body in [#"{"ok":false,"error":"channel_not_found"}"#, #"{"ok":null,"error":"private"}"#] {
            let broker = try makeBroker(http: FixtureHTTP(body: Data(body.utf8), status: 503), outputCancellationCheck: { _ in
                throw CancellationError() // No output/Slack decode should occur.
            })
            let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
            #expect(result.isError)
            #expect(try text(result) == "Slack upstream returned HTTP 503: [redacted]")
        }
    }

    @Test("both broker paths accept the exact ceiling and withhold ceiling-plus-one before decoding")
    func brokerAcceptedBodyCeiling() async throws {
        let ceiling = SafeBrokerOutput.maxAcceptedBodyBytes
        for tool in [CuratedToolBroker.githubGetMeTool, CuratedToolBroker.slackRequestTool] {
            let prefix = tool == CuratedToolBroker.slackRequestTool ? #"{"ok":true}"# : "public"
            let original = prefix + String(repeating: " ", count: ceiling - prefix.utf8.count)
            let accepted = try makeBroker(http: FixtureHTTP(body: Data(original.utf8)), maxBytes: Int.max)
            let success = await accepted.callTool(name: tool, arguments: ["method": .string("chat.postMessage")])
            #expect(!success.isError)
            #expect(try text(success) == original)
            var oversized = Data(original.utf8)
            oversized.append(0xFF)
            let rejected = try makeBroker(http: FixtureHTTP(body: oversized), maxBytes: 1, outputCancellationCheck: { _ in
                throw CancellationError() // Any attempted decode changes this result.
            })
            let result = await rejected.callTool(name: tool, arguments: ["method": .string("chat.postMessage")])
            #expect(result.isError)
            #expect(try text(result) == "Upstream response body withheld: accepted size limit exceeded.")
        }
    }

    @Test("broker output-loop cancellation is a fixed error, never a late success body")
    func brokerOutputCheckpointCancellation() async throws {
        let http = FixtureHTTP(body: Data(repeating: 0x7A, count: 12_288))
        let broker = try makeBroker(http: http, outputCancellationCheck: { checkpoint in
            if checkpoint == .literalScan(4_096) { throw CancellationError() }
        })
        let result = await broker.callTool(name: CuratedToolBroker.githubGetMeTool, arguments: [:])
        #expect(result.isError)
        #expect(try text(result) == "Tool call cancelled.")
        #expect(await http.requests.count == 1)
    }

    @Test("Slack decode checkpoints propagate cancellation instead of malformed or success copy", arguments: [
        SafeBrokerOutput.Checkpoint.beforeSlackDecode, .afterSlackDecode, .beforeSlackErrorDecode, .afterSlackErrorDecode,
    ])
    func slackDecodeCheckpointCancellation(_ target: SafeBrokerOutput.Checkpoint) async throws {
        let http = FixtureHTTP(body: Data(#"{"ok":false,"error":"channel_not_found","private":"hidden"}"#.utf8))
        let broker = try makeBroker(http: http, outputCancellationCheck: { checkpoint in
            if checkpoint == target { throw CancellationError() }
        })
        let result = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string("chat.postMessage")])
        #expect(result.isError)
        #expect(try text(result) == "Tool call cancelled.")
        #expect(await http.requests.count == 1)
    }

    @Test("K03 invalid bearer values fail safely with zero HTTP calls on every broker route")
    func invalidBearerCredentialsPreventHTTP() async throws {
        // Generic Keychain lookup remains exact. This consumer, not the native
        // decoder, must reject unsafe headers without trimming or reflecting them.
        let invalid = ["", " ", "\t", "\n", "\r", "\r\n", "synthetic\r\nX-Synthetic: value",
                       "synthetic\0token", " synthetic", "synthetic ", "syn thetic", "syn\tthetic",
                       "=", "==", "=synthetic", "syn=thetic", "syn==thetic", "synthetic:token",
                       "synthetic,token", "synthetic\\token", "synthetic\"token", "é", "synthetic😀",
                       String(repeating: "a", count: SafeBrokerOutput.maxTokenBytes + 1)]
        for token in invalid {
            for tool in [CuratedToolBroker.githubGetMeTool, CuratedToolBroker.githubRequestTool,
                         CuratedToolBroker.slackPostMessageTool, CuratedToolBroker.slackRequestTool] {
                let http = FixtureHTTP(body: Data(#"{"ok":true}"#.utf8))
                let broker = try makeBroker(http: http, token: token)
                let result = await broker.callTool(name: tool, arguments: [
                    "method": .string(tool == CuratedToolBroker.githubRequestTool ? "GET" : "chat.postMessage"),
                    "path": .string("/repos/public/fixture"), "channel": .string("fixture"), "text": .string("public"),
                ])
                #expect(result.isError)
                #expect(try text(result) == "Host secret unavailable.")
                #expect(await http.requests.isEmpty)
            }
        }
    }

    @Test("K03 valid RFC6750 grammar and exact bearer ceiling preserve token bytes and succeed")
    func validBearerCredentialsSucceed() async throws {
        // RFC b64token permits all these core characters and trailing padding;
        // it does not require Base64 decoding or a provider-specific prefix.
        for token in ["synthetic-token", "AZaz09-._~+/", "synthetic=", "synthetic===",
                      String(repeating: "a", count: SafeBrokerOutput.maxTokenBytes)] {
            for tool in [CuratedToolBroker.githubGetMeTool, CuratedToolBroker.slackRequestTool] {
                let http = FixtureHTTP(body: Data(#"{"ok":true,"public":"ok"}"#.utf8))
                let broker = try makeBroker(http: http, token: token)
                let result = await broker.callTool(name: tool, arguments: ["method": .string("chat.postMessage")])
                #expect(!result.isError)
                let requests = await http.requests
                #expect(requests.count == 1)
                #expect(requests.first?.headers["Authorization"] == "Bearer \(token)")
            }
        }
    }

    @Test("caller-controlled tool names, methods, and paths are omitted before credential lookup")
    func callerInputIsNotErrorCopy() async throws {
        // A failing provider and empty HTTP request log also pin that local
        // policy failures do not need a token merely to avoid echoing inputs.
        let http = FixtureHTTP()
        let broker = try makeBroker(http: http, secretFailure: .credentialBackendUnavailable)
        let unknown = await broker.callTool(name: "unknown-" + Self.token, arguments: [:])
        #expect(try text(unknown) == "Unknown tool.")
        let githubMethod = await broker.callTool(name: CuratedToolBroker.githubRequestTool, arguments: [
            "method": .string("TRACE-" + Self.token), "path": .string("/repos/public/fixture"),
        ])
        #expect(try text(githubMethod) == "Policy denied: GitHub method is not allowed.")
        let slackMethod = await broker.callTool(name: CuratedToolBroker.slackRequestTool, arguments: ["method": .string(Self.token)])
        #expect(try text(slackMethod) == "Policy denied: Slack method is not in the host allowlist.")
        let invalidPath = await broker.callTool(name: CuratedToolBroker.githubRequestTool, arguments: [
            "method": .string("GET"), "path": .string(Self.token),
        ])
        #expect(try text(invalidPath) == "Invalid tool arguments: 'path' is required and must start with '/'.")
        let deniedPath = await broker.callTool(name: CuratedToolBroker.githubRequestTool, arguments: [
            "method": .string("GET"), "path": .string("/gists/" + Self.token),
        ])
        #expect(try text(deniedPath) == "Policy denied: GitHub paths must start with '/repos/' (only GET /user is allowed outside that).")
        for result in [unknown, githubMethod, slackMethod, invalidPath, deniedPath] {
            #expect(result.isError)
            #expect(try !text(result).contains(Self.token))
        }
        let requests = await http.requests
        #expect(requests.isEmpty)
    }

    @Test("credential failures, including forged public errors, never publish backend descriptions", arguments: FailureKind.allCases)
    func credentialExceptionsAreStructural(_ kind: FailureKind) async throws {
        let http = FixtureHTTP()
        let broker = try makeBroker(http: http, secretFailure: kind)
        let result = await broker.callTool(name: CuratedToolBroker.githubGetMeTool, arguments: [:])
        #expect(result.isError)
        let expected = kind == .cancellation ? "Tool call cancelled." : "Host secret unavailable."
        #expect(try text(result) == expected)
        let requests = await http.requests
        #expect(requests.isEmpty)
    }

    @Test("HTTP exceptions, including every public broker error case, are fixed-copy failures", arguments: FailureKind.allCases)
    func httpExceptionsAreStructural(_ kind: FailureKind) async throws {
        // Error.localizedDescription is neither echoed nor trusted based on
        // ToolBrokerError type identity. Cancellation is a separate fixed case.
        let http = FixtureHTTP(failure: kind)
        let broker = try makeBroker(http: http)
        let result = await broker.callTool(name: CuratedToolBroker.githubGetMeTool, arguments: [:])
        #expect(result.isError)
        let expected = kind == .cancellation ? "Tool call cancelled." : "Tool call failed."
        #expect(try text(result) == expected)
        let requests = await http.requests
        #expect(requests.count == 1)
    }

    @Test("request encoding exceptions cannot expose secret-bearing coding-path keys")
    func encodingFailureIsStructural() async throws {
        // JSONEncoder rejects nonfinite numbers. Using the canary as the key
        // pins the need to withhold the coding path, not just localized prose.
        let http = FixtureHTTP()
        let broker = try makeBroker(http: http)
        let result = await broker.callTool(name: CuratedToolBroker.githubRequestTool, arguments: [
            "method": .string("POST"),
            "path": .string("/repos/public/fixture/issues"),
            "body": .object([Self.token: .number(.nan)]),
        ])
        #expect(result.isError)
        #expect(try text(result) == "Tool call failed.")
        let requests = await http.requests
        #expect(requests.isEmpty)
    }

    @Test("safe existing automation and service-configuration messages remain compatible")
    func fixedPolicyCompatibility() async throws {
        let broker = try makeBroker(http: FixtureHTTP(), automationAllowed: false, github: false)
        let missing = await broker.callTool(name: CuratedToolBroker.githubGetMeTool, arguments: [:])
        #expect(try text(missing) == "GitHub upstream is not configured on the host.")
        let denied = await broker.callTool(name: CuratedToolBroker.slackPostMessageTool, arguments: [:])
        #expect(try text(denied) == "Policy denied: Slack write operations require automationAllowed on the host.")
        #expect(missing.isError)
        #expect(denied.isError)
    }
}
