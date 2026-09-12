import Foundation

// MARK: - Connection key

/// Stable, short, filename/JSON-safe key for one connected shim.
/// `s<hex>` from a monotonic counter — never a pid (pids recycle).
public struct RelayConnectionKey: Hashable, Sendable, CustomStringConvertible {
    public let value: String
    public init(value: String) {
        self.value = value
    }

    static let prefix = "c"
    public static func make(_ n: UInt64) -> RelayConnectionKey {
        RelayConnectionKey(value: "\(prefix)\(String(n, radix: 36))")
    }

    public var description: String {
        value
    }
}

// MARK: - Relay

/// Pure id-rewriting for both relay directions. No I/O — trivially testable.
public enum JSONRPCRelay: Sendable {
    // MARK: Client → upstream

    /// The hub's verdict on one client frame — every branch is a typed case
    /// so the hub logs each decision without re-inspecting bytes.
    public enum ClientFrameDisposition: Sendable, Equatable {
        /// Forward (rewritten or byte-identical).
        case forward
        /// Drop silently (client roots notifications — see below).
        case dropRootsNotification
        /// Reject with `-32600` (malformed / hijack vector / batch).
        case reject(reason: RejectionReason)

        public enum RejectionReason: String, Sendable, Equatable {
            /// RFC-8259-illegal duplicate id members (hijack vector).
            case duplicateMemberID
            /// Top-level JSON array — JSON-RPC 2.0 batch. MCP (2025-06-18)
            /// dropped batching; a batch has no depth-1 id so it would pass
            /// the namespacer byte-identical and its response ids would
            /// fail hub-key routing and broadcast (Cursor security review).
            case topLevelArray
        }
    }

    /// Policy verdict for a client frame BEFORE any rewriting (Cursor HIGH +
    /// MEDIUM security review): duplicate-id frames are rejected (existing),
    /// top-level arrays (batches) are rejected (new), and
    /// `notifications/roots/list_changed` is dropped (new) — official
    /// `@modelcontextprotocol/server-filesystem` REPLACES its process-global
    /// `allowedDirectories` allowlist from client roots; forwarding that
    /// notification lets any connected session widen/replace the sandbox
    /// every other session shares (last-writer-wins). The hub — not any
    /// client — owns the sandbox: it is pinned at spawn time via CLI args.
    public static func dispositionForClientFrame(_ data: Data) -> ClientFrameDisposition {
        let bytes = [UInt8](data)
        // All four RFC-8259 whitespace bytes are skipped (Codex round 3):
        // LineAssembler strips CR only at line ENDS, so a leading \r could
        // otherwise hide a batch array from the first-byte scan.
        guard let first = bytes.first(where: { !Self.isJSONWhitespace($0) }) else {
            return .reject(reason: .topLevelArray)
        }
        if first == UInt8(ascii: "[") {
            return .reject(reason: .topLevelArray)
        }
        if JSONIDRewriter.hasDuplicateTopLevelID(in: bytes)
            || JSONIDRewriter.hasDuplicateCancelledRequestID(in: bytes)
        {
            return .reject(reason: .duplicateMemberID)
        }
        if isRootsListChangedNotification(bytes) {
            return .dropRootsNotification
        }
        return .forward
    }

    /// RFC 8259 whitespace: space, tab, LF, CR.
    static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    /// True when the frame is a `notifications/roots/list_changed`
    /// notification (no id, that method) — the client-driven roots push the
    /// hub never forwards.
    static func isRootsListChangedNotification(_ bytes: [UInt8]) -> Bool {
        guard JSONIDRewriter.topLevelIDSpan(in: bytes) == nil,
              let methodSpan = JSONIDRewriter.findMemberValueSpan(
                  in: bytes, key: "method", searchTopLevelOnly: true
              )
        else { return false }
        let raw = Array(bytes[methodSpan.start ..< methodSpan.end])
        // The member value is a JSON string; compare content against the
        // exact method name (quotes included — no allocation in the happy
        // path of other methods).
        let expected = Array(#""notifications/roots/list_changed""#.utf8)
        return raw == expected
    }

    /// True when an UPSTREAM frame is a server-initiated `roots/*` request
    /// (id present, method `roots/list` or `roots/list_changed` subscription
    /// shape). Official server-filesystem harvests client roots into its
    /// global allowlist; the hub answers these itself with EMPTY roots so
    /// the spawn-time sandbox stays the only authority, and never
    /// broadcasts the request to connected shims.
    public static func isUpstreamRootsRequest(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard JSONIDRewriter.topLevelIDSpan(in: bytes) != nil,
              let methodSpan = JSONIDRewriter.findMemberValueSpan(
                  in: bytes, key: "method", searchTopLevelOnly: true
              )
        else { return false }
        let raw = String(decoding: bytes[methodSpan.start ..< methodSpan.end], as: UTF8.self)
        return raw == #""roots/list""# || raw == #""roots/list_changed""#
    }

    /// Rewrite a client message's request id into the namespaced form
    /// `"<connKey>.<original>"` (string id, original shape preserved inside).
    /// Notifications (id omitted) pass through byte-identical.
    /// `notifications/cancelled` gets its `params.requestId` namespaced too.
    /// A client frame with duplicate top-level ids (or duplicate cancelled
    /// requestIds) — RFC-8259-illegal and a cross-connection routing
    /// hijack vector. Callers reject, never forward.
    public static func clientMessageIsMalformed(_ data: Data) -> Bool {
        if case .reject = dispositionForClientFrame(data) {
            return true
        }
        return false
    }

    /// Typed outcome of preparing one client frame for the upstream: the
    /// bytes to forward plus WHICH rewrites were applied, so the hub can
    /// log each decision point without re-scanning the frame.
    public struct ClientRelayOutcome: Sendable, Equatable {
        /// The frame to write upstream (id and/or cancelled requestId namespaced).
        public let frame: Data
        /// True when a top-level request id was rewritten into the composite form.
        public let namespacedID: Bool
        /// True when a `notifications/cancelled` `params.requestId` was rewritten.
        public let namespacedCancelledRequestID: Bool
    }

    /// Prepare one client frame for the upstream (namespacing + outcome flags).
    public static func relayClientMessage(
        _ data: Data, connection: RelayConnectionKey
    ) -> ClientRelayOutcome {
        let bytes = [UInt8](data)
        return ClientRelayOutcome(
            frame: namespaceClientMessage(data, connection: connection),
            namespacedID: JSONIDRewriter.topLevelIDSpan(in: bytes) != nil,
            namespacedCancelledRequestID: JSONIDRewriter.cancelledRequestIDSpan(in: bytes) != nil
        )
    }

    public static func namespaceClientMessage(_ data: Data, connection: RelayConnectionKey) -> Data {
        let bytes = [UInt8](data)
        var idReplacement: [UInt8]? = nil
        var cancelledReplacement: [UInt8]? = nil

        if let span = JSONIDRewriter.topLevelIDSpan(in: bytes) {
            let original = Array(bytes[span.start ..< span.end])
            // Wrap the original (number or string) inside our composite string.
            var composite = Array("\"".utf8)
            composite += Array(connection.value.utf8)
            composite += Array(".".utf8)
            if original.first == UInt8(ascii: "\"") {
                composite += Array(original[1 ..< (original.count - 1)])
            } else {
                composite += original
            }
            composite += Array("\"".utf8)
            idReplacement = composite
        }

        if let span = JSONIDRewriter.cancelledRequestIDSpan(in: bytes) {
            let original = Array(bytes[span.start ..< span.end])
            var composite = Array("\"".utf8)
            composite += Array(connection.value.utf8)
            composite += Array(".".utf8)
            if original.first == UInt8(ascii: "\"") {
                composite += Array(original[1 ..< (original.count - 1)])
            } else {
                composite += original
            }
            composite += Array("\"".utf8)
            cancelledReplacement = composite
        }

        return JSONIDRewriter.rewrite(
            data, idReplacement: idReplacement, cancelledRequestIDReplacement: cancelledReplacement
        )
    }

    // MARK: Upstream → clients

    /// A hub-issued connection key: nonempty, prefix + base-36 counter.
    /// (Foreign dotted ids — e.g. server-initiated request ids — fail this
    /// and broadcast instead of routing to a nonexistent connection.)
    static func isHubIssuedKey(_ key: String) -> Bool {
        guard key.hasPrefix(RelayConnectionKey.prefix.description), key.count > 1 else {
            return false
        }
        let counter = key.dropFirst(RelayConnectionKey.prefix.description.count)
        return counter.allSatisfy { $0.isNumber || ($0.isLetter && $0.isLowercase) }
    }

    /// Route an upstream message: namespaced ids split back to their
    /// connection; anything else broadcasts.
    public static func routeUpstreamMessage(_ data: Data) -> (key: String, original: Data)? {
        // Broadcasting is the caller's fallback; this returns a directed
        // route when the id carries our composite form.
        let bytes = [UInt8](data)
        guard let span = JSONIDRewriter.topLevelIDSpan(in: bytes) else { return nil }
        let value = Array(bytes[span.start ..< span.end])
        guard value.first == UInt8(ascii: "\""), value.last == UInt8(ascii: "\""),
              value.count >= 2
        else { return nil }
        let inner = String(decoding: value[1 ..< (value.count - 1)], as: UTF8.self)
        guard let dot = inner.firstIndex(of: ".") else { return nil }
        let key = String(inner[..<dot])
        // Strict routing (Codex P2): only keys this hub issued — the
        // connection prefix followed by base-36 counter characters.
        // Foreign dotted ids ("foo.bar" from server-initiated requests)
        // broadcast instead of directing to a nonexistent connection.
        guard Self.isHubIssuedKey(key) else { return nil }

        // Rebuild with the original id bytes (the remainder after "key.").
        // A purely numeric remainder restores BARE (the original id was a
        // JSON number); anything else restores as a string id.
        var original = bytes
        let remainderString = String(inner[inner.index(after: dot)...])
        let isNumeric = !remainderString.isEmpty
            && remainderString.allSatisfy { "0123456789.eE+-".contains($0) }
            && remainderString.contains(where: \.isNumber)
        let restored: [UInt8] = isNumeric
            ? Array(remainderString.utf8)
            : Array(("\"" + remainderString + "\"").utf8)
        original.replaceSubrange(span.start ..< span.end, with: restored)
        return (key, Data(original))
    }
}

// MARK: - Hub-issued error frames

/// One hub-issued JSON-RPC 2.0 error response, as a typed value instead of
/// a hand-written wire literal (canon: enums over strings, typed payloads).
///
/// The `id` member is REQUIRED on responses and MUST be `null` — not
/// absent — when the request id could not be determined (the hub rejects
/// frames before it has parsed an id out of them). Synthesized Codable
/// conformance would `encodeIfPresent` and silently DROP the key, changing
/// the wire format, so `encode(to:)` is hand-written and always writes id.
/// Prior art: `@EncodeNull` in AndromedaMCP/RPC.swift (internal to that
/// package — not visible here, reimplemented inline via `encodeNil`).
public struct JSONRPCErrorFrame: Codable, Sendable, Equatable {
    /// The JSON-RPC protocol member — always "2.0".
    public let jsonrpc: String
    /// The request id this error answers. `nil` means "unknown request id"
    /// and encodes as a PRESENT `"id":null` member (see encode(to:)).
    public let id: JSONRPCRequestID?
    /// The error object (code + message).
    public let error: ErrorObject

    public init(id: JSONRPCRequestID?, code: Int, message: String) {
        jsonrpc = "2.0"
        self.id = id
        error = ErrorObject(code: code, message: message)
    }

    public struct ErrorObject: Codable, Sendable, Equatable {
        public let code: Int
        public let message: String

        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, error
    }

    /// Canonical single-line encoding with members in `jsonrpc,id,error`
    /// order and NO key reordering — byte-equal to the hand-written wire
    /// literals this type replaced.
    ///
    /// Why not `JSONEncoder`: on this toolchain it emits object members in
    /// a per-process randomized key order (a custom `encode(to:)` does NOT
    /// pin it), and it escapes `/` as `\/`. Either alone would change the
    /// wire bytes the hub's peers already parse. The writer below writes
    /// the members in declaration order, strings JSON-escaped via the same
    /// encoder (so escaping stays correct) but order fixed by construction.
    public func canonicalData() throws -> Data {
        try Self.encodeCanonical(self)
    }

    /// Byte-stable writer for hub-issued error frames.
    ///
    /// Encodes one frame as `{"jsonrpc":…,"id":…,"error":{"code":…,"message":…}}` —
    /// members in that fixed order, `/` NOT escaped. A JSON-escaped, quoted
    /// string (`"…"`) is delegated to JSONEncoder so the escape set stays
    /// correct by construction.
    static func encodeCanonical(_ frame: JSONRPCErrorFrame) throws -> Data {
        var out = Data(#"{"jsonrpc":"#.utf8)
        try out.append(contentsOf: escapedJSONString(frame.jsonrpc))
        out.append(contentsOf: Data(#","id":"#.utf8))
        switch frame.id {
        case .none: out.append(contentsOf: Data("null".utf8)) // present, never absent
        case let .some(id): try out.append(contentsOf: Self.encodedID(id))
        }
        out.append(contentsOf: Data(#","error":{"code":"#.utf8))
        out.append(contentsOf: String(frame.error.code).data(using: .utf8) ?? Data())
        out.append(contentsOf: Data(#","message":"#.utf8))
        try out.append(contentsOf: escapedJSONString(frame.error.message))
        out.append(contentsOf: Data("}}".utf8))
        return out
    }

    /// A JSON-escaped, quoted string (`"…"`) — JSONEncoder handles the
    /// escape set; escaping correctness is not hand-rolled. Slashes stay
    /// unescaped, matching the hand-written literals this writer replaces.
    private static func escapedJSONString(_ string: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(string)
    }

    private static func encodedID(_ id: JSONRPCRequestID) throws -> Data {
        switch id {
        case let .number(number):
            String(number).data(using: .utf8) ?? Data()
        case let .string(string):
            try escapedJSONString(string)
        }
    }

    /// Codable conformance, retained for decode/round-trip use.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        // Always write id — a plain optional would omit the key when nil.
        try container.encodeNilIfNilOrValue(id, forKey: .id)
        try container.encode(error, forKey: .error)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        // `null` and "key absent" both decode to nil; the distinction is
        // irrelevant for hub-issued frames (we always issue null ids today)
        // but decoding accepts either so the type is a usable Codable
        // citizen for round-trip tests.
        id = try container.decodeIfPresent(JSONRPCRequestID.self, forKey: .id)
        error = try container.decode(ErrorObject.self, forKey: .error)
    }
}

extension KeyedEncodingContainerProtocol {
    /// Encodes `value` when non-nil, otherwise writes a present `null` —
    /// the `@EncodeNull` semantics without a property wrapper (the prior
    /// art in AndromedaMCP is package-internal and not importable here).
    mutating func encodeNilIfNilOrValue(
        _ value: JSONRPCRequestID?, forKey key: Self.Key
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

/// A JSON-RPC request id in its two legal wire shapes (number or string).
public enum JSONRPCRequestID: Codable, Sendable, Equatable, Hashable {
    case number(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .number(number)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        throw DecodingError.typeMismatch(
            JSONRPCRequestID.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected number or string request id"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(number): try container.encode(number)
        case let .string(string): try container.encode(string)
        }
    }
}

/// The errors the hub itself issues. Each case owns its JSON-RPC code —
/// no magic numbers at the call sites (canon: codes belong to the cases).
public enum HubJSONRPCError: Sendable, Equatable {
    /// The upstream process could not be spawned or has exhausted its
    /// restart budget — the reply tells the agent host instead of hanging.
    case upstreamUnavailable
    /// The client frame was rejected as malformed before forwarding.
    /// `duplicate` names the RFC-8259-illegal duplicate member it carried.
    case malformedFrame(duplicate: String)
    /// The client frame was a JSON-RPC 2.0 batch (top-level array) — MCP
    /// (2025-06-18) dropped batching, and a batch bypasses depth-1 id
    /// namespacing (Cursor security review). Rejected, never forwarded.
    case batchFrameRejected
    /// The hub answered a server-initiated `roots/*` request itself with
    /// empty roots — the hub, not any client, owns the sandbox allowlist
    /// (Cursor security review: client roots are last-writer-wins on
    /// server-filesystem's process-global allowedDirectories).
    case rootsOwnedByHub

    /// Canonical member name the hub reports when it rejects a frame
    /// without distinguishing WHICH member was duplicated (both today's
    /// rejection paths are id-member attacks; see d72ddcf).
    public static let duplicateMemberID = "id"

    /// The hub-issued errors, for exhaustive (CaseIterable-style) testing.
    /// Not a synthesized `CaseIterable` conformance: `malformedFrame`
    /// carries a payload, so the canonical instance below pins the exact
    /// representative the wire depends on.
    public static var allCases: [HubJSONRPCError] {
        [
            .upstreamUnavailable,
            .malformedFrame(duplicate: duplicateMemberID),
            .batchFrameRejected,
            .rootsOwnedByHub,
        ]
    }

    /// The representative instance per constructor (payload cases use the
    /// canonical payload) — lets tests iterate constructors, not payloads.
    public var canonical: HubJSONRPCError {
        switch self {
        case .upstreamUnavailable: .upstreamUnavailable
        case .malformedFrame: .malformedFrame(duplicate: Self.duplicateMemberID)
        case .batchFrameRejected: .batchFrameRejected
        case .rootsOwnedByHub: .rootsOwnedByHub
        }
    }

    /// JSON-RPC 2.0 reserved error codes (the standard's -32600..-32699 band).
    public var code: Int {
        switch self {
        case .upstreamUnavailable: -32603 // internal error: hub cannot reach upstream
        case .malformedFrame: -32600 // invalid request: malformed frame
        case .batchFrameRejected: -32600 // invalid request: batch frames unsupported
        case .rootsOwnedByHub: -32603 // internal error: hub policy reply
        }
    }

    /// Human-readable message, stable wire content (byte-equality tested).
    public var message: String {
        switch self {
        case .upstreamUnavailable:
            "mcp-hub: upstream unavailable (restart budget exhausted)"
        case let .malformedFrame(duplicate):
            "mcp-hub: malformed frame (duplicate \(duplicate) members rejected)"
        case .batchFrameRejected:
            "mcp-hub: batch frames rejected (MCP 2025-06-18 dropped batching)"
        case .rootsOwnedByHub:
            "mcp-hub: roots are hub-owned (spawn-time sandbox)"
        }
    }

    /// The error frame for this hub-issued error.
    ///
    /// - Parameter explicitNullID: hub-issued errors answer an UNKNOWN
    ///   request id (the hub rejects or fails the frame before it has a
    ///   trustworthy id to echo), and JSON-RPC 2.0 requires the `id`
    ///   member on responses be a PRESENT `"id":null` — never omitted.
    ///   The frame encoder always writes it; the flag states that law at
    ///   the call site, and `false` is a programming error (an omitted id
    ///   would silently change the wire format).
    public func frame(explicitNullID: Bool = true) -> JSONRPCErrorFrame {
        assert(explicitNullID, "hub-issued error frames must carry an explicit null id")
        return JSONRPCErrorFrame(id: nil, code: code, message: message)
    }

    /// A SUCCESS reply the hub issues itself — `roots/list` is answered
    /// with EMPTY roots (the sandbox is spawn-time, hub-owned), so the
    /// frame echoes the upstream's request id and carries `{"roots":[]}`.
    /// Canonical writer, fixed member order, byte-stable.
    public static func emptyRootsResult(id: JSONRPCRequestID) throws -> Data {
        var out = Data(#"{"jsonrpc":"2.0","id":"#.utf8)
        switch id {
        case let .number(number): out.append(contentsOf: String(number).data(using: .utf8) ?? Data())
        case let .string(string):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            try out.append(contentsOf: encoder.encode(string))
        }
        out.append(contentsOf: Data(#","result":{"roots":[]}}"#.utf8))
        return out
    }

    /// The error frame encoded as wire bytes — byte-identical to the raw
    /// string literals this type replaced (asserted by tests). Uses the
    /// frame's canonical writer, NOT JSONEncoder, whose key order is
    /// per-process randomized and which escapes `/` — either would change
    /// the wire format the hub's peers already parse.
    public func encoded() -> Data {
        // swiftlint:disable:next force_try
        try! frame(explicitNullID: true).canonicalData()
    }
}

// MARK: - Byte-level id rewriter

/// Raw-JSON id rewriter. Scans for the top-level `"id"` key and the
/// `params.requestId` key (cancelled notifications), replacing their value
/// spans while preserving every other byte.
///
/// JSON objects are unordered; the rewriter locates the top level by
/// tracking brace depth (strings escaped correctly), so `"id"` inside a
/// nested `params` object is not confused with the top-level one.
enum JSONIDRewriter: Sendable {
    struct Span: Equatable, Sendable {
        let start: Int // byte offset of the value's first byte
        let end: Int // byte offset one past the value's last byte
    }

    /// Finds the top-level `"id"` member's value span, if present.
    /// A key that is PRESENT with value `null` is reported (caller decides).
    static func topLevelIDSpan(in bytes: [UInt8]) -> Span? {
        findMemberValueSpan(in: bytes, key: "id", searchTopLevelOnly: true)
    }

    /// True when the top level carries MORE THAN ONE `"id"` member —
    /// duplicate object keys are RFC-8259-illegal, and parsers disagree
    /// on which one wins (node: last-key-wins). A second unnamespaced id
    /// could survive our first-span rewrite and hijack cross-connection
    /// routing (Cursor security review 3960584548) — such frames are
    /// rejected, never forwarded.
    static func hasDuplicateTopLevelID(in bytes: [UInt8]) -> Bool {
        memberCount(in: bytes, key: "id", targetDepth: 1) > 1
    }

    /// Same check for `params."requestId"` (cancelled hijack variant).
    static func hasDuplicateCancelledRequestID(in bytes: [UInt8]) -> Bool {
        guard let paramsSpan = findMemberValueSpan(in: bytes, key: "params", searchTopLevelOnly: true),
              paramsSpan.isObjectStart(in: bytes)
        else { return false }
        let offset = paramsSpan.start + 1
        let sub = Array(bytes[offset ..< (paramsSpan.end - 1)])
        return memberCount(in: sub, key: "requestId", targetDepth: 0) > 1
    }

    /// Counts occurrences of `"key":` members at the given depth.
    static func memberCount(in bytes: [UInt8], key: String, targetDepth: Int) -> Int {
        var i = 0
        var depth = 0
        var inString = false
        var escaped = false
        var count = 0

        while i < bytes.count {
            let b = bytes[i]
            if inString {
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    inString = false
                }
                i += 1
                continue
            }
            switch b {
            case UInt8(ascii: "\""):
                if depth == targetDepth, let parsed = parseKeyString(bytes, at: i),
                   parsed.decoded == key
                {
                    var j = parsed.end
                    skipWhitespace(bytes, from: &j)
                    if j < bytes.count, bytes[j] == UInt8(ascii: ":") {
                        count += 1
                        i = j + 1
                        continue
                    }
                }
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            default:
                break
            }
            i += 1
        }
        return count
    }

    /// Finds `params."requestId"` value span (for cancelled notifications).
    /// The params object's INNER bytes (braces stripped) have their members
    /// at depth 0 — the inner scan targets depth 0.
    static func cancelledRequestIDSpan(in bytes: [UInt8]) -> Span? {
        guard let paramsSpan = findMemberValueSpan(in: bytes, key: "params", searchTopLevelOnly: true),
              paramsSpan.isObjectStart(in: bytes)
        else { return nil }
        let offset = paramsSpan.start + 1
        let sub = Array(bytes[offset ..< (paramsSpan.end - 1)])
        return findMemberValueSpan(in: sub, key: "requestId", targetDepth: 0)
            .map { Span(start: offset + $0.start, end: offset + $0.end) }
    }

    /// Replaces both spans (id first, then requestId — offsets adjusted).
    static func rewrite(
        _ data: Data,
        idReplacement: [UInt8]?,
        cancelledRequestIDReplacement: [UInt8]?
    ) -> Data {
        var bytes = [UInt8](data)

        if let idSpan = topLevelIDSpan(in: bytes), let replacement = idReplacement {
            bytes.replaceSubrange(idSpan.start ..< idSpan.end, with: replacement)
        }
        if let cancelledSpan = cancelledRequestIDSpan(in: bytes),
           let replacement = cancelledRequestIDReplacement
        {
            // Recompute after the id replacement shifted offsets.
            if let fresh = cancelledRequestIDSpan(in: bytes) {
                _ = cancelledSpan
                bytes.replaceSubrange(fresh.start ..< fresh.end, with: replacement)
            }
        }
        return Data(bytes)
    }

    // MARK: - Scanner

    /// Legacy entry point: members of the root object live at depth 1.
    static func findMemberValueSpan(in bytes: [UInt8], key: String, searchTopLevelOnly: Bool) -> Span? {
        findMemberValueSpan(in: bytes, key: key, targetDepth: searchTopLevelOnly ? 1 : 0)
    }

    /// Generic: find `"key":` at the given brace depth and return the
    /// value's byte span.
    static func findMemberValueSpan(in bytes: [UInt8], key: String, targetDepth: Int) -> Span? {
        var i = 0
        var depth = 0
        var inString = false
        var escaped = false

        while i < bytes.count {
            let b = bytes[i]

            if inString {
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    inString = false
                }
                i += 1
                continue
            }

            switch b {
            case UInt8(ascii: "\""):
                // Key candidate: parse the full string (escape-aware) and
                // compare the decoded key.
                if depth == targetDepth, let parsed = parseKeyString(bytes, at: i),
                   parsed.decoded == key
                {
                    var j = parsed.end
                    skipWhitespace(bytes, from: &j)
                    if j < bytes.count, bytes[j] == UInt8(ascii: ":") {
                        j += 1
                        skipWhitespace(bytes, from: &j)
                        let valueStart = j
                        let valueEnd = endOfValue(bytes, from: j)
                        if depth == targetDepth {
                            return Span(start: valueStart, end: valueEnd)
                        }
                    }
                    // Matched key but no ':' — skip past the key string.
                    i = parsed.end
                    continue
                }
                inString = true

            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1

            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1

            default:
                break
            }
            i += 1
        }
        return nil
    }

    /// Parses the JSON string starting at the opening quote `i` and returns
    /// its decoded key plus the index just past the closing quote. Handles
    /// the full escape set (`\uXXXX` incl. surrogate pairs). Literal-byte
    /// key matching missed Unicode-escaped members (`"\u0069d"`) — RFC 8259
    /// decodes those to the same key, so a duplicate could bypass the
    /// duplicate-id guard and hijack cross-connection routing (Cursor
    /// security follow-up to 3960584548).
    static func parseKeyString(_ bytes: [UInt8], at i: Int) -> (decoded: String, end: Int)? {
        guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { return nil }
        var units: [UInt16] = []
        var j = i + 1
        while j < bytes.count {
            let b = bytes[j]
            switch b {
            case UInt8(ascii: "\""):
                let decoded = String(decoding: units, as: UTF16.self)
                return (decoded, j + 1)
            case UInt8(ascii: "\\"):
                let next = j + 1 < bytes.count ? bytes[j + 1] : UInt8(ascii: " ")
                switch next {
                case UInt8(ascii: "\""): units.append(0x22); j += 2
                case UInt8(ascii: "\\"): units.append(0x5C); j += 2
                case UInt8(ascii: "/"): units.append(0x2F); j += 2
                case UInt8(ascii: "b"): units.append(0x08); j += 2
                case UInt8(ascii: "f"): units.append(0x0C); j += 2
                case UInt8(ascii: "n"): units.append(0x0A); j += 2
                case UInt8(ascii: "r"): units.append(0x0D); j += 2
                case UInt8(ascii: "t"): units.append(0x09); j += 2
                case UInt8(ascii: "u"):
                    guard let (unit, end) = hex4(bytes, at: j + 2) else { return nil }
                    units.append(unit)
                    j = end
                    // Surrogate pair: lead followed by `\uXXXX` low.
                    if UTF16.isLeadSurrogate(unit), j + 1 < bytes.count,
                       bytes[j] == UInt8(ascii: "\\"), bytes[j + 1] == UInt8(ascii: "u"),
                       let (low, lowEnd) = hex4(bytes, at: j + 2), UTF16.isTrailSurrogate(low)
                    {
                        units.append(low)
                        j = lowEnd
                    }
                default:
                    return nil
                }
            default:
                units.append(UInt16(b))
                j += 1
            }
        }
        return nil
    }

    private static func hex4(_ bytes: [UInt8], at start: Int) -> (UInt16, Int)? {
        guard start + 4 <= bytes.count else { return nil }
        var value: UInt16 = 0
        for offset in 0 ..< 4 {
            guard let digit = Character(Unicode.Scalar(bytes[start + offset])).hexDigitValue
            else { return nil }
            value = value << 4 | UInt16(digit)
        }
        return (value, start + 4)
    }

    private static func skipWhitespace(_ bytes: [UInt8], from j: inout Int) {
        while j < bytes.count,
              bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t")
              || bytes[j] == UInt8(ascii: "\n") || bytes[j] == UInt8(ascii: "\r")
        {
            j += 1
        }
    }

    /// End offset (exclusive) of a JSON value starting at `start`:
    /// string (with escapes), number/keyword (delimiter-run), or bracketed.
    private static func endOfValue(_ bytes: [UInt8], from start: Int) -> Int {
        guard start < bytes.count else { return start }
        var i = start
        switch bytes[i] {
        case UInt8(ascii: "\""):
            i += 1
            var escaped = false
            while i < bytes.count {
                let b = bytes[i]
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    return i + 1
                }
                i += 1
            }
            return i
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var inString = false
            var esc = false
            while i < bytes.count {
                let b = bytes[i]
                if inString {
                    if esc {
                        esc = false
                    } else if b == UInt8(ascii: "\\") {
                        esc = true
                    } else if b == UInt8(ascii: "\"") {
                        inString = false
                    }
                } else {
                    switch b {
                    case UInt8(ascii: "\""): inString = true
                    case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                    case UInt8(ascii: "}"), UInt8(ascii: "]"):
                        depth -= 1
                        if depth == 0 {
                            return i + 1
                        }
                    default: break
                    }
                }
                i += 1
            }
            return i
        default:
            // number / true / false / null — run to delimiter.
            while i < bytes.count {
                let b = bytes[i]
                if b == UInt8(ascii: ",") || b == UInt8(ascii: "}")
                    || b == UInt8(ascii: "]") || b == UInt8(ascii: " ")
                    || b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r")
                    || b == UInt8(ascii: "\t")
                {
                    return i
                }
                i += 1
            }
            return i
        }
    }
}

// MARK: - Value-shape helpers

enum RelayJSON: Sendable {
    /// Decodes the top-level object for structural inspection only.
    static func decodeObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The raw bytes of the top-level `id` value (verbatim shape).
    static func idValueBytes(in data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let span = JSONIDRewriter.topLevelIDSpan(in: bytes) else { return nil }
        return Data(bytes[span.start ..< span.end])
    }

    /// True when the message is a notification (id key absent).
    static func isNotification(_ data: Data) -> Bool {
        JSONIDRewriter.topLevelIDSpan(in: [UInt8](data)) == nil
    }

    /// Namespaced replacement bytes for a connection: `"<conn>.<id-bytes>"`.
    static func namespacedID(original: [UInt8], connection: RelayConnectionKey) -> [UInt8] {
        var out = Array("\"".utf8)
        out += Array(connection.value.utf8)
        out += Array(".".utf8)
        out += original
        out += Array("\"".utf8)
        return out
    }

    /// Splits a namespaced string id `"<conn>.<rest>"`; returns the original
    /// id bytes when the prefix matches, else nil (foreign id).
    static func splitNamespaced(_ bytes: [UInt8], connection: RelayConnectionKey) -> [UInt8]? {
        // bytes include surrounding quotes for string ids.
        guard bytes.first == UInt8(ascii: "\""), bytes.last == UInt8(ascii: "\""),
              bytes.count >= 2
        else { return nil }
        let inner = Array(bytes[1 ..< (bytes.count - 1)])
        let prefix = Array(connection.value.utf8) + Array(".".utf8)
        guard inner.count > prefix.count, Array(inner[0 ..< prefix.count]) == prefix else {
            return nil
        }
        var out = Array("\"".utf8)
        out += Array(inner[prefix.count...])
        out += Array("\"".utf8)
        return out
    }
}

extension JSONIDRewriter.Span {
    func isObjectStart(in bytes: [UInt8]) -> Bool {
        start < bytes.count && bytes[start] == UInt8(ascii: "{")
    }
}
