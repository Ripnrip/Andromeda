import Foundation

/// Minimal runtime health surface for the Milestone 0 HTTP adapter.
public struct RuntimeHealthStatus: Codable, Sendable, Equatable {
    public let status: String
    public let service: String
    public let version: String
    public let journal: String

    public init(status: String, service: String, version: String, journal: String) {
        self.status = status
        self.service = service
        self.version = version
        self.journal = journal
    }
}
