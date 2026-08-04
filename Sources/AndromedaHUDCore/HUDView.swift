import AppKit
import SwiftUI
import MemoryKit

public struct HUDView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var idleWidth: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var expandedWidth: CGFloat = 350
    @ScaledMetric(relativeTo: .body) private var idleResultsWidth: CGFloat = 178
    @ScaledMetric(relativeTo: .body) private var expandedResultsWidth: CGFloat = 378
    @State private var isExpanded: Bool
    @State private var searchQuery: String
    @FocusState private var isSearchFocused: Bool
    @State private var model: HUDModel
    @State private var searchVM: MemorySearchViewModel
    /// Keyboard selection among recalled memory hits (wrap-around).
    @State private var selectedIndex: Int = 0

    public init() {
        let model = HUDModel()
        self._isExpanded = State(initialValue: false)
        self._searchQuery = State(initialValue: "")
        self._model = State(initialValue: model)
        self._searchVM = State(initialValue: MemorySearchViewModel(hudModel: model))
    }

    // Internal initializer for testing
    init(isExpanded: Bool = false, searchQuery: String = "", model: HUDModel = HUDModel()) {
        self._isExpanded = State(initialValue: isExpanded)
        self._searchQuery = State(initialValue: searchQuery)
        self._model = State(initialValue: model)
        self._searchVM = State(initialValue: MemorySearchViewModel(hudModel: model))
    }

    private var resultsVisible: Bool {
        isExpanded && (
            model.lastOutcome.showsResultsPanel
            || showRecentQueries
        )
    }

    private var showRecentQueries: Bool {
        isExpanded
            && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.recentQueries.isEmpty
            && (model.lastOutcome == .idle || !model.lastOutcome.showsResultsPanel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 0) {
                DragHandleView()

                HStack(spacing: 8) {
                    HUDFleetPulseChip(pulse: model.fleetPulse)
                        .onTapGesture { expandAndFocusSearch() }

                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                        .onTapGesture { expandAndFocusSearch() }

                    TextField("recall · store · journal · infer.write…", text: $searchQuery)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Memory command")
                        .accessibilityHint("Type recall, store, journal, infer.write, or project.state. Arrow keys move among results. Escape dismisses results.")
                        .onSubmit {
                            handleSubmit()
                        }
                        // Escape while TextField is first responder (Enter stays on onSubmit).
                        .onKeyPress(.escape) {
                            handleEscape()
                            return .handled
                        }
                }
                // Fill the idle/expanded width so clicks land on the TextField
                // (avoid transparent overlay / parent onTapGesture — those steal hits).
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: isExpanded ? expandedWidth : idleWidth, alignment: .leading)
                .background {
                    // NSEvent local monitor beats the field editor for ↑/↓; zero-size
                    // keyboardShortcut Buttons were audit-FAIL unreliable.
                    HUDArrowKeyMonitor(
                        isActive: resultsVisible && selectableItemCount > 0,
                        onUp: { moveSelection(up: true) },
                        onDown: { moveSelection(up: false) }
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                // Escape backup when focus is not in the TextField (e.g. results row).
                Button("") { handleEscape() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .padding(4)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .overlay(
                        Capsule()
                            .stroke(Color.andromedaLine, lineWidth: 1)
                    )
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)

            if let feedback = model.activationFeedback {
                Text(feedback)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .accessibilityLabel(feedback)
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            HUDResultsView(isVisible: resultsVisible) {
                if showRecentQueries {
                    HUDRecentQueriesView(
                        queries: model.recentQueries,
                        selectedIndex: selectedIndex,
                        onSelect: { q in
                            searchQuery = q
                            isSearchFocused = true
                            submitSearch()
                        }
                    )
                } else {
                    HUDOutcomeView(
                        outcome: model.lastOutcome,
                        selectedIndex: selectedIndex,
                        isLiveSearching: searchVM.isSearching,
                        onActivateHit: activateHit,
                        onActivateProjectItem: activateProjectItem
                    )
                }
            }
            .frame(width: isExpanded ? expandedResultsWidth : idleResultsWidth)
            .fixedSize(horizontal: false, vertical: resultsVisible)
        }
        .fixedSize(horizontal: true, vertical: true)
        .onChange(of: isSearchFocused) { _, newValue in
            if newValue {
                isExpanded = true
            } else {
                // Lose-focus polish: collapse results / pill without killing the window.
                collapseResultsKeepingWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .andromedaHUDFocusSearch)) { _ in
            expandAndFocusSearch()
        }
        .onChange(of: searchQuery) { oldValue, newValue in
            selectedIndex = 0
            searchVM.updateQueryFromField(newValue)
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Empty field + expanded → recent queries (clear prior outcome).
                if isExpanded {
                    model.dismissResults()
                }
                searchVM.cancelPendingSearch()
            } else if newValue != oldValue {
                isExpanded = true
            }
        }
        .onChange(of: model.lastOutcome) { _, _ in
            selectedIndex = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .andromedaHUDCollapseResults)) { _ in
            collapseResultsKeepingWindow()
        }
        .task {
            if !model.isReady {
                await model.start()
            }
            // Keep searchVM pointed at the same model instance.
            searchVM.hudModel = model
        }
    }

    // MARK: - Expand / focus

    private func expandAndFocusSearch() {
        isExpanded = true
        isSearchFocused = true
    }

    // MARK: - Collapse / Escape

    private func handleEscape() {
        // Always abandon Working / in-flight recall — never leave the spinner stuck.
        model.cancelInFlightWork()
        searchVM.cancelPendingSearch()
        if model.lastOutcome.showsResultsPanel || showRecentQueries {
            model.dismissResults()
            return
        }
        if isExpanded {
            isExpanded = false
            isSearchFocused = false
            return
        }
        // Already collapsed — ask app to orderOut (hide) without quitting.
        NotificationCenter.default.post(name: .andromedaHUDRequestHide, object: nil)
    }

    private func collapseResultsKeepingWindow() {
        model.cancelInFlightWork()
        model.dismissResults()
        searchVM.cancelPendingSearch()
        isExpanded = false
        // Do not orderOut — window stays; status item can re-focus.
    }

    // MARK: - Keyboard / activation

    private var selectableItemCount: Int {
        HUDSelectionNavigation.selectableCount(
            outcome: model.lastOutcome,
            showRecentQueries: showRecentQueries,
            recentQueryCount: model.recentQueries.count
        )
    }

    private func moveSelection(up: Bool) {
        let total = selectableItemCount
        guard total > 0 else { return }
        selectedIndex = HUDSelectionNavigation.move(selectedIndex: selectedIndex, total: total, up: up)
        isExpanded = true
    }

    private func handleSubmit() {
        searchVM.cancelPendingSearch()
        if showRecentQueries {
            let queries = Array(model.recentQueries.prefix(HUDSelectionNavigation.recentQueriesVisibleLimit))
            if selectedIndex >= 0, selectedIndex < queries.count {
                searchQuery = queries[selectedIndex]
                submitSearch()
                return
            }
        }
        switch model.lastOutcome {
        case .recalled(let hits) where !hits.isEmpty && selectedIndex >= 0 && selectedIndex < hits.count:
            activateHit(hits[selectedIndex])
        case .projects(let states):
            let items = HUDProjectResultsView.flattenedOpenItems(from: states)
            if selectedIndex >= 0, selectedIndex < items.count {
                activateProjectItem(items[selectedIndex])
            } else {
                submitSearch()
            }
        default:
            submitSearch()
        }
    }

    private func submitSearch() {
        Task {
            await model.submitQuery(searchQuery)
            isExpanded = true
            isSearchFocused = true
        }
    }

    private func activateHit(_ hit: MemoryHit) {
        if let path = hit.path, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            model.showActivationFeedback("Opened \(URL(fileURLWithPath: expanded).lastPathComponent)")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hit.narrative, forType: .string)
        model.showActivationFeedback("Copied to clipboard")
    }

    private func activateProjectItem(_ item: ProjectStateItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.title, forType: .string)
        model.showActivationFeedback("Copied item title")
    }
}

// MARK: - Fleet pulse chip

struct HUDFleetPulseChip: View {
    let pulse: HUDFleetPulse

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fleet pulse \(pulse.status.rawValue)")
            .accessibilityValue(pulse.detail)
            .accessibilityHint("\(pulse.attentionCount) attention items")
            .help(pulse.detail)
    }

    private var color: Color {
        switch pulse.status {
        case .green: return .andromedaLive
        case .yellow: return .andromedaAlert
        case .red: return .andromedaAlert
        case .unknown: return .andromedaMuted
        }
    }
}

// MARK: - Recent queries

struct HUDRecentQueriesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let queries: [String]
    var selectedIndex: Int = 0
    var onSelect: (String) -> Void

    var body: some View {
        let visible = Array(queries.prefix(HUDSelectionNavigation.recentQueriesVisibleLimit))
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(visible.enumerated()), id: \.offset) { index, query in
                Button {
                    onSelect(query)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(query)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == selectedIndex ? Color.andromedaSelection : .clear)
                    )
                    .contentShape(Rectangle())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selectedIndex)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent query: \(query)")
                .accessibilityHint("Runs this query again")
                .accessibilityAddTraits(index == selectedIndex ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent queries")
    }
}

struct HUDOutcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let outcome: HUDOutcome
    var selectedIndex: Int = 0
    var isLiveSearching: Bool = false
    var onActivateHit: ((MemoryHit) -> Void)?
    var onActivateProjectItem: ((ProjectStateItem) -> Void)?

    var body: some View {
        switch outcome {
        case .idle:
            EmptyView()
        case .syncing:
            HUDStatusRow(
                systemImage: nil,
                showsProgress: true,
                title: isLiveSearching ? "Searching…" : "Working…",
                accessibilityLabel: "Working on your query"
            )
        case .empty(let msg):
            HUDStatusRow(
                systemImage: "magnifyingglass",
                showsProgress: false,
                title: msg,
                accessibilityLabel: msg,
                emphasis: .secondary
            )
        case .failed(let msg):
            HUDStatusRow(
                systemImage: "exclamationmark.triangle.fill",
                showsProgress: false,
                title: msg,
                accessibilityLabel: "Error: \(msg)",
                emphasis: .warning
            )
        case .stored(let id):
            HUDStatusRow(
                systemImage: "tray.and.arrow.down.fill",
                showsProgress: false,
                title: "Stored memory (id: \(id))",
                accessibilityLabel: "Stored memory, ID: \(id)",
                tinted: true
            )
        case .journaled(let id):
            HUDStatusRow(
                systemImage: "book.closed.fill",
                showsProgress: false,
                title: "Journaled session (id: \(id))",
                accessibilityLabel: "Journaled session, ID: \(id)",
                tinted: true
            )
        case .created(let title):
            HUDStatusRow(
                systemImage: "plus.circle.fill",
                showsProgress: false,
                title: "Created via project.state.create: \(title)",
                accessibilityLabel: "Created project item: \(title)",
                tinted: true
            )
        case .updated(let title):
            HUDStatusRow(
                systemImage: "pencil.circle.fill",
                showsProgress: false,
                title: "Updated via project.state.update: \(title)",
                accessibilityLabel: "Updated project item: \(title)",
                tinted: true
            )
        case .recalled(let hits):
            recalledHitsList(hits)
        case .projects(let states):
            HUDProjectResultsView(
                projects: states,
                selectedIndex: selectedIndex,
                onActivateItem: onActivateProjectItem
            )
        }
    }

    @ViewBuilder
    private func recalledHitsList(_ hits: [MemoryHit]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        HUDMemoryHitRow(
                            hit: hit,
                            isSelected: index == selectedIndex,
                            onActivate: { onActivateHit?(hit) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
            .frame(
                minHeight: min(CGFloat(hits.count) * 44, HUDResultsLayout.contentMaxHeight),
                maxHeight: HUDResultsLayout.contentMaxHeight
            )
            .onChange(of: selectedIndex) { _, newIndex in
                if reduceMotion {
                    proxy.scrollTo(newIndex, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

/// Shared empty / error / loading / success row for the results panel.
struct HUDStatusRow: View {
    enum Emphasis {
        case secondary
        case warning
    }

    var systemImage: String?
    var showsProgress: Bool
    var title: String
    var accessibilityLabel: String
    var emphasis: Emphasis = .secondary
    var tinted: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(iconStyle)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(textStyle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(minHeight: HUDResultsLayout.visibleMinHeight - 16, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(showsProgress ? .updatesFrequently : [])
    }

    private var iconStyle: AnyShapeStyle {
        if tinted { return AnyShapeStyle(.tint) }
        switch emphasis {
        case .secondary: return AnyShapeStyle(.secondary)
        case .warning: return AnyShapeStyle(.orange)
        }
    }

    private var textStyle: AnyShapeStyle {
        switch emphasis {
        case .secondary: return AnyShapeStyle(.secondary)
        case .warning: return AnyShapeStyle(.primary)
        }
    }
}

/// 🌐 Capability-safe project.state rows — titles + status labels only (never tracker brands).
struct HUDProjectResultsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let projects: [ProjectState]
    var selectedIndex: Int = 0
    var onActivateItem: ((ProjectStateItem) -> Void)?

    nonisolated static func flattenedOpenItems(from projects: [ProjectState]) -> [ProjectStateItem] {
        Array(projects.prefix(4)).flatMap { project in
            Array(project.items.filter { $0.status != .done }.prefix(4))
        }
    }

    var body: some View {
        let flatItems = Self.flattenedOpenItems(from: projects)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(projects.prefix(4))) { project in
                        projectBlock(project, flatItems: flatItems)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
            .frame(
                minHeight: 120,
                maxHeight: HUDResultsLayout.contentMaxHeight
            )
            .onChange(of: selectedIndex) { _, newIndex in
                if reduceMotion {
                    proxy.scrollTo(newIndex, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .accessibilityLabel("project.state results")
    }

    @ViewBuilder
    private func projectBlock(_ project: ProjectState, flatItems: [ProjectStateItem]) -> some View {
        let openItems = Array(project.items.filter { $0.status != .done }.prefix(4))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(project.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(ProjectStatePanelModel.statusLabel(project.status))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(project.title), \(ProjectStatePanelModel.statusLabel(project.status))")

            if openItems.isEmpty {
                Text("No open items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 22)
            } else {
                ForEach(Array(openItems.enumerated()), id: \.element.id) { _, item in
                    let globalIndex = flatItems.firstIndex(where: { $0.id == item.id }) ?? 0
                    projectItemRow(item: item, globalIndex: globalIndex)
                }
            }
        }
    }

    private func projectItemRow(item: ProjectStateItem, globalIndex: Int) -> some View {
        Button {
            onActivateItem?(item)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(statusColor(for: item.status))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(ProjectStatePanelModel.statusLabel(item.status))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.leading, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(globalIndex == selectedIndex ? Color.andromedaSelection : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(globalIndex)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(ProjectStatePanelModel.statusLabel(item.status))")
        .accessibilityAddTraits(globalIndex == selectedIndex ? [.isSelected, .isButton] : .isButton)
    }

    private func statusColor(for status: ProjectStateStatus) -> Color {
        switch status {
        case .backlog: return .andromedaMuted
        case .active: return .andromedaTeal
        case .blocked: return .andromedaAlert
        case .done: return .andromedaLive
        }
    }
}

/// One recalled memory row — highlight + click/Enter activate.
struct HUDMemoryHitRow: View {
    let hit: MemoryHit
    var isSelected: Bool = false
    let onActivate: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: hit.source == .vault ? "books.vertical" : "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.narrative)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(hit.source == .vault ? "vault" : "hot")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let proj = hit.project {
                            Text("· \(proj)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hit.path == nil ? "Copies narrative to clipboard" : "Opens file path")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var rowFill: Color {
        if isSelected {
            return .andromedaSelection
        }
        if isHovering {
            return .andromedaHover
        }
        return .clear
    }

    private var accessibilityLabel: String {
        var label = "\(hit.narrative). Source: \(hit.source == .vault ? "Vault" : "Hot")"
        if let project = hit.project {
            label += ", Project: \(project)"
        }
        if isSelected {
            label += ", selected"
        }
        return label
    }
}

struct DragHandleView: View {
    var body: some View {
        WindowDragRegion()
            .frame(width: 22, height: 28)
            .padding(.horizontal, 6)
            .overlay {
                VStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
                .foregroundStyle(.white.opacity(0.3))
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Move window")
            .accessibilityHint("Drag to reposition the HUD.")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// Bridges SwiftUI to AppKit's public `NSWindow.performDrag(with:)` for native window dragging.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        let startOrigin = window?.frame.origin
        window?.performDrag(with: event)
        if let window, window.frame.origin != startOrigin {
            NotificationCenter.default.post(name: .andromedaHUDUserDidDragWindow, object: window)
        }
    }
}

public extension Notification.Name {
    /// Posted when the user finishes a free drag of the HUD (mouse-up after performDrag).
    static let andromedaHUDUserDidDragWindow = Notification.Name("andromeda.hud.userDidDragWindow")
    /// Collapse results / pill without quitting (click-outside / resign key).
    static let andromedaHUDCollapseResults = Notification.Name("andromeda.hud.collapseResults")
    /// Hide the HUD panel (orderOut) — Escape when already collapsed.
    static let andromedaHUDRequestHide = Notification.Name("andromeda.hud.requestHide")
    /// Make the search field key + expand the pill (status item / hotkey show).
    static let andromedaHUDFocusSearch = Notification.Name("andromeda.hud.focusSearch")
}

#Preview("HUD Idle") {
    HUDView()
        .padding()
        .background(Color.gray)
}

#Preview("HUD Recalled · selection") {
    let hits = [
        MemoryHit(narrative: "First memory from the hot store", source: .hotStore, score: 10.0),
        MemoryHit(narrative: "Second memory from the vault", project: "andromeda", source: .vault, score: 8.0),
        MemoryHit(narrative: "Third vault echo about fleet observe", project: "multibrain", source: .vault, score: 6.0),
    ]
    let model = HUDModel()
    model.lastOutcome = .recalled(hits: hits)
    return HUDView(isExpanded: true, searchQuery: "fleet", model: model)
        .padding()
        .background(Color.gray)
}

#Preview("HUD Empty · results polish") {
    let model = HUDModel()
    model.lastOutcome = .empty(message: "No memories matched “xyz”")
    return HUDView(isExpanded: true, searchQuery: "xyz", model: model)
        .padding()
        .background(Color.gray)
}

#Preview("HUD Failed · results polish") {
    let model = HUDModel()
    model.lastOutcome = .failed(message: "Memory store unavailable")
    return HUDView(isExpanded: true, searchQuery: "recall", model: model)
        .padding()
        .background(Color.gray)
}

#Preview("HUD Projects · results panel") {
    let states = [
        ProjectState(
            id: "andromeda",
            title: "Andromeda",
            status: .active,
            items: [
                ProjectStateItem(id: "i1", title: "Wire HUD results panel", status: .active),
                ProjectStateItem(id: "i2", title: "Ship snapshots", status: .backlog),
            ]
        )
    ]
    let model = HUDModel()
    model.lastOutcome = .projects(states: states)
    return HUDView(isExpanded: true, searchQuery: "project.state", model: model)
        .padding()
        .background(Color.gray)
}

#Preview("HUD Syncing · results panel") {
    let model = HUDModel()
    model.lastOutcome = .syncing
    return HUDView(isExpanded: true, searchQuery: "recall fleet", model: model)
        .padding()
        .background(Color.gray)
}

#Preview("HUD Recent queries") {
    let model = HUDModel()
    model.recordRecentQuery("recall fleet observe")
    model.recordRecentQuery("project.state")
    model.recordRecentQuery("infer.write dogfood note")
    return HUDView(isExpanded: true, searchQuery: "", model: model)
        .padding()
        .background(Color.gray)
}

// MARK: - Sub-component previews

#Preview("MemoryHitRow · selected") {
    let hit = MemoryHit(narrative: "Studio hosts the hive mind", project: "andromeda", source: .vault, score: 8.0)
    return HUDMemoryHitRow(hit: hit, isSelected: true, onActivate: {})
        .padding()
        .frame(width: 380)
        .background(Color.gray.opacity(0.2))
}

#Preview("MemoryHitRow · unselected · hot") {
    let hit = MemoryHit(narrative: "Quick ephemeral from the hot store", source: .hotStore, score: 12.0)
    return HUDMemoryHitRow(hit: hit, isSelected: false, onActivate: {})
        .padding()
        .frame(width: 380)
        .background(Color.gray.opacity(0.2))
}

#Preview("FleetPulseChip · green") {
    HUDFleetPulseChip(pulse: HUDFleetPulse(status: .green, attentionCount: 0, detail: "All systems nominal"))
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("FleetPulseChip · red") {
    HUDFleetPulseChip(pulse: HUDFleetPulse(status: .red, attentionCount: 1, detail: "Critical: Qdrant unreachable"))
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("StatusRow · syncing") {
    HUDStatusRow(systemImage: nil, showsProgress: true, title: "Searching…", accessibilityLabel: "Searching")
        .padding()
        .frame(width: 380)
        .background(Color.gray.opacity(0.2))
}

#Preview("StatusRow · failed") {
    HUDStatusRow(systemImage: "exclamationmark.triangle.fill", showsProgress: false, title: "Memory store unavailable", accessibilityLabel: "Error", emphasis: .warning)
        .padding()
        .frame(width: 380)
        .background(Color.gray.opacity(0.2))
}

#Preview("RecentQueriesView") {
    HUDRecentQueriesView(
        queries: ["project.state", "recall fleet observe", "store hello"],
        selectedIndex: 1,
        onSelect: { _ in }
    )
    .padding()
    .frame(width: 380)
    .background(Color.gray.opacity(0.2))
}

#Preview("ProjectResultsView") {
    let states = [
        ProjectState(id: "andromeda", title: "Andromeda", status: .active, items: [
            ProjectStateItem(id: "i1", title: "Wire HUD results panel", status: .active),
            ProjectStateItem(id: "i2", title: "Ship snapshots", status: .backlog),
        ]),
    ]
    return HUDProjectResultsView(projects: states, selectedIndex: 0, onActivateItem: nil)
        .padding()
        .frame(width: 380)
        .background(Color.gray.opacity(0.2))
}

#Preview("DragHandle") {
    DragHandleView()
        .padding()
        .background(Color.gray.opacity(0.2))
}
