import Foundation

/// Shared lowercase hex encoding for digests and content hashes.
extension Sequence where Element == UInt8 {
    /// Lowercase hex string (`a1b2…`) — one place for the `%02x` map/join pattern.
    public var hexLowercase: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
