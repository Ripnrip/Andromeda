/**
 * 🎭 The ProjectStateSurface - Client Capability Curtain
 *
 * "Four stable verbs for the seeker: list, get, create, update.
 * Behind the velvet: Linear, Multica, Slack fanout — never named aloud."
 *
 * - The Cosmic Capability Orchestrator of Andromeda
 */

import Foundation

/// Stable `project.state.*` capability IDs — clients see these, never tracker brands.
public enum ProjectStateCapabilityID: String, Sendable, CaseIterable {
    case root = "project.state"
    case list = "project.state.list"
    case get = "project.state.get"
    case create = "project.state.create"
    case update = "project.state.update"
}

/**
 * 🌟 ProjectStateSurface — Andromeda client-facing `project.state` CRUD.
 *
 * Capability IDs (stable; expose these — never tracker brands):
 * - `project.state.list`
 * - `project.state.get`
 * - `project.state.create`
 * - `project.state.update`
 */
public protocol ProjectStateSurface: Sendable {
    /// Capability: `project.state.list`
    func listProjects() async throws -> [ProjectState]

    /// Capability: `project.state.get`
    func getProject(_ id: ProjectStateID) async throws -> ProjectState

    /// Capability: `project.state.create`
    func createItem(_ draft: ProjectStateDraft) async throws -> ProjectStateItem

    /// Capability: `project.state.update`
    func updateItem(_ id: ProjectStateItemID, _ patch: ProjectStatePatch) async throws -> ProjectStateItem
}
