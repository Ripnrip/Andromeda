/**
 * MemoryVerbSurface — locked Andromida agent-facing memory verbs (BIN-247).
 *
 * Canonical IDs: memory_recall / memory_retain / memory_forget / memory_health.
 * Legacy dotted IDs remain as compatibility shims only. Session-end / daily dump
 * aliases are accepted but marked off the agent hot path.
 */

import Foundation

/// Canonical Andromida memory verbs exposed to agents and companions.
public enum MemoryVerb: String, Sendable, Codable, CaseIterable, Equatable {
    case recall = "memory_recall"
    case retain = "memory_retain"
    case forget = "memory_forget"
    case health = "memory_health"

    /// Human-facing short form without the `memory_` prefix.
    public var shortName: String {
        switch self {
        case .recall: return "recall"
        case .retain: return "retain"
        case .forget: return "forget"
        case .health: return "health"
        }
    }
}

/// How a parsed capability maps onto the locked verb surface.
public enum MemoryVerbResolution: Sendable, Equatable {
    /// Canonical verb used on the agent hot path.
    case canonical(MemoryVerb)
    /// Deprecated or operator-only alias that still routes to a verb.
    case compatibilityShim(MemoryVerb, alias: String, hotPath: Bool)
}

/// Parses caller capability strings into the locked verb surface.
public enum MemoryVerbSurface: Sendable {
    /// Canonical capability IDs agents should prefer.
    public static let canonicalIDs: [String] = MemoryVerb.allCases.map(\.rawValue)

    /// Legacy / convenience aliases accepted as shims.
    public static let compatibilityAliases: [String: MemoryVerb] = [
        "memory.recall": .recall,
        "recall": .recall,
        "memory.store": .retain,
        "memory_store": .retain,
        "store": .retain,
        "retain": .retain,
        "memory.forget": .forget,
        "forget": .forget,
        "memory.health": .health,
        "health": .health,
        // Off hot-path convenience aliases → retain with WriteKind elsewhere.
        "memory.journal": .retain,
        "journal": .retain,
        "memory.session_dump": .retain,
        "session_dump": .retain,
        "session dump": .retain,
        "infer.write": .retain,
        "infer": .retain,
    ]

    /// Aliases that must not be treated as the agent hot path (session dumps / journals).
    public static let offHotPathAliases: Set<String> = [
        "memory.journal",
        "journal",
        "memory.session_dump",
        "session_dump",
        "session dump",
    ]

    /// Resolve a raw capability or short verb string.
    public static func resolve(_ raw: String) -> MemoryVerbResolution? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()

        if let verb = MemoryVerb(rawValue: key) {
            return .canonical(verb)
        }
        if let verb = compatibilityAliases[key] {
            let hotPath = !offHotPathAliases.contains(key)
            return .compatibilityShim(verb, alias: key, hotPath: hotPath)
        }
        return nil
    }

    /// Whether the raw ID is a canonical hot-path verb.
    public static func isCanonicalHotPath(_ raw: String) -> Bool {
        guard case .canonical = resolve(raw) else { return false }
        return true
    }
}

/// Write kind assigned behind the curtain — never a client capability ID.
public enum CurtainWriteKind: String, Sendable, Codable, Equatable {
    case episodic
    case journal
    case sessionDump
    case inferAliasDeprecated
    case forgetTombstone
}

/// Maps shim aliases onto curtain write kinds for retain intake.
public enum CurtainWriteKindResolver: Sendable {
    public static func resolve(capabilityAlias: String?) -> CurtainWriteKind {
        guard let alias = capabilityAlias?.lowercased() else { return .episodic }
        if MemoryVerbSurface.offHotPathAliases.contains(alias) {
            if alias.contains("session") { return .sessionDump }
            return .journal
        }
        if alias == "infer.write" || alias == "infer" {
            return .inferAliasDeprecated
        }
        return .episodic
    }
}
