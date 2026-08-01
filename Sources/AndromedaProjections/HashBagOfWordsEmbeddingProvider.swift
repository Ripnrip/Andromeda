import AndromedaDomain
import AndromedaMemory
import CryptoKit
import Foundation

/// A deterministic, dependency-free bag-of-words embedding provider.
///
/// Each term is tokenized, hashed with SHA-256, and folded into a 384-float
/// vector. The same input text always produces the same vector, making the
/// provider ideal for rebuild tests and idempotent Qdrant upserts.
public struct HashBagOfWordsEmbeddingProvider: EmbeddingProvider, Sendable {
    public let dimension: Int = 384

    public init() {}

    public func embedding(for text: String) -> [Float] {
        let tokens = Self.tokenize(text)
        var vector = [Float](repeating: 0, count: dimension)

        for token in tokens {
            accumulate(token: token, into: &vector)
        }

        return Self.l2Normalize(vector)
    }

    private static func tokenize(_ text: String) -> [String] {
        let lowercased = text.lowercased()
        var tokens: [String] = []
        var current = ""

        for character in lowercased {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private func accumulate(token: String, into vector: inout [Float]) {
        // We need 384 bits of deterministic material per token. SHA-256 gives
        // 256 bits, so we mix a second salted hash to cover the tail.
        let primary = Self.hash(token)
        let secondary = Self.hash(token + "::andromeda-embedding-tail")

        for index in 0..<dimension {
            let bitIndex = index % 8
            let bit: Bool
            if index < 256 {
                let byteIndex = index / 8
                bit = (primary[byteIndex] >> bitIndex) & 1 == 1
            } else {
                let byteIndex = (index - 256) / 8
                bit = (secondary[byteIndex] >> bitIndex) & 1 == 1
            }
            vector[index] += bit ? 1.0 : -1.0
        }
    }

    private static func hash(_ value: String) -> [UInt8] {
        let digest = SHA256.hash(data: Data(value.utf8))
        return Array(digest)
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        let sumOfSquares = vector.reduce(0) { $0 + $1 * $1 }
        guard sumOfSquares > 0 else {
            return vector
        }
        let magnitude = sqrt(sumOfSquares)
        return vector.map { $0 / magnitude }
    }
}
