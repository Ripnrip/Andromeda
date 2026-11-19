import Foundation

/// Call-local filtering for the one resolved token, not generic DLP. Coverage
/// is exact UTF-8 literal matches and complete, valid JSON string literals.
/// Foundation owns JSON escaping/unescaping; no normalization or recursive
/// decoding is attempted. A token already cut by transport is not recoverable.
struct SafeBrokerOutput: Sendable {
    /// Conservative local acceptance policy, independent of the output budget
    /// and of an injected transport. The root transport defaults to 8 MiB;
    /// this draft accepts at most 1 MiB, inclusive, before any body decoding.
    static let maxAcceptedBodyBytes = 1_024 * 1_024
    static let maxTokenBytes = 4_096
    static let maxQuotedSpanBytes = 64 * 1_024
    static let maxQuotedSpans = 4_096
    private static let maxSanitizedBytes = 8 * 1_024 * 1_024
    private static let checkpointStride = 4_096

    /// Internal, synchronous test seam. No tasks, suspension, timers, shared
    /// handlers, or detached work. Scan offsets are bytes (quotedScan uses
    /// accumulated scalar UTF-8 widths). Byte loops check every 4096 bytes;
    /// scalar loops can overshoot that stride by at most three UTF-8 bytes.
    enum Checkpoint: Sendable, Equatable {
        case beforeUTF8Decode, afterUTF8Decode
        case quotedScan(Int)
        case beforeStringDecode, afterStringDecode
        case beforeStringEncode, afterStringEncode
        case literalScan(Int), invariantScan(Int), truncation(Int)
        case beforeSlackDecode, afterSlackDecode
        case beforeSlackErrorDecode, afterSlackErrorDecode
    }
    typealias CancellationCheck = @Sendable (Checkpoint) throws -> Void

    private enum FilteringFailure: Error {
        case workLimit, invariant
    }

    /// Preserves the original internal nonthrowing helper seam for pure callers.
    /// Broker calls use checkedBodyText so CancellationError remains a tool error.
    static func bodyText(_ body: Data, resolvedToken: String, maxBytes: Int) -> String {
        do {
            return try checkedBodyText(body, resolvedToken: resolvedToken, maxBytes: maxBytes) { _ in
                try Task.checkCancellation()
            }
        } catch {
            // Cancellation does not release original data. This convenience
            // seam has no error flag; the broker uses the throwing seam below.
            return ""
        }
    }

    /// Withholds oversized bodies wholesale, never a pre-redaction prefix.
    /// There are two fixed quoted-span passes (filter then invariant), one raw
    /// replacement pass, and bounded invariant scans; no replacement retries.
    /// Primitive String/Data/Foundation operations are not preemptible, but
    /// their inputs are capped. Checks bracket UTF-8/JSON codec operations.
    static func checkedBodyText(
        _ body: Data,
        resolvedToken: String,
        maxBytes: Int,
        checkCancellation: CancellationCheck
    ) throws -> String {
        // Materialize only a bounded token prefix, even with hostile injection.
        let tokenBytes = Array(resolvedToken.utf8.prefix(maxTokenBytes + 1))
        guard tokenBytes.count <= maxTokenBytes else { return "" }
        let pattern = LiteralPattern(bytes: tokenBytes)
        do {
            guard body.count <= maxAcceptedBodyBytes else {
                return try notice("<upstream body withheld: accepted size limit exceeded>", pattern: pattern, check: checkCancellation)
            }
            try checkCancellation(.beforeUTF8Decode)
            let decoded = String(data: body, encoding: .utf8)
            try checkCancellation(.afterUTF8Decode)
            guard let text = decoded else {
                return try notice("<non-utf8 body: \(body.count) bytes>", pattern: pattern, check: checkCancellation)
            }
            // The two marker alphabets are disjoint, so a nonempty token cannot
            // occur in both. Marker selection is bounded, not trial replacement.
            let ordinaryMarker = "[redacted]"
            let replacement = try pattern.contains(Array(ordinaryMarker.utf8), check: checkCancellation) ? "■" : ordinaryMarker
            let jsonFiltered = try quotedStrings(text, pattern: pattern, replacement: replacement, validateOnly: false, check: checkCancellation)
            let filtered = try pattern.redact(jsonFiltered, replacement: replacement, check: checkCancellation)
            guard try !pattern.contains(Array(filtered.utf8), check: checkCancellation) else {
                throw FilteringFailure.invariant
            }
            // Raw replacement can change quoted boundaries. Recheck recognized
            // decoded spans after it, not merely the decoded input strings.
            _ = try quotedStrings(filtered, pattern: pattern, replacement: replacement, validateOnly: true, check: checkCancellation)
            let limit = max(0, maxBytes)
            let sanitizedBytes = filtered.utf8.count
            let output: String
            if sanitizedBytes > limit {
                output = try utf8Prefix(filtered, maxBytes: limit, check: checkCancellation)
                    + "\n[truncated: upstream body was \(body.count) bytes, sanitized body was \(sanitizedBytes) bytes, limit is \(limit)]"
            } else {
                output = filtered
            }
            // Metadata or its boundary with the prefix must not manufacture a
            // literal token either. If it does, drop the whole output once.
            guard try !pattern.contains(Array(output.utf8), check: checkCancellation) else {
                throw FilteringFailure.invariant
            }
            return output
        } catch is CancellationError {
            throw CancellationError()
        } catch FilteringFailure.workLimit {
            return try notice("<upstream body withheld: output sanitization limit exceeded>", pattern: pattern, check: checkCancellation)
        } catch {
            return try notice("<upstream body withheld: output sanitization failed>", pattern: pattern, check: checkCancellation)
        }
    }

    /// Constants can themselves collide with an arbitrary helper token. Empty
    /// output is the final fail-closed fallback; no body bytes are retained.
    private static func notice(_ text: String, pattern: LiteralPattern, check: CancellationCheck) throws -> String {
        try pattern.contains(Array(text.utf8), check: check) ? "" : text
    }

    /// Byte-exact KMP: linear scanning and O(token length) prefix storage.
    /// UTF-8 token matches in valid UTF-8 text align with scalar boundaries.
    /// Keeping a single pending union avoids an array per overlapping match.
    private struct LiteralPattern: Sendable {
        let bytes: [UInt8]
        let fallback: [Int]

        /// Builds the prefix table only for the bounded token (empty matches none).
        init(bytes: [UInt8]) {
            self.bytes = bytes
            var table = [Int](repeating: 0, count: bytes.count)
            var matched = 0
            if bytes.count > 1 {
                for index in 1 ..< bytes.count {
                    while matched > 0, bytes[index] != bytes[matched] {
                        matched = table[matched - 1]
                    }
                    if bytes[index] == bytes[matched] { matched += 1 }
                    table[index] = matched
                }
            }
            self.fallback = table
        }

        /// Finds a complete literal token with cooperative checkpoints.
        func contains(_ text: [UInt8], check: CancellationCheck) throws -> Bool {
            guard !bytes.isEmpty else { return false }
            var matched = 0
            for index in text.indices {
                if index % checkpointStride == 0 { try check(.invariantScan(index)) }
                while matched > 0, text[index] != bytes[matched] { matched = fallback[matched - 1] }
                if text[index] == bytes[matched] { matched += 1 }
                if matched == bytes.count { return true }
            }
            return false
        }

        /// Enumerates every occurrence, including overlaps; emits each coalesced
        /// union once. A subsequent invariant rejects boundary-created tokens.
        func redact(_ text: String, replacement: String, check: CancellationCheck) throws -> String {
            guard !bytes.isEmpty else { return text }
            let input = Array(text.utf8)
            let marker = Array(replacement.utf8)
            var output: [UInt8] = []
            var matched = 0
            var copiedThrough = 0
            var pending: Range<Int>?
            for index in input.indices {
                if index % checkpointStride == 0 { try check(.literalScan(index)) }
                while matched > 0, input[index] != bytes[matched] { matched = fallback[matched - 1] }
                if input[index] == bytes[matched] { matched += 1 }
                guard matched == bytes.count else { continue }
                let range = (index + 1 - bytes.count) ..< (index + 1)
                if let previous = pending {
                    if range.lowerBound < previous.upperBound {
                        pending = previous.lowerBound ..< range.upperBound
                    } else {
                        try append(input[copiedThrough ..< previous.lowerBound], to: &output)
                        try append(marker[...], to: &output)
                        copiedThrough = previous.upperBound
                        pending = range
                    }
                } else {
                    pending = range
                }
                matched = fallback[matched - 1]
            }
            if let previous = pending {
                try append(input[copiedThrough ..< previous.lowerBound], to: &output)
                try append(marker[...], to: &output)
                copiedThrough = previous.upperBound
            }
            try append(input[copiedThrough...], to: &output)
            guard let result = String(bytes: output, encoding: .utf8) else { throw FilteringFailure.invariant }
            return result
        }

        /// Caps intermediate growth before allocating/appending another chunk.
        private func append(_ chunk: ArraySlice<UInt8>, to output: inout [UInt8]) throws {
            guard chunk.count <= maxSanitizedBytes - output.count else { throw FilteringFailure.workLimit }
            output.append(contentsOf: chunk)
        }
    }

    /// A scalar lexer locates spans; Foundation decodes complete literals only.
    /// Each pass allows 4096 complete spans, each at most 64 KiB, and at most
    /// 1 MiB cumulative literal bytes submitted to JSONDecoder (failures count).
    /// Exceeding a bound withholds everything, not a partly sanitized suffix.
    private static func quotedStrings(
        _ text: String,
        pattern: LiteralPattern,
        replacement: String,
        validateOnly: Bool,
        check: CancellationCheck
    ) throws -> String {
        guard !pattern.bytes.isEmpty else { return validateOnly ? "" : text }
        let scalars = text.unicodeScalars
        var cursor = scalars.startIndex
        var copiedThrough = cursor
        var scannedBytes = 0
        var nextCheckpoint = 0
        var spans = 0
        var decodedBytes = 0
        var result = ""
        var resultBytes = 0
        while cursor < scalars.endIndex {
            if scannedBytes >= nextCheckpoint {
                try check(.quotedScan(scannedBytes))
                nextCheckpoint = scannedBytes + checkpointStride
            }
            guard scalars[cursor] == "\"" else {
                scannedBytes += utf8Width(scalars[cursor])
                scalars.formIndex(after: &cursor)
                continue
            }
            let start = cursor
            scannedBytes += 1
            scalars.formIndex(after: &cursor)
            var spanBytes = 1
            var escaped = false
            var closed = false
            while cursor < scalars.endIndex {
                if scannedBytes >= nextCheckpoint {
                    try check(.quotedScan(scannedBytes))
                    nextCheckpoint = scannedBytes + checkpointStride
                }
                let scalar = scalars[cursor]
                let width = utf8Width(scalar)
                spanBytes += width
                scannedBytes += width
                guard spanBytes <= maxQuotedSpanBytes else { throw FilteringFailure.workLimit }
                scalars.formIndex(after: &cursor)
                if escaped { escaped = false }
                else if scalar == "\\" { escaped = true }
                else if scalar == "\"" { closed = true; break }
            }
            guard closed else { break }
            spans += 1
            guard spans <= maxQuotedSpans, spanBytes <= maxAcceptedBodyBytes - decodedBytes else {
                throw FilteringFailure.workLimit
            }
            decodedBytes += spanBytes
            let literal = String(text[start ..< cursor])
            try check(.beforeStringDecode)
            let decoded: String?
            do {
                decoded = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
            } catch {
                // Non-JSON/malformed quoted prose retains raw-literal coverage;
                // decoder diagnostics are never emitted or mistaken for status.
                decoded = nil
            }
            try check(.afterStringDecode)
            guard let decoded else { continue }
            if validateOnly {
                guard try !pattern.contains(Array(decoded.utf8), check: check) else { throw FilteringFailure.invariant }
                continue
            }
            let redacted = try pattern.redact(decoded, replacement: replacement, check: check)
            guard redacted != decoded else { continue }
            guard try !pattern.contains(Array(redacted.utf8), check: check) else { throw FilteringFailure.invariant }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            try check(.beforeStringEncode)
            let data = try encoder.encode(redacted)
            try check(.afterStringEncode)
            guard let encoded = String(data: data, encoding: .utf8) else { throw FilteringFailure.invariant }
            try appendText(String(text[copiedThrough ..< start]), to: &result, bytes: &resultBytes)
            try appendText(encoded, to: &result, bytes: &resultBytes)
            copiedThrough = cursor
        }
        if !validateOnly {
            try appendText(String(text[copiedThrough...]), to: &result, bytes: &resultBytes)
        }
        return result
    }

    /// Bounds intermediate text growth, independent of the forwarded budget.
    private static func appendText(_ text: String, to result: inout String, bytes: inout Int) throws {
        let count = text.utf8.count
        guard count <= maxSanitizedBytes - bytes else { throw FilteringFailure.workLimit }
        result += text
        bytes += count
    }

    /// Scalar width without allocating a String for each lexed scalar.
    private static func utf8Width(_ scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0 ... 0x7F: 1
        case 0x80 ... 0x7FF: 2
        case 0x800 ... 0xFFFF: 3
        default: 4
        }
    }

    /// Largest scalar-aligned prefix within the output cap. Checkpoints are
    /// synchronous; subtraction avoids overflow for Int.max/Int.min budgets.
    private static func utf8Prefix(_ text: String, maxBytes: Int, check: CancellationCheck) throws -> String {
        var used = 0
        var nextCheckpoint = 0
        var end = text.unicodeScalars.startIndex
        let scalars = text.unicodeScalars
        while end < scalars.endIndex {
            if used >= nextCheckpoint {
                try check(.truncation(used))
                nextCheckpoint = used + checkpointStride
            }
            let width = utf8Width(scalars[end])
            guard width <= maxBytes - used else { break }
            used += width
            scalars.formIndex(after: &end)
        }
        return String(text[..<end])
    }
}
