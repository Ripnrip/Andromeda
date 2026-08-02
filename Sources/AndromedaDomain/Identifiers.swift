import Foundation

/// Shared behavior for stable typed identifiers that cross module and actor boundaries.
public protocol TypedIdentifier: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
where RawValue == UUID {}

extension TypedIdentifier {
    public var description: String { rawValue.uuidString.lowercased() }
}

/// Stable identifier for a project scope.
public struct ProjectID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a memory record.
public struct MemoryID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a repository scope.
public struct RepositoryID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a session lifecycle.
public struct SessionID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a canonical event.
public struct EventID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a checkpoint.
public struct CheckpointID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a temporary capability lease.
public struct LeaseID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a configured environment.
public struct EnvironmentID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a user scope.
public struct UserID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a team scope.
public struct TeamID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for an organization scope.
public struct OrganizationID: TypedIdentifier, Equatable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Stable key used to deduplicate canonical writes across retries.
public struct IdempotencyKey: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}
