/**
 * Memory orchestration types shared by MemoryKit UI and AnimaCore TCA reducer.
 * Lives in MemoryKit so UI targets avoid importing AnimaCore (no circular deps).
 */

import Foundation

/// CloudKit sync pipeline progress (TCA + CommandCenter badges).
public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case success(Date)
    case failed(SyncError)
}

/// Per-service health probe (Letta / Ladybug / Qdrant).
public enum HealthStatus: Equatable, Sendable {
    case unknown
    case healthy
    case unhealthy(String)
}

public typealias ConnectionHealthStatus = HealthStatus

/// Cloak dial for reducer UI — aliases `VisibilityClass`.
public typealias VisibilityLevel = VisibilityClass

/// Obsidian markdown materialization progress.
public enum MaterializationStatus: Equatable, Sendable {
    case idle
    case materializing(progress: Double)
    case success(String)
    case failed(String)
}

public struct MaterializationError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
