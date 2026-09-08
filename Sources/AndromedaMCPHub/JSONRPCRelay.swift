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

    /// Rewrite a client message's request id into the namespaced form
    /// `"<connKey>.<original>"` (string id, original shape preserved inside).
    /// Notifications (id omitted) pass through byte-identical.
    /// `notifications/cancelled` gets its `params.requestId` namespaced too.
    /// A client frame with duplicate top-level ids (or duplicate cancelled
    /// requestIds) — RFC-8259-illegal and a cross-connection routing
    /// hijack vector. Callers reject, never forward.
    public static func clientMessageIsMalformed(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        return JSONIDRewriter.hasDuplicateTopLevelID(in: bytes)
            || JSONIDRewriter.hasDuplicateCancelledRequestID(in: bytes)
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
