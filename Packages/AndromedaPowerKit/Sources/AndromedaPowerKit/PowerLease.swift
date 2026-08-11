import Foundation

public struct PowerLease: Sendable, Hashable, Codable {
    public let id: UUID
    public let owner: String
    public let reason: String
    public let requirements: PowerRequirement
    public let acquiredAt: Date

    public init(
        id: UUID = UUID(),
        owner: String,
        reason: String,
        requirements: PowerRequirement,
        acquiredAt: Date = Date()
    ) {
        self.id = id
        self.owner = owner
        self.reason = reason
        self.requirements = requirements
        self.acquiredAt = acquiredAt
    }
}
