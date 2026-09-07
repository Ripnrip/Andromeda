import SwiftUI

// MARK: - HUD

//
// The always-there control surface. Docked it sits in the console's corner;
// detached it becomes the floating macOS panel (see `HUDWindow` below). Its
// tabs drive the console's screen — one surface, two placements, never two
// separate apps.
//
// Interaction patterns (positional context, press-and-hold drag, snap, a
// single detach/dock toggle) follow the companion HUD. Visual language is
// Andromeda's own.

public struct HUDPanel: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    public init(model: OrchestratorModel) {
        self.model = model
    }

    private let tabs: [(String, OrchestratorModel.Screen)] = [
        ("STREAM", .overview),
        ("MCP", .registry),
        ("MODELS", .providers),
        ("USAGE", .usage),
    ]

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            bodyContent
        }
        .frame(width: 292)
        .background(palette.chrome)
        .clipShape(.rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(palette.hairline, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AndromedaMarkView(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Andromeda").font(OrchestratorFont.sans(11.5, .semibold)).foregroundStyle(palette.ink)
                Kicker("hud")
            }
            Spacer()
            Button("LAUNCH") { model.replayFirstRun() }
                .buttonStyle(ConsoleButtonStyle(kind: .quiet))
                .accessibilityLabel("Replay the Andromeda launch reveal")
            Button(model.hudDetached ? "DOCK" : "DETACH") { model.hudDetached.toggle() }
                .buttonStyle(ConsoleButtonStyle(kind: .quiet))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.panel)
        .overlay(alignment: .bottom) { Divider().overlay(palette.hairline) }
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                let selected = model.screen == tab.1
                Button { model.screen = tab.1 } label: {
                    Text(tab.0)
                        .font(OrchestratorFont.mono(9, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(selected ? palette.ink : palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(selected ? palette.cyan.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(selected ? palette.cyan.opacity(0.5) : palette.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(palette.void)
        .overlay(alignment: .bottom) { Divider().overlay(palette.hairline) }
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Kicker("gateway")
                Spacer()
                StatusBadge(.healthy, text: "LISTENING", bordered: false)
            }

            HStack(spacing: 10) {
                hudStat("req/min", "\(Int(model.requestsPerMinute))", palette.cyan)
                hudStat("cache", "\(Int(model.cacheHitRate * 100))%", palette.green)
                hudStat("spend", model.totalSpend, palette.ink)
            }

            Divider().overlay(palette.hairline)

            VStack(alignment: .leading, spacing: 7) {
                Kicker("last calls")
                ForEach(model.requests.prefix(3)) { request in
                    HStack(spacing: 8) {
                        Text(request.cached ? "◈" : "●")
                            .font(OrchestratorFont.mono(9))
                            .foregroundStyle(request.cached ? palette.green : palette.cyan)
                        Text(request.alias)
                            .font(OrchestratorFont.mono(10))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(request.latencyMS)ms")
                            .font(OrchestratorFont.mono(9.5))
                            .foregroundStyle(palette.muted)
                            .monospacedDigit()
                    }
                    .transition(.opacity)
                }
            }
            .animation(OrchestratorMotion.settle, value: model.requests.first?.id)

            HStack(spacing: 8) {
                Button("＋ MODEL") { model.open(.addModel) }
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
                Button("＋ MCP") { model.open(.addMCPServer) }
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }
        }
        .padding(13)
    }

    private func hudStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(label)
            Text(value)
                .font(OrchestratorFont.mono(13, .semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if os(macOS)
    import AppKit

    // MARK: - Floating panel

//
    // Detached, the HUD becomes a non-activating always-on-top panel — the thing
    // the mark flies out of at launch. See `references/macos-patterns.md`.

    public final class HUDWindowController: NSWindowController {
        public convenience init(model: OrchestratorModel) {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 292, height: 420),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentView = NSHostingView(
                rootView: HUDPanel(model: model).orchestratorPalette()
            )
            self.init(window: panel)
        }
    }
#endif

#Preview("HUD · docked") {
    HUDPanel(model: OrchestratorModel(firstRun: false))
        .padding(24)
        .background(OrchestratorPalette.obsidian.void)
        .orchestratorPalette()
}

#Preview("HUD · light") {
    HUDPanel(model: OrchestratorModel(firstRun: false))
        .padding(24)
        .background(OrchestratorPalette.observatory.void)
        .environment(\.colorScheme, .light)
        .orchestratorPalette()
}
