/**
 * SkillEntity — observe-first ritual skill citizen (HAB-598 / surface-area skill.*).
 *
 * Clients never see tracker brands. Capability IDs stay stable
 * (`skill.checkpoint`, `skill.knowledge-sync`, `skill.close`, `skill.graphify`).
 */

import Foundation

/// Which host directory seeded this skill (observe only — never Linear/Multica).
public enum SkillSource: String, Sendable, Codable, CaseIterable, Equatable {
    case claude
    case codex
    case cursor
    case hermes
    case repo
    case unknown

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .hermes: return "Hermes"
        case .repo: return "Repo"
        case .unknown: return "Unknown"
        }
    }
}

/// Known Andromeda ritual / knowledge skills (ANDROMEDA-SURFACE-AREA § skill.*).
public enum SkillKind: String, Sendable, Codable, CaseIterable, Equatable {
    case checkpoint
    case knowledgeSync = "knowledge-sync"
    case close
    case graphify

    /// Stable client capability id.
    public var capabilityID: String { "skill.\(rawValue)" }

    public var displayName: String {
        switch self {
        case .checkpoint: return "Checkpoint"
        case .knowledgeSync: return "Knowledge Sync"
        case .close: return "Close"
        case .graphify: return "Graphify"
        }
    }
}

/// One skill as a Swift citizen — inventory row for observe / Invoke later.
public struct SkillEntity: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let kind: SkillKind
    /// On-disk path when discovered; nil for catalog-only seeds.
    public let path: String?
    public let source: SkillSource
    /// True when the skill directory / SKILL.md was found on disk.
    public let presentOnDisk: Bool
    public let scannedAt: Date

    public init(
        id: String,
        kind: SkillKind,
        path: String? = nil,
        source: SkillSource,
        presentOnDisk: Bool,
        scannedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.source = source
        self.presentOnDisk = presentOnDisk
        self.scannedAt = scannedAt
    }

    public var capabilityID: String { kind.capabilityID }
}
