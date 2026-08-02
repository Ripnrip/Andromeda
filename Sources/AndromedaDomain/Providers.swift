import Foundation

/// Provides wall-clock time without pinning runtime code to `Date()` during tests.
public protocol ClockProviding: Sendable {
    func now() async -> Date
}

/// Provides UUID values without pinning runtime code to `UUID()` during tests.
public protocol UUIDProviding: Sendable {
    func makeUUID() async -> UUID
}

/// Production clock implementation.
public struct LiveClock: ClockProviding {
    public init() {}

    public func now() async -> Date {
        Date()
    }
}

/// Production UUID implementation.
public struct LiveUUIDProvider: UUIDProviding {
    public init() {}

    public func makeUUID() async -> UUID {
        UUID()
    }
}

/// Deterministic clock for tests that should not depend on wall-clock time.
public actor FixedClock: ClockProviding {
    private let date: Date

    public init(date: Date) {
        self.date = date
    }

    public func now() async -> Date {
        date
    }
}

/// Deterministic UUID source for tests that need stable event identities.
public actor DeterministicUUIDProvider: UUIDProviding {
    private var values: [UUID]
    private let fallback: UUID

    public init(values: [UUID], fallback: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) {
        self.values = values
        self.fallback = fallback
    }

    public func makeUUID() async -> UUID {
        guard !values.isEmpty else { return fallback }
        return values.removeFirst()
    }
}
