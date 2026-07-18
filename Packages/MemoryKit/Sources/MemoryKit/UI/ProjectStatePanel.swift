/**
 * 🎭 The ProjectStatePanel - Client Board Without Tracker Neon
 *
 * "A quiet SwiftUI ledger of projects and items—
 * status chips, titles, nothing that spells Linear or Habitat.
 * Light and dark footlights for the Andromeda console."
 *
 * - The Spellbinding Museum Director of Capability UI
 */

import Foundation
import SwiftUI

// MARK: - Model

/// 🌟 Main-actor presentation model for `project.state` panel proofs.
@MainActor
@Observable
public final class ProjectStatePanelModel {
    public var projects: [ProjectState]
    public var selectedProjectID: ProjectStateID?
    public var lastMessage: String?
    public var isLoading: Bool
    /// ✨ Draft title for `project.state.create` — never tracker IDs.
    public var draftTitle: String

    public init(
        projects: [ProjectState] = [],
        selectedProjectID: ProjectStateID? = nil,
        lastMessage: String? = nil,
        isLoading: Bool = false,
        draftTitle: String = ""
    ) {
        self.projects = projects
        self.selectedProjectID = selectedProjectID ?? projects.first?.id
        self.lastMessage = lastMessage
        self.isLoading = isLoading
        self.draftTitle = draftTitle
    }

    /// 🎨 Currently selected project, if any.
    public var selectedProject: ProjectState? {
        guard let selectedProjectID else { return projects.first }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    /// ✨ Human status label — never tracker brand names.
    public static func statusLabel(_ status: ProjectStateStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .active: return "Active"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }

    /// 📡 Replace roster from a capability surface result.
    public func apply(projects: [ProjectState]) {
        self.projects = projects
        if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = projects.first?.id
        }
        isLoading = false
        lastMessage = "project.state.list · \(projects.count) project(s)"
    }

    /// 🌐 Refresh via `project.state.list` (capability ID — not Linear/Multica).
    public func refresh(using surface: any ProjectStateSurface) async {
        isLoading = true
        lastMessage = "project.state.list…"
        do {
            let listed = try await surface.listProjects()
            apply(projects: listed)
            print("🎉 ✨ PROJECT.STATE.LIST PANEL REFRESH COMPLETE!")
        } catch {
            isLoading = false
            lastMessage = "project.state.list failed: \(Self.clientSafeMessage(from: error))"
            print("💥 😭 PROJECT.STATE PANEL REFRESH TEMPORARILY HALTED!")
        }
    }

    /// ✨ Create via `project.state.create`, then re-list.
    public func createDraft(using surface: any ProjectStateSurface) async {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            lastMessage = "project.state.create needs a title"
            return
        }
        guard let projectID = selectedProject?.id ?? projects.first?.id else {
            lastMessage = "project.state.create needs a project — refresh first"
            return
        }
        isLoading = true
        lastMessage = "project.state.create…"
        do {
            let draft = ProjectStateDraft(projectID: projectID, title: title, status: .backlog)
            _ = try await surface.createItem(draft)
            draftTitle = ""
            print("🎉 ✨ PROJECT.STATE.CREATE PANEL COMPLETE!")
            await refresh(using: surface)
        } catch {
            isLoading = false
            lastMessage = "project.state.create failed: \(Self.clientSafeMessage(from: error))"
            print("💥 😭 PROJECT.STATE CREATE TEMPORARILY HALTED!")
        }
    }

    /// 🧹 Strip accidental tracker brand leakage from error copy shown on glass.
    public static func clientSafeMessage(from error: Error) -> String {
        var text = error.localizedDescription
        let banned = ["Linear", "Multica", "Habitat", "BIN-", "HAB-"]
        for token in banned {
            text = text.replacingOccurrences(of: token, with: "tracker", options: .caseInsensitive)
        }
        return text
    }
}

// MARK: - Panel

/// 🎭 Simple SwiftUI panel for client-facing `project.state` — no tracker chrome.
@MainActor
public struct ProjectStatePanel: View {
    @Bindable public var model: ProjectStatePanelModel
    public var onRefresh: (() -> Void)?
    public var onCreate: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: ProjectStatePanelModel,
        onRefresh: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.model = model
        self.onRefresh = onRefresh
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if model.isLoading {
                loadingRow
            } else if let project = model.selectedProject {
                projectHeader(project)
                itemList(project.items)
            } else {
                Text("No projects yet — refresh with project.state.list")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectState.empty")
            }
            createRow
            if let message = model.lastMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectState.lastMessage")
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectState.panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            Text("Projects")
                .font(.headline)
            Spacer()
            Text("project.state")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Capability project.state")
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading)
                .accessibilityLabel("Refresh project.state.list")
                .accessibilityIdentifier("projectState.refresh")
            }
        }
        .accessibilityIdentifier("projectState.header")
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text("Loading projects…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("projectState.loading")
    }

    private var createRow: some View {
        HStack(spacing: 8) {
            TextField("New item title", text: $model.draftTitle)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isLoading)
                .accessibilityLabel("New project.state item title")
                .accessibilityIdentifier("projectState.draftTitle")
                .onSubmit {
                    onCreate?()
                }
            Button("Add") {
                onCreate?()
            }
            .disabled(model.isLoading || model.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Create via project.state.create")
            .accessibilityIdentifier("projectState.create")
        }
    }

    private func projectHeader(_ project: ProjectState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.title3.weight(.semibold))
                Text(ProjectStatePanelModel.statusLabel(project.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(project.items.count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: Capsule())
                .accessibilityLabel("\(project.items.count) items")
        }
        .accessibilityIdentifier("projectState.projectHeader")
    }

    private func itemList(_ items: [ProjectStateItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(item.status))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .font(.callout)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(ProjectStatePanelModel.statusLabel(item.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title), \(ProjectStatePanelModel.statusLabel(item.status))")
                .accessibilityIdentifier("projectState.item.\(item.id.rawValue)")
            }
        }
    }

    private func statusColor(_ status: ProjectStateStatus) -> Color {
        switch status {
        case .backlog: return .secondary
        case .active: return .teal
        case .blocked: return .orange
        case .done: return .green
        }
    }
}

// MARK: - Fixtures (previews + snapshots)

extension ProjectStatePanelModel {
    /// 🎨 Deterministic fixture for light/dark previews and SnapshotTesting.
    public static func snapshotFixture() -> ProjectStatePanelModel {
        let items = [
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-1"),
                title: "Wire capability curtain",
                status: .active,
                notes: nil
            ),
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-2"),
                title: "Hide tracker brands from clients",
                status: .done,
                notes: nil
            ),
            ProjectStateItem(
                id: ProjectStateItemID(rawValue: "item-3"),
                title: "Operator bridge live APIs",
                status: .backlog,
                notes: nil
            ),
        ]
        let project = ProjectState(
            id: ProjectStateID(rawValue: "andromeda"),
            title: "Andromeda",
            status: .active,
            items: items,
            provenance: ProjectStateProvenance(linearIssueID: "BIN-HIDDEN", multicaIssueID: "HAB-HIDDEN")
        )
        return ProjectStatePanelModel(
            projects: [project],
            selectedProjectID: project.id,
            lastMessage: "project.state.list · 1 project(s)"
        )
    }
}

#if DEBUG
#Preview("ProjectState · light") {
    ProjectStatePanel(model: .snapshotFixture(), onRefresh: {}, onCreate: {})
        .preferredColorScheme(.light)
}

#Preview("ProjectState · dark") {
    ProjectStatePanel(model: .snapshotFixture(), onRefresh: {}, onCreate: {})
        .preferredColorScheme(.dark)
}

#Preview("ProjectState · a2 · light") {
    ProjectStatePanel(model: .snapshotFixture(), onRefresh: {}, onCreate: {})
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.light)
}

#Preview("ProjectState · loading · reduceMotion · dark") {
    ProjectStatePanel(
        model: ProjectStatePanelModel(
            projects: [],
            lastMessage: "project.state.list…",
            isLoading: true
        ),
        onRefresh: {},
        onCreate: {}
    )
    .preferredColorScheme(.dark)
}
#endif
