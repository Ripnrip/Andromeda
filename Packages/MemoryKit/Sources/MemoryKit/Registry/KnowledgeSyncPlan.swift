/**
 * KnowledgeSyncPlan — observe-first destination matrix for HAB-598 / BIN-286.
 *
 * `/knowledge-sync` distributes one authored record to live destinations.
 * This type is the curtain-facing inventory; invoke/fan-out remains 📐
 * (multibrain scripts + Claude skill today). Ladybug is explicitly NOT a
 * knowledge-sync destination (nightly rebuild only).
 */

import Foundation

/// One `/knowledge-sync` fan-out target (operator-internal brands stay off client menus).
public enum KnowledgeSyncDestination: String, Sendable, Codable, CaseIterable, Equatable {
    case memoryMd = "memory.md"
    case claudeMem = "claude-mem"
    case graphify
    case multibrainStage = "multibrain-stage"
    case qdrant

    public var displayName: String {
        switch self {
        case .memoryMd: return "memory.md"
        case .claudeMem: return "claude-mem"
        case .graphify: return "graphify / MCP memory"
        case .multibrainStage: return "multibrain stage"
        case .qdrant: return "qdrant secondbrain_learnings"
        }
    }

    /// Short operator path hint (not a client capability string).
    public var pathHint: String {
        switch self {
        case .memoryMd: return "~/.claude/projects/…/memory/"
        case .claudeMem: return "~/.claude-mem/"
        case .graphify: return "MCP user-memory"
        case .multibrainStage: return "~/Developer/multibrain/07-Sessions/"
        case .qdrant: return "127.0.0.1:6333/secondbrain_learnings"
        }
    }
}

/// Honesty for a destination row.
public enum KnowledgeSyncDestinationStatus: String, Sendable, Codable, Equatable {
    case live
    case staged
    case specified
    case deferred
}

/// One row in the observe matrix.
public struct KnowledgeSyncDestinationRow: Sendable, Equatable, Identifiable, Codable {
    public var id: String { destination.rawValue }
    public let destination: KnowledgeSyncDestination
    public let status: KnowledgeSyncDestinationStatus
    public let notes: String

    public init(
        destination: KnowledgeSyncDestination,
        status: KnowledgeSyncDestinationStatus,
        notes: String = ""
    ) {
        self.destination = destination
        self.status = status
        self.notes = notes
    }
}

/// Crystallized observe plan for `skill.knowledge-sync` (HAB-598).
public struct KnowledgeSyncPlan: Sendable, Equatable, Codable {
    public let capabilityID: String
    public let rows: [KnowledgeSyncDestinationRow]
    /// Explicit non-destinations (prevents Ladybug conflation).
    public let excluded: [String]
    public let generatedAt: Date

    public init(
        rows: [KnowledgeSyncDestinationRow],
        excluded: [String] = ["ladybug", "LadybugDB"],
        generatedAt: Date = Date()
    ) {
        self.capabilityID = SkillKind.knowledgeSync.capabilityID
        self.rows = rows
        self.excluded = excluded
        self.generatedAt = generatedAt
    }

    /// Canonical live matrix from `docs/KNOWLEDGE-STACK.md` (as of 2026-10).
    public static func canonical(now: Date = Date()) -> KnowledgeSyncPlan {
        KnowledgeSyncPlan(
            rows: [
                KnowledgeSyncDestinationRow(
                    destination: .memoryMd,
                    status: .live,
                    notes: "fact file + MEMORY.md pointer"
                ),
                KnowledgeSyncDestinationRow(
                    destination: .claudeMem,
                    status: .live,
                    notes: "verify observer capture"
                ),
                KnowledgeSyncDestinationRow(
                    destination: .graphify,
                    status: .live,
                    notes: "create_entities / create_relations (merge)"
                ),
                KnowledgeSyncDestinationRow(
                    destination: .multibrainStage,
                    status: .staged,
                    notes: "nightly ingest_staged → SecondBrain"
                ),
                KnowledgeSyncDestinationRow(
                    destination: .qdrant,
                    status: .live,
                    notes: "384-dim local embeddings; not Ladybug"
                ),
            ],
            generatedAt: now
        )
    }
}

extension SkillRegistry {
    /// Observe-only knowledge-sync destination plan (BIN-286 consolidate step 1).
    public func knowledgeSyncPlan(now: Date = Date()) -> KnowledgeSyncPlan {
        _ = now
        return .canonical(now: now)
    }
}
