import Foundation

/// Stable error surface shared by the runtime foundation and journal layers.
public enum AndromedaRuntimeError: Error, Sendable, Equatable {
    case invalidEventSource(String)
    case unsupportedSchemaVersion(Int)
    case duplicateIdempotencyConflict(key: IdempotencyKey, existingEventID: EventID)
    case journalCorrupted(String)
    case journalIOFailed(String)
    case invalidMemoryContent(String)
    case invalidRecallQuery(String)
    case invalidRuntimeRequest(String)
    case operationalStoreFailed(String)
}

extension AndromedaRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEventSource(let detail):
            return detail
        case .unsupportedSchemaVersion(let version):
            return "Unsupported event schema version: \(version)"
        case .duplicateIdempotencyConflict(let key, let eventID):
            return "Idempotency key \(key.rawValue) already maps to event \(eventID)"
        case .journalCorrupted(let detail):
            return detail
        case .journalIOFailed(let detail):
            return detail
        case .invalidMemoryContent(let detail):
            return detail
        case .invalidRecallQuery(let detail):
            return detail
        case .invalidRuntimeRequest(let detail):
            return detail
        case .operationalStoreFailed(let detail):
            return detail
        }
    }
}
