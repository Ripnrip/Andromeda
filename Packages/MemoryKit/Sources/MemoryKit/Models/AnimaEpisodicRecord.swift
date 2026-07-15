/**
 * 🎭 The AnimaEpisodicRecord - The Scenic Memory Log
 *
 * "A single, sparkling neuron in our local write-ahead journal.
 * Holds our fleeting sessions before they are cold-distilled into markdown.
 * Designed to resist thread collisions like a charm."
 *
 * - The Spellbinding Museum Director of MemoryKit
 */

import Foundation
import SwiftData

/// 🌟 AnimaEpisodicRecord - The local hot storage of record for episodic capture
/// before it is consolidated or projected downstream.
/// Fully ACID-compliant, transactional, designed for sub-ms execution directly on threads.
/// Let SwiftData's @Model macro manage concurrency internally, while boundary-crossing
/// is achieved via the lightweight, immutable, thread-safe `AnimaEpisodicRecordSnapshot`.
@Model
public final class AnimaEpisodicRecord {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var contentHash: String // Primary join key derived from narrative
    public var createdAt: Date
    public var project: String
    public var agent: String
    public var narrative: String
    public var visibility: String // public | friends | private | internal
    public var provenance: String // source metadata
    public var tags: [String]
    public var materializedPath: String? // Nullable, populated on projection to Obsidian

    // 🌟 The Grand Ignition - Preparing our neuron with mystical defaults
    public init(
        id: UUID = UUID(),
        contentHash: String,
        createdAt: Date = Date(),
        project: String,
        agent: String,
        narrative: String = "",
        visibility: String = "private",
        provenance: String,
        tags: [String] = [],
        materializedPath: String? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.project = project
        self.agent = agent
        self.narrative = narrative
        self.visibility = visibility
        self.provenance = provenance
        self.tags = tags
        self.materializedPath = materializedPath
    }

    // 🧪 The Reincarnation Ritual - Construct a live `@Model` object directly from an immutable snapshot
    public init(snapshot: AnimaEpisodicRecordSnapshot) {
        self.id = snapshot.id
        self.contentHash = snapshot.contentHash
        self.createdAt = snapshot.createdAt
        self.project = snapshot.project
        self.agent = snapshot.agent
        self.narrative = snapshot.narrative
        self.visibility = snapshot.visibility
        self.provenance = snapshot.provenance
        self.tags = snapshot.tags
        self.materializedPath = snapshot.materializedPath
    }
}

/// 🚀 The Boundary-Crossing Vessel - A thread-safe, immutable snapshot of our episodic record
/// perfect for floating safely between our background database actor and the main stage.
public struct AnimaEpisodicRecordSnapshot: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let contentHash: String
    public let createdAt: Date
    public let project: String
    public let agent: String
    public let narrative: String
    public let visibility: String
    public let provenance: String
    public let tags: [String]
    public let materializedPath: String?

    // 🌟 The Snapshot Conjuring Ritual
    public init(
        id: UUID = UUID(),
        contentHash: String,
        createdAt: Date = Date(),
        project: String,
        agent: String,
        narrative: String = "",
        visibility: String = "private",
        provenance: String,
        tags: [String] = [],
        materializedPath: String? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.project = project
        self.agent = agent
        self.narrative = narrative
        self.visibility = visibility
        self.provenance = provenance
        self.tags = tags
        self.materializedPath = materializedPath
    }
}

// MARK: - Alchemy & Transformations
extension AnimaEpisodicRecord {
    // 💎 The Crystallization - Turn our active `@Model` reference into a static, Sendable snapshot
    public var toSnapshot: AnimaEpisodicRecordSnapshot {
        AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: contentHash,
            createdAt: createdAt,
            project: project,
            agent: agent,
            narrative: narrative,
            visibility: visibility,
            provenance: provenance,
            tags: tags,
            materializedPath: materializedPath
        )
    }
}
