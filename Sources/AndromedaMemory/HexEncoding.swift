import Foundation

/// Shared lowercase hex encoding for digests (AndromedaMemory has no MemoryKit dep).
extension Sequence where Element == UInt8 {
    /// Lowercase hex string (`a1b2…`) — mirrors MemoryKit's `hexLowercase`.
    var hexLowercase: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
