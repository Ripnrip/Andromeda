#if canImport(AppKit)
import AppKit
import SwiftUI

/**
 Modern SwiftUI chrome for the Andromeda floating HUD (BIN-58).

 Collapsed: status glyph + brand + Ask AI affordance in a material pill.
 Expanded: Screendrop-inspired search field routing `memory.*` / `infer.write`.
 */
@MainActor
public struct AndromedaHUDView: View {
    @Bindable public var model: AndromedaHUDModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let honorSystemReduceMotion: Bool

    public init(
        model: AndromedaHUDModel,
        honorSystemReduceMotion: Bool = true
    ) {
        self.model = model
        self.honorSystemReduceMotion = honorSystemReduceMotion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pillBar
            if model.expansion.isExpanded {
                expandedPanel
                    .transition(reduceMotionEffective ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(10)
        .frame(
            width: model.chromeSize.x,
            alignment: .topLeading
        )
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: model.expansion.isExpanded ? 18 : 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: model.expansion.isExpanded ? 18 : 26, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier("andromedaHUD.root")
        .onAppear {
            if honorSystemReduceMotion, systemReduceMotion {
                model.reduceMotion = true
            }
        }
        .onChange(of: systemReduceMotion) { _, newValue in
            guard honorSystemReduceMotion else { return }
            if newValue { model.reduceMotion = true }
        }
    }

    // MARK: - Collapsed bar

    private var pillBar: some View {
        HStack(spacing: 10) {
            dragHandle
            statusGlyph
            Text("Andromeda")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("andromedaHUD.brand")
            Spacer(minLength: 4)
            askAIButton
        }
        .frame(height: 32)
        .accessibilityIdentifier("andromedaHUD.pill")
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Drag handle")
            .accessibilityIdentifier("andromedaHUD.dragHandle")
            .help("Drag to reposition · release near menu bar to snap")
    }

    private var statusGlyph: some View {
        Image(systemName: model.health.systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(healthTint)
            .symbolEffect(
                .pulse,
                isActive: model.health == .working && !reduceMotionEffective
            )
            .accessibilityLabel(model.health.accessibilityLabel)
            .accessibilityIdentifier("andromedaHUD.health")
    }

    private var askAIButton: some View {
        Button {
            model.toggleExpansion()
        } label: {
            Label(
                model.expansion.isExpanded ? "Close" : "Ask AI",
                systemImage: model.expansion.isExpanded ? "xmark" : "sparkles"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan.opacity(0.85))
        .accessibilityIdentifier("andromedaHUD.askAI")
        .accessibilityLabel(model.expansion.isExpanded ? "Close Ask AI" : "Ask AI")
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.35)
            Text("Ask AI · memory.*")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("andromedaHUD.searchTitle")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("recall … · store … · ask anything", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { model.submitQuery() }
                    .accessibilityIdentifier("andromedaHUD.searchField")
                Button("Go") { model.submitQuery() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("andromedaHUD.submit")
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Tips: recall <q> · store <note> · journal · or free-form infer.write")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.lastMessage {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("andromedaHUD.lastMessage")
            }

            if let timing = model.lastTiming {
                Text(timingLine(timing))
                    .font(.caption2.monospaced())
                    .foregroundStyle(timing.isWithinBudget ? .green : .orange)
                    .accessibilityIdentifier("andromedaHUD.timing")
            }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("andromedaHUD.expanded")
    }

    // MARK: - Chrome helpers

    private var pillBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: model.expansion.isExpanded ? 18 : 26, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: model.expansion.isExpanded ? 18 : 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.55),
                            Color.cyan.opacity(0.12),
                            Color.black.opacity(0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var healthTint: Color {
        switch model.health {
        case .unknown: return .secondary
        case .healthy: return .green
        case .working: return .cyan
        case .degraded: return .orange
        }
    }

    private var reduceMotionEffective: Bool {
        honorSystemReduceMotion ? (model.reduceMotion || systemReduceMotion) : model.reduceMotion
    }

    private func timingLine(_ sample: HUDTimingSample) -> String {
        let ms = String(format: "%.2f", sample.elapsedMilliseconds)
        let budget = String(format: "%.0f", sample.budgetMilliseconds)
        let mark = sample.isWithinBudget ? "ok" : "slow"
        return "\(sample.operation) \(ms)ms / \(budget)ms · \(mark)"
    }
}

// MARK: - Preview catalog

#if DEBUG
@MainActor
enum AndromedaHUDPreviewCatalog {
    static func collapsedHealthy() -> AndromedaHUDModel {
        AndromedaHUDModel(
            expansion: .collapsed,
            snapMode: .menuBar,
            health: .healthy
        )
    }

    static func expandedWorking() -> AndromedaHUDModel {
        AndromedaHUDModel(
            expansion: .expanded,
            snapMode: .floating,
            health: .working,
            healthDetail: "sync",
            query: "recall launch entities"
        )
    }

    static func degraded() -> AndromedaHUDModel {
        AndromedaHUDModel(
            expansion: .collapsed,
            snapMode: .floating,
            health: .degraded,
            healthDetail: "letta"
        )
    }
}

#Preview("HUD · collapsed · healthy · dark") {
    AndromedaHUDView(model: AndromedaHUDPreviewCatalog.collapsedHealthy(), honorSystemReduceMotion: false)
        .padding(24)
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("HUD · expanded · working · dark") {
    AndromedaHUDView(model: AndromedaHUDPreviewCatalog.expandedWorking(), honorSystemReduceMotion: false)
        .padding(24)
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("HUD · collapsed · degraded · light") {
    AndromedaHUDView(model: AndromedaHUDPreviewCatalog.degraded(), honorSystemReduceMotion: false)
        .padding(24)
        .background(Color.white)
        .preferredColorScheme(.light)
}

#Preview("HUD · expanded · a11y2") {
    AndromedaHUDView(model: AndromedaHUDPreviewCatalog.expandedWorking(), honorSystemReduceMotion: false)
        .environment(\.dynamicTypeSize, .accessibility2)
        .padding(24)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
#endif
#else
// SwiftUI HUD chrome is Apple-platform only. Portable model / snap / search compile everywhere.
#endif
