import Foundation

/// Provides deterministic vector embeddings for semantic projection sinks.
///
/// Implementations must be `Sendable` so they can be held by actor-isolated
/// sinks and injected in tests.
public protocol EmbeddingProvider: Sendable {
    /// Vector dimension produced by this provider.
    var dimension: Int { get }

    /// Returns a numeric vector representing the supplied text.
    ///
    /// The same text should always produce the same vector for a given
    /// implementation, enabling projection idempotency and rebuild tests.
    func embedding(for text: String) -> [Float]
}
