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

/// Dotted / short compatibility shims that resolve onto `MemoryVerb`.
///
/// Underscored forms are canonical (`MemoryVerb`); dotted / short forms live
/// here so both naming schemes stay greppable and call sites never re-type
/// the literals (issue #57 / swift-canon enum-design).
public enum MemoryCompatibilityAlias: String, Sendable, CaseIterable, Equatable {
    case memoryRecallDotted = "memory.recall"
    case recallShort = "recall"
    case memoryStoreDotted = "memory.store"
    case memoryStoreUnderscore = "memory_store"
    case storeShort = "store"
    case retainShort = "retain"
    case memoryForgetDotted = "memory.forget"
    case forgetShort = "forget"
    case memoryHealthDotted = "memory.health"
    case healthShort = "health"
    case memoryJournalDotted = "memory.journal"
    case journalShort = "journal"
    case memorySessionDumpDotted = "memory.session_dump"
    case sessionDumpUnderscore = "session_dump"
    case sessionDumpSpaced = "session dump"
    case inferWrite = "infer.write"
    case inferShort = "infer"

    /// Verb this alias routes to behind the curtain.
    public var verb: MemoryVerb {
        switch self {
        case .memoryRecallDotted, .recallShort:
            return .recall
        case .memoryStoreDotted, .memoryStoreUnderscore, .storeShort, .retainShort,
            .memoryJournalDotted, .journalShort, .memorySessionDumpDotted,
            .sessionDumpUnderscore, .sessionDumpSpaced, .inferWrite, .inferShort:
            return .retain
        case .memoryForgetDotted, .forgetShort:
            return .forget
        case .memoryHealthDotted, .healthShort:
            return .health
        }
    }

    /// Whether this alias stays on the agent hot path.
    public var isHotPath: Bool {
        switch self {
        case .memoryJournalDotted, .journalShort, .memorySessionDumpDotted,
            .sessionDumpUnderscore, .sessionDumpSpaced:
            return false
        default:
            return true
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

    /// Legacy / convenience aliases accepted as shims — derived from the enum.
    public static let compatibilityAliases: [String: MemoryVerb] = {
        Dictionary(uniqueKeysWithValues: MemoryCompatibilityAlias.allCases.map { ($0.rawValue, $0.verb) })
    }()

    /// Aliases that must not be treated as the agent hot path (session dumps / journals).
    public static let offHotPathAliases: Set<String> = [
        MemoryCompatibilityAlias.memoryJournalDotted.rawValue,
        MemoryCompatibilityAlias.journalShort.rawValue,
        MemoryCompatibilityAlias.memorySessionDumpDotted.rawValue,
        MemoryCompatibilityAlias.sessionDumpUnderscore.rawValue,
        MemoryCompatibilityAlias.sessionDumpSpaced.rawValue,
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
        if alias == MemoryCompatibilityAlias.inferWrite.rawValue
            || alias == MemoryCompatibilityAlias.inferShort.rawValue
        {
            return .inferAliasDeprecated
        }
        return .episodic
    }
}
