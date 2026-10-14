/**
 * KnowledgeSyncPlan — observe-first destination matrix for HAB-598 / BIN-286.
 *
 * `/knowledge-sync` distributes one authored record to live destinations.
 * Invoke/fan-out remains 📐 (multibrain scripts + Claude skill today). The
 * nightly rebuild index is explicitly NOT a knowledge-sync destination.
 *
 * Review 5513453513 P1-3 — curtain split:
 * - The client-facing Codable plan (`KnowledgeSyncPlan` / `KnowledgeSyncPlanItem`)
 *   serializes **opaque destination capability ids** (`destination.*`) and
 *   curtain-safe notes only.
 * - Raw provider / topology identifiers (brands, host paths, endpoints) stay in
 *   the operator-side `KnowledgeSyncDestination` catalog and the
 *   `KnowledgeSyncDestinationRow` operator projection — they are never Codable
 *   and never cross the curtain.
 */

import Foundation

/// Operator-side destination catalog (review 5513453513 P1-3).
///
/// Raw cases, display names, and path hints are operator-internal detail.
/// This type is deliberately **not** `Codable`: anything that serializes for
/// clients must go through the opaque `capabilityID` / `curtainNotes`
/// projection below.
public enum KnowledgeSyncDestination: String, Sendable, Equatable, CaseIterable {
    case memoryMd = "memory.md"
    case claudeMem = "claude-mem"
    case graphify
    case multibrainStage = "multibrain-stage"
    case qdrant

    /// Stable, curtain-facing capability id — opaque, no provider brands.
    public var capabilityID: String {
        switch self {
        case .memoryMd: return "destination.memory-facts"
        case .claudeMem: return "destination.agent-memory"
        case .graphify: return "destination.graph-memory"
        case .multibrainStage: return "destination.session-stage"
        case .qdrant: return "destination.vector-index"
        }
    }

    /// Curtain-safe note for the client plan (no brands, paths, endpoints).
    public var curtainNotes: String {
        switch self {
        case .memoryMd: return "fact file + memory.md pointer"
        case .claudeMem: return "verify observer capture"
        case .graphify: return "entity / relation merge upsert"
        case .multibrainStage: return "nightly staged ingest"
        case .qdrant: return "384-dim local embeddings; not the nightly index"
        }
    }

    /// Canonical observe status for this destination (`docs/KNOWLEDGE-STACK.md`, 2026-10).
    public var canonicalStatus: KnowledgeSyncDestinationStatus {
        switch self {
        case .memoryMd, .claudeMem, .graphify, .qdrant: return .live
        case .multibrainStage: return .staged
        }
    }

    /// Opaque capability id for the explicitly-excluded nightly rebuild index
    /// (prevents conflation with the vector-index destination without naming
    /// any provider brand on client surfaces).
    public static let excludedNightlyIndexCapabilityID = "destination.nightly-rebuild-index"

    /// Operator-only display name — never serialized across the curtain.
    public var displayName: String {
        switch self {
        case .memoryMd: return "memory.md"
        case .claudeMem: return "claude-mem"
        case .graphify: return "graphify / MCP memory"
        case .multibrainStage: return "multibrain stage"
        case .qdrant: return "qdrant secondbrain_learnings"
        }
    }

    /// Operator-only path hint — never serialized across the curtain.
    public var pathHint: String {
        switch self {
        case .memoryMd: return "~/.claude/projects/…/memory/"
        case .claudeMem: return "~/.claude-mem/"
        case .graphify: return "MCP user-memory"
        case .multibrainStage: return "~/Developer/multibrain/07-Sessions/"
        case .qdrant: return "127.0.0.1:6333/secondbrain_learnings"
        }
    }

    /// Resolve the operator destination for a curtain capability id.
    public static func operatorDestination(forCapabilityID id: String) -> KnowledgeSyncDestination? {
        allCases.first { $0.capabilityID == id }
    }
}

/// Honesty for a destination row (values are curtain-safe).
public enum KnowledgeSyncDestinationStatus: String, Sendable, Codable, Equatable {
    case live
    case staged
    case specified
    case deferred
}

/// Curtain-facing row (review P1-3): opaque capability id, status, and
/// curtain-safe notes only. This is the only destination shape that
/// serializes to clients.
public struct KnowledgeSyncPlanItem: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let status: KnowledgeSyncDestinationStatus
    public let notes: String

    public init(
        id: String,
        status: KnowledgeSyncDestinationStatus,
        notes: String = ""
    ) {
        self.id = id
        self.status = status
        self.notes = notes
    }

    public init(destination: KnowledgeSyncDestination) {
        self.init(
            id: destination.capabilityID,
            status: destination.canonicalStatus,
            notes: destination.curtainNotes
        )
    }
}

/// Operator-only projection retaining raw provider detail (brands, path
/// hints). Lives server-side behind the curtain; intentionally not `Codable`
/// and never handed to client serialization paths.
public struct KnowledgeSyncDestinationRow: Sendable, Equatable, Identifiable {
    public var id: String { destination.rawValue }
    public let destination: KnowledgeSyncDestination
    public let status: KnowledgeSyncDestinationStatus
    public let notes: String

    public var pathHint: String { destination.pathHint }
    public var displayName: String { destination.displayName }

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
/// Client-facing and `Codable`: every identifier in the encoded form is an
/// opaque capability id — raw provider / topology detail stays operator-side.
public struct KnowledgeSyncPlan: Sendable, Equatable, Codable {
    public let capabilityID: String
    public let items: [KnowledgeSyncPlanItem]
    /// Explicit non-destinations as opaque capability ids.
    public let excluded: [String]
    public let generatedAt: Date

    public init(
        items: [KnowledgeSyncPlanItem],
        excluded: [String] = [KnowledgeSyncDestination.excludedNightlyIndexCapabilityID],
        generatedAt: Date = Date()
    ) {
        self.capabilityID = SkillKind.knowledgeSync.capabilityID
        self.items = items
        self.excluded = excluded
        self.generatedAt = generatedAt
    }

    /// Canonical live matrix from `docs/KNOWLEDGE-STACK.md` (as of 2026-10),
    /// projected through opaque capability ids.
    public static func canonical(now: Date = Date()) -> KnowledgeSyncPlan {
        KnowledgeSyncPlan(
            items: KnowledgeSyncDestination.allCases.map(KnowledgeSyncPlanItem.init(destination:)),
            generatedAt: now
        )
    }

    /// Operator-only projection with raw provider detail (server-side,
    /// behind the curtain — never serialize to clients).
    public func operatorRows() -> [KnowledgeSyncDestinationRow] {
        items.compactMap { item in
            KnowledgeSyncDestination.operatorDestination(forCapabilityID: item.id).map {
                KnowledgeSyncDestinationRow(destination: $0, status: item.status, notes: item.notes)
            }
        }
    }
}

extension SkillRegistry {
    /// Observe-only knowledge-sync destination plan (BIN-286 consolidate step 1).
    public func knowledgeSyncPlan(now: Date = Date()) -> KnowledgeSyncPlan {
        KnowledgeSyncPlan.canonical(now: now)
    }
}
