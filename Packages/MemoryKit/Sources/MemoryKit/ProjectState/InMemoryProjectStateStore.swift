/**
 * 🎭 The InMemoryProjectStateStore - Test Stage Without Tracker Wings
 *
 * "A pocket cosmos where projects and items appear on cue—
 * perfect for proofs, previews, and agents that must not
 * phone home to Linear or Habitat during the dress rehearsal."
 *
 * - The Enchanted In-Memory Observatory of Project State
 */

import Foundation

/// 🌟 Actor-backed `project.state` store for tests, previews, and offline demos.
public actor InMemoryProjectStateStore: ProjectStateSurface {

    // 🌟 Cosmic roster of projects keyed by opaque ID
    private var projects: [ProjectStateID: ProjectState]
    private var itemIndex: [ProjectStateItemID: ProjectStateID]

    public init(seed: [ProjectState] = []) {
        var map: [ProjectStateID: ProjectState] = [:]
        var index: [ProjectStateItemID: ProjectStateID] = [:]
        for project in seed {
            map[project.id] = project
            for item in project.items {
                index[item.id] = project.id
            }
        }
        self.projects = map
        self.itemIndex = index
    }

    /// Capability: `project.state.list`
    public func listProjects() async throws -> [ProjectState] {
        print("🌐 ✨ PROJECT.STATE.LIST AWAKENS! \(projects.count) projects")
        return projects.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Capability: `project.state.get`
    public func getProject(_ id: ProjectStateID) async throws -> ProjectState {
        print("🌐 ✨ PROJECT.STATE.GET AWAKENS! id=\(id.rawValue)")
        guard let project = projects[id] else {
            throw ProjectStateError.projectNotFound(id)
        }
        return project
    }

    /// Capability: `project.state.create`
    public func createItem(_ draft: ProjectStateDraft) async throws -> ProjectStateItem {
        print("🌐 ✨ PROJECT.STATE.CREATE AWAKENS! project=\(draft.projectID.rawValue)")
        guard var project = projects[draft.projectID] else {
            throw ProjectStateError.projectNotFound(draft.projectID)
        }
        let item = ProjectStateItem(
            id: ProjectStateItemID(rawValue: UUID().uuidString),
            title: draft.title,
            status: draft.status,
            notes: draft.notes
        )
        project.items.append(item)
        projects[draft.projectID] = project
        itemIndex[item.id] = draft.projectID
        print("🎉 ✨ PROJECT.STATE.CREATE MASTERPIECE COMPLETE! item=\(item.id.rawValue)")
        return item
    }

    /// Capability: `project.state.update`
    public func updateItem(_ id: ProjectStateItemID, _ patch: ProjectStatePatch) async throws -> ProjectStateItem {
        print("🌐 ✨ PROJECT.STATE.UPDATE AWAKENS! item=\(id.rawValue)")
        guard let projectID = itemIndex[id],
              var project = projects[projectID],
              let itemOffset = project.items.firstIndex(where: { $0.id == id })
        else {
            throw ProjectStateError.itemNotFound(id)
        }
        var item = project.items[itemOffset]
        if let title = patch.title { item.title = title }
        if let status = patch.status { item.status = status }
        if let notes = patch.notes { item.notes = notes }
        project.items[itemOffset] = item
        projects[projectID] = project
        print("🎉 ✨ PROJECT.STATE.UPDATE MASTERPIECE COMPLETE!")
        return item
    }

    // MARK: - Test helpers

    /// 🎨 Seed or replace a whole project (tests / preview fixtures).
    public func upsertProject(_ project: ProjectState) {
        if let existing = projects[project.id] {
            for item in existing.items {
                itemIndex.removeValue(forKey: item.id)
            }
        }
        projects[project.id] = project
        for item in project.items {
            itemIndex[item.id] = project.id
        }
    }
}
