/**
 * 🎭 The ProjectState Models - Client Kanban Without Tracker Brands
 *
 * "The seeker sees a project, a status, a list of items—
 * never a linear.com URL, never a Habitat deep-link.
 * Provenance whispers backstage for operators alone."
 *
 * - The Spellbinding Museum Director of Capability Curtains
 */

import Foundation

// MARK: - Identifiers

/// 🌟 Opaque project identity — capability surface, not tracker ticket IDs.
public struct ProjectStateID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// 🌟 Opaque item identity inside a project.
public struct ProjectStateItemID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

// MARK: - Status

/// 🌟 Client-facing workflow posture — brand-neutral vocabulary.
public enum ProjectStateStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case backlog
    case active
    case blocked
    case done
}

// MARK: - Provenance (operator / internal only)

/**
 * 🔮 Operator-only tracker cross-links — IDs, never public URLs.
 *
 * Intentionally **not** encoded on `ProjectState`'s Codable surface so
 * client JSON / agent tool payloads cannot leak Linear∪Multica brands.
 */
public struct ProjectStateProvenance: Sendable, Equatable {
    /// e.g. `BIN-42` — operator fabric only
    public var linearIssueID: String?
    /// e.g. `HAB-99` — operator fabric only
    public var multicaIssueID: String?

    public init(linearIssueID: String? = nil, multicaIssueID: String? = nil) {
        self.linearIssueID = linearIssueID
        self.multicaIssueID = multicaIssueID
    }
}

// MARK: - Items & Projects

/// 🌟 A single work item on the client `project.state` board.
public struct ProjectStateItem: Sendable, Equatable, Identifiable, Codable {
    public var id: ProjectStateItemID
    public var title: String
    public var status: ProjectStateStatus
    public var notes: String?

    public init(
        id: ProjectStateItemID,
        title: String,
        status: ProjectStateStatus = .backlog,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.notes = notes
    }
}

/**
 * 🎭 ProjectState - The public board the client may see
 *
 * Public fields: id, title, status, items.
 * `provenance` is optional / internal — excluded from Codable encode/decode.
 */
public struct ProjectState: Sendable, Equatable, Identifiable {
    public var id: ProjectStateID
    public var title: String
    public var status: ProjectStateStatus
    public var items: [ProjectStateItem]
    /// Operator-only cross-links — never linear.com / multica URLs.
    public var provenance: ProjectStateProvenance?

    public init(
        id: ProjectStateID,
        title: String,
        status: ProjectStateStatus = .active,
        items: [ProjectStateItem] = [],
        provenance: ProjectStateProvenance? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.items = items
        self.provenance = provenance
    }
}

extension ProjectState: Codable {
    // 🎨 Client Codable keys — provenance stays behind the curtain
    enum CodingKeys: String, CodingKey {
        case id, title, status, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ProjectStateID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(ProjectStateStatus.self, forKey: .status)
        items = try container.decodeIfPresent([ProjectStateItem].self, forKey: .items) ?? []
        provenance = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(items, forKey: .items)
        // ✨ provenance deliberately omitted — no tracker brand leakage
    }
}

// MARK: - Drafts & Patches

/// 🌟 Create-item draft for `project.state.create`.
public struct ProjectStateDraft: Sendable, Equatable {
    public var projectID: ProjectStateID
    public var title: String
    public var status: ProjectStateStatus
    public var notes: String?

    public init(
        projectID: ProjectStateID,
        title: String,
        status: ProjectStateStatus = .backlog,
        notes: String? = nil
    ) {
        self.projectID = projectID
        self.title = title
        self.status = status
        self.notes = notes
    }
}

/// 🌟 Partial update for `project.state.update`.
public struct ProjectStatePatch: Sendable, Equatable {
    public var title: String?
    public var status: ProjectStateStatus?
    public var notes: String?

    public init(title: String? = nil, status: ProjectStateStatus? = nil, notes: String? = nil) {
        self.title = title
        self.status = status
        self.notes = notes
    }
}

// MARK: - Errors

/// 🌩️ Capability-surface errors — brand-neutral copy for clients.
public enum ProjectStateError: Error, LocalizedError, Equatable, Sendable {
    case projectNotFound(ProjectStateID)
    case itemNotFound(ProjectStateItemID)
    case bridgeNotWired
    case providerFailure(String)

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "Project not found: \(id.rawValue)"
        case .itemNotFound(let id):
            return "Item not found: \(id.rawValue)"
        case .bridgeNotWired:
            return "Operator project bridge is not wired yet"
        case .providerFailure(let message):
            return "Project provider failure: \(message)"
        }
    }
}
