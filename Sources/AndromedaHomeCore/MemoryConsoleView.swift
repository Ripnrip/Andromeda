/**
 * 🎭 MemoryConsoleView — default AndromedaHome path for memory.*
 *
 * Store / recall / journal via capability IDs only. Embeds live MemoryKit
 * Capture + Retrieval through AndromedaMemorySession — no tracker brands.
 */

import SwiftUI

@MainActor
public struct MemoryConsoleView: View {
    @Bindable public var session: AndromedaMemorySession
    @Binding public var query: String
    public var onSubmit: () -> Void
    /// 🧪 When true, prefer hourglass over ProgressView (snapshots / reduce-motion previews).
    public var forceReduceMotion: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool

    public init(
        session: AndromedaMemorySession,
        query: Binding<String>,
        onSubmit: @escaping () -> Void,
        forceReduceMotion: Bool = false
    ) {
        self.session = session
        self._query = query
        self.onSubmit = onSubmit
        self.forceReduceMotion = forceReduceMotion
    }

    private var effectiveReduceMotion: Bool {
        forceReduceMotion || reduceMotion
    }

    /// 🌟 Verb currently implied by the field (or nil when empty / unrecognized).
    private var activeVerb: MemoryConsoleVerb? {
        MemoryConsoleVerb.detect(in: query)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            verbChipRow
            commandField
            guidanceStrip
            runRow
            outcomeTray
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("andromedaHome.memory.console")
        .accessibilityLabel("Memory console")
        .accessibilityHint("Recall, store, or journal memories using memory capabilities.")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
                .symbolEffect(.pulse, isActive: !effectiveReduceMotion && session.lastOutcome == .syncing)

            VStack(alignment: .leading, spacing: 2) {
                Text("memory.*")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("recall · store · journal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Capabilities: memory recall, memory store, memory journal")
            }

            Spacer(minLength: 8)

            visibilityBadge
        }
        .accessibilityIdentifier("andromedaHome.memory.header")
    }

    private var visibilityBadge: some View {
        Text(session.activeVisibility.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .accessibilityLabel("Active visibility \(session.activeVisibility.rawValue)")
            .accessibilityIdentifier("andromedaHome.memory.visibility")
    }

    // MARK: - Verb chips

    private var verbChipRow: some View {
        HStack(spacing: 8) {
            ForEach(MemoryConsoleVerb.allCases) { verb in
                verbChip(verb)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory verbs")
    }

    private func verbChip(_ verb: MemoryConsoleVerb) -> some View {
        let selected = activeVerb == verb
        return Button {
            insertVerb(verb)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: verb.systemImage)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(verb.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .background(
            selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.15), value: selected)
        .accessibilityLabel(verb.accessibilityLabel)
        .accessibilityHint(verb.accessibilityHint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("andromedaHome.memory.verb.\(verb.rawValue)")
    }

    // MARK: - Field + guidance

    private var commandField: some View {
        TextField(fieldPlaceholder, text: $query)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($fieldFocused)
            .onSubmit(onSubmit)
            .accessibilityLabel("Memory command")
            .accessibilityValue(query.isEmpty ? "Empty" : query)
            .accessibilityHint(fieldAccessibilityHint)
            .accessibilityIdentifier("andromedaHome.memory.field")
    }

    private var fieldPlaceholder: String {
        switch activeVerb {
        case .recall: return "recall <query>…"
        case .store: return "store <narrative>…"
        case .journal: return "journal <session notes>…"
        case .none: return "recall / store / journal …"
        }
    }

    private var fieldAccessibilityHint: String {
        switch activeVerb {
        case .recall:
            return "Type a search query after recall, then press Return to run \(AndromedaMemoryCapability.recall.rawValue)."
        case .store:
            return "Type the memory narrative after store, then press Return to run \(AndromedaMemoryCapability.store.rawValue)."
        case .journal:
            return "Type session notes after journal, then press Return to run \(AndromedaMemoryCapability.journal.rawValue)."
        case .none:
            return "Choose recall, store, or journal, then type text. Press Return to run."
        }
    }

    @ViewBuilder
    private var guidanceStrip: some View {
        let copy = guidanceCopy
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: copy.systemImage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(copy.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy.accessibilityLabel)
        .accessibilityIdentifier("andromedaHome.memory.guidance")
    }

    private var guidanceCopy: (text: String, systemImage: String, accessibilityLabel: String) {
        if let parsed = AndromedaMemoryCommand.parse(query) {
            switch parsed {
            case .recall(let q) where q.isEmpty:
                return (
                    "\(AndromedaMemoryCapability.recall.rawValue) — type a query, then Run",
                    "magnifyingglass",
                    "Memory recall ready. Type a query then run."
                )
            case .recall:
                return (
                    "↩︎ Run · \(AndromedaMemoryCapability.recall.rawValue)",
                    "magnifyingglass",
                    "Press Return to run memory recall."
                )
            case .store(let n) where n.isEmpty:
                return (
                    "\(AndromedaMemoryCapability.store.rawValue) — type what to remember",
                    "tray.and.arrow.down",
                    "Memory store ready. Type a narrative then run."
                )
            case .store:
                return (
                    "↩︎ Run · \(AndromedaMemoryCapability.store.rawValue)",
                    "tray.and.arrow.down",
                    "Press Return to store this memory."
                )
            case .journal(let b) where b.isEmpty:
                return (
                    "\(AndromedaMemoryCapability.journal.rawValue) — empty dumps a session stamp",
                    "book.closed",
                    "Memory journal ready. Optional notes, or Run for a session dump."
                )
            case .journal:
                return (
                    "↩︎ Run · \(AndromedaMemoryCapability.journal.rawValue) / \(AndromedaMemoryCapability.sessionDump.rawValue)",
                    "book.closed",
                    "Press Return to journal this session dump."
                )
            }
        }

        switch activeVerb {
        case .recall:
            return (
                "\(AndromedaMemoryCapability.recall.rawValue) — type a query after the verb",
                "magnifyingglass",
                "Continue typing a recall query."
            )
        case .store:
            return (
                "\(AndromedaMemoryCapability.store.rawValue) — type a narrative after the verb",
                "tray.and.arrow.down",
                "Continue typing a store narrative."
            )
        case .journal:
            return (
                "\(AndromedaMemoryCapability.journal.rawValue) — type notes or Run for session dump",
                "book.closed",
                "Continue typing journal notes."
            )
        case .none:
            return (
                "Pick a verb · \(AndromedaMemoryCapability.recall.rawValue) · \(AndromedaMemoryCapability.store.rawValue) · \(AndromedaMemoryCapability.journal.rawValue)",
                "sparkles",
                "Memory capabilities ready. Choose recall, store, or journal."
            )
        }
    }

    private var runRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                onSubmit()
            } label: {
                Label("Run", systemImage: "return")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(session.lastOutcome == .syncing)
            .accessibilityLabel(runAccessibilityLabel)
            .accessibilityHint("Executes the memory command in the field.")
            .accessibilityIdentifier("andromedaHome.memory.run")
        }
    }

    private var runAccessibilityLabel: String {
        if let verb = activeVerb {
            return "Run \(verb.capability.rawValue)"
        }
        return "Run memory command"
    }

    // MARK: - Outcome tray

    @ViewBuilder
    private var outcomeTray: some View {
        switch session.lastOutcome {
        case .idle:
            EmptyView()
        case .syncing:
            syncingRow
        case .recalled(let hits, let degraded, let note):
            recalledSection(hits: hits, degraded: degraded, note: note)
        case .stored(let id):
            successBanner(
                title: "Stored",
                detail: "\(AndromedaMemoryCapability.store.rawValue) · id \(id)…",
                systemImage: "tray.and.arrow.down.fill"
            )
        case .journaled(let id):
            successBanner(
                title: "Journaled",
                detail: "\(AndromedaMemoryCapability.sessionDump.rawValue) · id \(id)…",
                systemImage: "book.closed.fill"
            )
        case .empty(let message):
            Label(message, systemImage: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(message)
                .accessibilityIdentifier("andromedaHome.memory.empty")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
                .accessibilityIdentifier("andromedaHome.memory.error")
        }
    }

    private var syncingRow: some View {
        HStack(spacing: 8) {
            if effectiveReduceMotion {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(syncingCopy)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(syncingAccessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("andromedaHome.memory.syncing")
    }

    private var syncingCopy: String {
        switch activeVerb {
        case .recall: return "Recalling…"
        case .store: return "Storing…"
        case .journal: return "Journaling…"
        case .none: return "Working…"
        }
    }

    private var syncingAccessibilityLabel: String {
        switch activeVerb {
        case .recall: return "\(AndromedaMemoryCapability.recall.rawValue) in progress"
        case .store: return "\(AndromedaMemoryCapability.store.rawValue) in progress"
        case .journal: return "\(AndromedaMemoryCapability.journal.rawValue) in progress"
        case .none: return "Memory command in progress"
        }
    }

    @ViewBuilder
    private func recalledSection(hits: [AndromedaMemoryHit], degraded: Bool, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MEMORIES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if degraded {
                    Text("degraded")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Results degraded")
                }
                Spacer()
                Text("\(hits.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(hits.count) memories")
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(hits.prefix(6)) { hit in
                hitRow(hit)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recall results, \(hits.count) memories")
        .accessibilityIdentifier("andromedaHome.memory.results")
    }

    private func hitRow(_ hit: AndromedaMemoryHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hit.sourceLabel == "vault" ? "books.vertical" : "bolt.horizontal.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(hit.sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let visibility = hit.visibility {
                        Text(visibility)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !hit.subtitle.isEmpty {
                        Text(hit.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hitAccessibilityLabel(hit))
    }

    private func hitAccessibilityLabel(_ hit: AndromedaMemoryHit) -> String {
        var parts = [hit.title, "source \(hit.sourceLabel)"]
        if let visibility = hit.visibility {
            parts.append("visibility \(visibility)")
        }
        if !hit.subtitle.isEmpty {
            parts.append(hit.subtitle)
        }
        return parts.joined(separator: ", ")
    }

    private func successBanner(title: String, detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier("andromedaHome.memory.success")
    }

    // MARK: - Actions

    private func insertVerb(_ verb: MemoryConsoleVerb) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || AndromedaMemoryCommand.parse(query) == nil || activeVerb != verb {
            query = "\(verb.rawValue) "
        } else if !query.lowercased().hasPrefix(verb.rawValue) {
            query = "\(verb.rawValue) "
        }
        fieldFocused = true
    }
}

// MARK: - Verb model

/// 🌟 Client-facing memory verbs shown as console chips.
public enum MemoryConsoleVerb: String, CaseIterable, Identifiable, Sendable {
    case recall
    case store
    case journal

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .recall: return "magnifyingglass"
        case .store: return "tray.and.arrow.down"
        case .journal: return "book.closed"
        }
    }

    public var capability: AndromedaMemoryCapability {
        switch self {
        case .recall: return .recall
        case .store: return .store
        case .journal: return .journal
        }
    }

    public var accessibilityLabel: String {
        "Insert \(rawValue) for \(capability.rawValue)"
    }

    public var accessibilityHint: String {
        switch self {
        case .recall: return "Search stored memories and vault notes."
        case .store: return "Capture a new memory narrative."
        case .journal: return "Write a session dump journal entry."
        }
    }

    /// 🔮 Detect leading verb even when the rest is incomplete.
    public static func detect(in raw: String) -> MemoryConsoleVerb? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        if lower.hasPrefix("recall") { return .recall }
        if lower.hasPrefix("store") { return .store }
        if lower.hasPrefix("journal") || lower.hasPrefix("session dump") || lower.hasPrefix("sessiondump") {
            return .journal
        }
        return nil
    }
}

#if DEBUG
#Preview("Memory console · idle · light") {
    @Previewable @State var query = ""
    let session = AndromedaMemorySession()
    return MemoryConsoleView(session: session, query: $query, onSubmit: {})
        .padding()
        .frame(width: 420)
        .preferredColorScheme(.light)
}

#Preview("Memory console · recall ready · dark") {
    @Previewable @State var query = "recall "
    let session = AndromedaMemorySession()
    return MemoryConsoleView(session: session, query: $query, onSubmit: {})
        .padding()
        .frame(width: 420)
        .preferredColorScheme(.dark)
}

#Preview("Memory console · recalled · dark · a11y2") {
    @Previewable @State var query = "recall andromeda"
    let session = AndromedaMemorySession()
    session.lastOutcome = .recalled(
        hits: [
            AndromedaMemoryHit(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                title: "Studio hosts the hive mind; Book recalls as a satellite.",
                subtitle: "multibrain · ~/Developer/SecondBrain",
                sourceLabel: "hot",
                visibility: "private"
            )
        ],
        degraded: false,
        note: nil
    )
    return MemoryConsoleView(session: session, query: $query, onSubmit: {})
        .environment(\.dynamicTypeSize, .accessibility2)
        .padding()
        .frame(width: 420)
        .preferredColorScheme(.dark)
}

#Preview("Memory console · syncing · reduceMotion") {
    @Previewable @State var query = "store hello"
    let session = AndromedaMemorySession()
    session.lastOutcome = .syncing
    return MemoryConsoleView(session: session, query: $query, onSubmit: {}, forceReduceMotion: true)
        .padding()
        .frame(width: 420)
}

#Preview("Memory console · store success · light") {
    @Previewable @State var query = "store hello hive"
    let session = AndromedaMemorySession()
    session.lastOutcome = .stored(idSummary: "A1B2C3D4")
    return MemoryConsoleView(session: session, query: $query, onSubmit: {})
        .padding()
        .frame(width: 420)
        .preferredColorScheme(.light)
}
#endif
