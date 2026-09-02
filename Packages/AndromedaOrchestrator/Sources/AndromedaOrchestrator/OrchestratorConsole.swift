import SwiftUI

// MARK: - Console shell

//
// Header · sidebar · screen. The launch reveal and first-run flow sit above
// the whole thing as full-window overlays, so the console is always mounted
// and warm behind them.

public struct OrchestratorConsole: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var systemScheme

    @State private var model: OrchestratorModel
    @State private var scheme: ColorScheme
    @State private var launchTask: Task<Void, Never>?

    public init(model: OrchestratorModel = OrchestratorModel(), scheme: ColorScheme = .dark) {
        _model = State(initialValue: model)
        _scheme = State(initialValue: scheme)
    }

    public var body: some View {
        ZStack {
            OrchestratorSurface()

            VStack(spacing: 0) {
                header
                Divider().overlay(palette.hairline)
                HStack(spacing: 0) {
                    sidebar
                    Divider().overlay(palette.hairline)
                    screen
                }
            }

            // Docked placement hides while detached — the detached window
            // (presented by the host app via HUDWindowController) owns the HUD.
            if !model.hudDetached {
                HUDPanel(model: model)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if model.onboardingStep != nil, model.launchPhase == .idle {
                OnboardingFlow(model: model)
                    .transition(.opacity)
                    .zIndex(50)
            }

            if model.launchPhase != .idle {
                LaunchRevealView(model: model)
                    .zIndex(60)
            }
        }
        .environment(\.colorScheme, scheme)
        .orchestratorPalette()
        .foregroundStyle(palette.ink)
        .sheet(item: $model.wizard) { wizard in
            AddResourceSheet(model: model, wizard: wizard)
                .environment(\.colorScheme, scheme)
                .orchestratorPalette()
        }
        .task { await model.streamRequests() }
        // The task ID must stay true for the WHOLE reveal: `.markOnly` flips
        // to false the moment the sequence advances to `.wordmark`, which
        // cancels `runLaunchSequence()` mid-flight and strands the overlay
        // (skip sets `.dissolving`, but the dead task can never reach `.idle`).
        // Any non-idle phase keeps the sequence alive; completion flips the
        // ID to false after `.idle` is already set.
        .task(id: model.launchPhase != .idle) {
            guard model.launchPhase == .markOnly else { return }
            await model.runLaunchSequence()
        }
        .animation(OrchestratorMotion.entrance, value: model.onboardingStep)
        .animation(OrchestratorMotion.entrance, value: model.screen)
        #if os(macOS)
            .onExitCommand { model.skipLaunch() }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 11) {
                AndromedaMarkView(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Andromeda").font(OrchestratorFont.sans(13, .semibold))
                    Kicker("orchestrator")
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Text("3 dialects").font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                Text("messages · responses · completions")
                    .font(OrchestratorFont.mono(10, .semibold))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .panel(radius: 8, fill: palette.void)

            Button("FIRST RUN") {
                launchTask?.cancel()
                model.replayFirstRun()
            }
            .buttonStyle(ConsoleButtonStyle(kind: .primary))

            Button(scheme == .dark ? "◐ LIGHT" : "◑ OBSIDIAN") {
                withAnimation(OrchestratorMotion.settle) {
                    scheme = scheme == .dark ? .light : .dark
                }
            }
            .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            .accessibilityLabel(scheme == .dark ? "Switch to light mode" : "Switch to obsidian mode")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(palette.chrome)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(OrchestratorModel.Screen.allCases.enumerated()), id: \.element) { index, item in
                NavRow(screen: item, badge: badge(for: item), isSelected: model.screen == item) {
                    model.screen = item
                }
                .entrance(index, step: 0.04)
            }

            Divider().overlay(palette.hairline).padding(.vertical, 10)

            Button { model.open(.addModel) } label: {
                addRow("Add a model")
            }
            .buttonStyle(.plain)

            Button { model.open(.addMCPServer) } label: {
                addRow("Add an MCP server")
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Kicker("gateway")
                Text("gw.andromeda.local")
                    .font(OrchestratorFont.mono(10.5, .semibold))
                    .foregroundStyle(palette.ink)
                StatusBadge(.healthy, text: "LISTENING")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 11, fill: palette.void)
        }
        .padding(12)
        .frame(width: 232)
        .background(palette.chrome)
    }

    private func addRow(_ title: String) -> some View {
        HStack(spacing: 11) {
            Text("＋").font(OrchestratorFont.mono(11, .semibold)).foregroundStyle(palette.cyan)
            Text(title).font(OrchestratorFont.sans(12.5)).foregroundStyle(palette.muted)
            Spacer()
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .contentShape(.rect)
    }

    private func badge(for screen: OrchestratorModel.Screen) -> String? {
        switch screen {
        case .overview: "live"
        case .registry: "\(model.mcpServers.count)"
        case .providers: "\(model.providers.count)"
        case .usage: model.totalSpend
        case .gateway: "3"
        case .states: "6"
        }
    }

    // MARK: Screens

    private var screen: some View {
        ScrollView {
            Group {
                switch model.screen {
                case .overview: OverviewScreen(model: model)
                case .registry: RegistryScreen(model: model)
                case .providers: ProvidersScreen(model: model)
                case .usage: UsageScreen(model: model)
                case .gateway: GatewayScreen(model: model)
                case .states: StatesScreen(model: model)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.void)
    }
}

#Preview("Console · obsidian") {
    OrchestratorConsole(model: OrchestratorModel(firstRun: false), scheme: .dark)
        .frame(width: 1440, height: 900)
}

#Preview("Console · light") {
    OrchestratorConsole(model: OrchestratorModel(firstRun: false), scheme: .light)
        .frame(width: 1440, height: 900)
}

#Preview("Console · first run") {
    OrchestratorConsole(model: OrchestratorModel(), scheme: .dark)
        .frame(width: 1440, height: 900)
}
