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
        let keyBytes = Array(("\"" + key + "\"").utf8)
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
                // Key candidate: match the target key at this position?
                if depth == targetDepth {
                    if matchesKey(bytes, at: i, key: keyBytes) {
                        // Find the ':' after the key (skipping whitespace).
                        var j = i + keyBytes.count
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
                        // Not the member we want (e.g. nested) — continue scan
                        // from after this key string.
                        i += keyBytes.count
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
        return nil
    }

    private static func matchesKey(_ bytes: [UInt8], at i: Int, key: [UInt8]) -> Bool {
        guard i + key.count <= bytes.count else { return false }
        for (offset, k) in key.enumerated() where bytes[i + offset] != k {
            return false
        }
        // Key must END at the quote — byte before position must be the
        // opening quote we matched at `i`.
        return true
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
