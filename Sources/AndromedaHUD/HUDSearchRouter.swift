import Foundation

/// Capability-facing query intents from the expandable Ask AI field (BIN-57).
///
/// Clients only see stable capability IDs (`memory.*`, `infer.write`) — never
/// tracker or provider brands.
public enum HUDSearchIntent: Equatable, Sendable, Codable {
    /// `memory.recall` — retrieve stored knowledge.
    case memoryRecall(query: String)
    /// `memory.store` — capture a new observation.
    case memoryStore(content: String)
    /// `memory.journal` — dump / inspect session journal.
    case memoryJournal(query: String)
    /// `infer.write` — general Ask AI generation.
    case inferWrite(prompt: String)
    /// Empty / whitespace-only submission.
    case empty

    /// Stable capability ID for telemetry and routing.
    public var capabilityID: String {
        switch self {
        case .memoryRecall: return "memory.recall"
        case .memoryStore: return "memory.store"
        case .memoryJournal: return "memory.journal"
        case .inferWrite: return "infer.write"
        case .empty: return "hud.search.empty"
        }
    }

    /// Human-readable summary for the HUD footer (no provider names).
    public var displaySummary: String {
        switch self {
        case .memoryRecall(let query):
            return "memory.recall · \(query)"
        case .memoryStore(let content):
            return "memory.store · \(content)"
        case .memoryJournal(let query):
            return "memory.journal · \(query)"
        case .inferWrite(let prompt):
            return "infer.write · \(prompt)"
        case .empty:
            return "Enter a query"
        }
    }
}

/// Parses Ask AI / memory search text into capability intents.
public enum HUDSearchRouter: Sendable {
    /// Prefix verbs recognized by the expandable search field.
    public static let recallPrefixes = ["recall ", "memory.recall ", "/recall "]
    public static let storePrefixes = ["store ", "memory.store ", "/store "]
    public static let journalPrefixes = ["journal ", "memory.journal ", "session dump ", "/journal "]

    /// Route free-text input to a capability intent.
    ///
    /// - Parameters:
    ///   - raw: Operator-typed search / Ask AI string.
    /// - Returns: Parsed intent; bare text becomes `infer.write`.
    public static func route(_ raw: String) -> HUDSearchIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let lower = trimmed.lowercased()

        if let payload = stripPrefix(lower, from: trimmed, prefixes: recallPrefixes) {
            return .memoryRecall(query: payload)
        }
        if let payload = stripPrefix(lower, from: trimmed, prefixes: storePrefixes) {
            return .memoryStore(content: payload)
        }
        if let payload = stripPrefix(lower, from: trimmed, prefixes: journalPrefixes) {
            return .memoryJournal(query: payload)
        }
        return .inferWrite(prompt: trimmed)
    }

    /// Strip a known verb prefix, preserving original casing of the remainder.
    private static func stripPrefix(
        _ lower: String,
        from original: String,
        prefixes: [String]
    ) -> String? {
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let start = original.index(original.startIndex, offsetBy: prefix.count)
                let rest = String(original[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }
}
