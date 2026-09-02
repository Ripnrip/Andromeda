import SwiftUI

// MARK: - First run

//
// Four beats, continuing the pattern established in the companion HUD's
// `Onboarding.swift`: promise → what we already found → the consolidation →
// the one URL to point everything at. Every step is skippable.

public struct OnboardingFlow: View {
    @Environment(\.palette) private var palette
    @Bindable public var model: OrchestratorModel

    public init(model: OrchestratorModel) {
        self.model = model
    }

    private var step: Int {
        model.onboardingStep ?? 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: providers
                    case 2: consolidation
                    default: clients
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 44)
                .padding(.bottom, 34)
            }
            footer
        }
        // AGENTS.md honesty law: this console is a design preview — the
        // broker, Keychain reads, and gateway wiring it describes are not
        // shipped in this package (fixtures only). Say so on every beat,
        // never let first-run copy read as operational success.
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                Text("◐").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.amber)
                Text("design preview — broker, keychain & gateway wiring not shipped in this package")
                    .font(OrchestratorFont.mono(10))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .panel(radius: 999)
            .padding(.top, 12)
        }
        .background {
            ZStack {
                palette.void
                RadialGradient(colors: [palette.cyan.opacity(0.09), .clear],
                               center: .top, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
        .animation(OrchestratorMotion.entrance, value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 20) {
            AndromedaMarkView(size: 132)
            VStack(spacing: 10) {
                TypedText(model.onboardingTitle, font: OrchestratorFont.editorial(40))
                    .multilineTextAlignment(.center)
                Text(
                    "Andromeda consolidates your MCP servers and model providers behind a single local "
                        + "endpoint that speaks Anthropic messages, OpenAI responses, and chat completions. "
                        + "Nothing leaves this machine unless you route it out."
                )
                .font(OrchestratorFont.sans(14.5))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 560)
            }
            HStack(spacing: 10) {
                ForEach(Array(["local-first", "keys never leave the broker", "one usage ledger"].enumerated()), id: \.offset) { index, promise in
                    HStack(spacing: 8) {
                        Text("◇").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.cyan)
                        Text(promise).font(OrchestratorFont.mono(11)).foregroundStyle(palette.muted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .panel(radius: 999)
                    .entrance(index, step: 0.08)
                }
            }
            .padding(.top, 4)
        }
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Andromeda read the Keychain, not your shell history. Each key becomes a stable proxy id — agents ask for capabilities and never see a provider brand or a token.")
            VStack(spacing: 0) {
                ForEach(Array(discoveredProviders.enumerated()), id: \.element.name) { index, row in
                    HStack(spacing: 13) {
                        Text(row.status.glyph)
                            .font(OrchestratorFont.mono(10, .semibold))
                            .foregroundStyle(row.status.tint(palette))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(OrchestratorFont.sans(12.5, .semibold)).foregroundStyle(palette.ink)
                            Text(row.proxyID).font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Text(row.models).font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
                        StatusBadge(row.status, text: row.state)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Divider().overlay(palette.hairline) }
                    .entrance(index, step: 0.075)
                }
            }
            .panel()
            Text("Add the rest later from Providers & models — nothing here is required to start.")
                .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.dim)
        }
    }

    private var consolidation: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Four client configs list nine servers, three of them twice. Import them once into the supervised host — every client then reads the same registry.")
            HStack(alignment: .center, spacing: 14) {
                sprawl
                VStack(spacing: 6) {
                    Text("⇢").font(OrchestratorFont.mono(18)).foregroundStyle(palette.cyan)
                    Kicker("dedupe")
                }
                .frame(width: 64)
                consolidated
            }
        }
    }

    private var sprawl: some View {
        FlowLayout(spacing: 7) {
            ForEach(Array(sprawlChips.enumerated()), id: \.offset) { index, chip in
                Text(chip)
                    .font(OrchestratorFont.mono(10))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .panel(radius: 7, fill: palette.void)
                    .entrance(index, step: 0.045)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(palette.panel, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.hairline, style: .init(lineWidth: 1, dash: [4, 4]))
        }
    }

    private var consolidated: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                AndromedaMarkView(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("andromeda.mcp.host").font(OrchestratorFont.mono(12, .semibold)).foregroundStyle(palette.ink)
                    Text("supervised · one process").font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                }
            }
            ForEach(Array(hostFacts.enumerated()), id: \.offset) { index, fact in
                HStack(spacing: 9) {
                    Text("●").font(OrchestratorFont.mono(10, .semibold))
                        .foregroundStyle(index == 2 ? palette.green : palette.cyan)
                    Text(fact.0).font(OrchestratorFont.mono(11)).foregroundStyle(palette.ink)
                    Spacer()
                    Text(fact.1).font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                }
                .entrance(index, step: 0.07)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .panel(radius: 12, fill: palette.cyan.opacity(0.07), border: palette.cyan.opacity(0.4))
    }

    private var clients: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                "Three dialects, one endpoint, one usage ledger. Existing SDKs need only a base URL "
                    + "change — the gateway translates request shapes and injects cache breakpoints on the way through."
            )
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("base url")
                    Text("https://gw.andromeda.local/v1")
                        .font(OrchestratorFont.mono(15, .semibold))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                Button("COPY") {}
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }
            .padding(16)
            .panel(radius: 12, fill: palette.cyan.opacity(0.08), border: palette.cyan.opacity(0.45))

            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(Dialect.allCases.enumerated()), id: \.element) { index, dialect in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dialect.path)
                            .font(OrchestratorFont.mono(10.5, .semibold))
                            .foregroundStyle(index == 0 ? palette.cyan : index == 1 ? palette.green : palette.muted)
                        Text(dialect.note)
                            .font(OrchestratorFont.sans(11))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dialect.clients)
                            .font(OrchestratorFont.mono(10))
                            .foregroundStyle(palette.dim)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(radius: 11)
                    .entrance(index, step: 0.1)
                }
            }
        }
    }

    private func header(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TypedText(model.onboardingTitle, font: OrchestratorFont.editorial(30))
            Text(body)
                .font(OrchestratorFont.sans(13))
                .foregroundStyle(palette.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0 ..< OrchestratorModel.onboardingTitles.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? palette.cyan : palette.hairline)
                        .frame(width: index == step ? 26 : 10, height: 4)
                        .animation(OrchestratorMotion.settle, value: step)
                }
            }
            Text("step \(step + 1) of \(OrchestratorModel.onboardingTitles.count)")
                .font(OrchestratorFont.mono(11))
                .foregroundStyle(palette.muted)
            Spacer()
            Button("SKIP SETUP") { model.skipOnboarding() }
                .buttonStyle(ConsoleButtonStyle(kind: .quiet))
            Button(step >= OrchestratorModel.onboardingTitles.count - 1 ? "ENTER CONSOLE" : "CONTINUE") {
                model.advanceOnboarding()
            }
            .buttonStyle(ConsoleButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .background(palette.chrome)
        .overlay(alignment: .top) { Divider().overlay(palette.hairline) }
    }

    // MARK: Fixtures

    private struct DiscoveredProvider {
        var name: String
        var proxyID: String
        var models: String
        var state: String
        var status: OrchestratorStatus
    }

    private var discoveredProviders: [DiscoveredProvider] {
        [
            .init(name: "Anthropic", proxyID: "proxy:anthropic_key", models: "6 models", state: "BOUND", status: .healthy),
            .init(name: "OpenAI", proxyID: "proxy:openai_key", models: "7 models", state: "BOUND", status: .healthy),
            .init(name: "Google", proxyID: "proxy:google_key", models: "5 models", state: "BOUND", status: .healthy),
            .init(name: "Bedrock", proxyID: "proxy:aws_sigv4", models: "5 models", state: "VERIFYING", status: .verifying),
            .init(name: "Ollama (local)", proxyID: "127.0.0.1:11434", models: "3 models", state: "NO KEY NEEDED", status: .healthy),
            .init(name: "xAI", proxyID: "not found", models: "—", state: "SKIPPED", status: .idle),
        ]
    }

    private var sprawlChips: [String] {
        ["claude_desktop_config.json", "cursor/mcp.json", ".vscode/mcp.json", "codex.toml",
         "github ×3", "slack ×2", "unpinned npx", "no scopes", "no telemetry", "6 zombie pids"]
    }

    private var hostFacts: [(String, String)] {
        [("9 servers", "1 process"), ("63 tools", "12 withheld"), ("7 duplicate secrets", "0")]
    }
}

// MARK: - Flow layout

//
// Wrapping chip row. `Layout` rather than a nested HStack grid so chips reflow
// with the window instead of clipping.

public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("Onboarding · welcome") {
    OnboardingFlow(model: OrchestratorModel())
        .frame(width: 980, height: 700)
        .orchestratorPalette()
}

#Preview("Onboarding · consolidation") {
    let model = OrchestratorModel()
    model.onboardingStep = 2
    return OnboardingFlow(model: model)
        .frame(width: 980, height: 700)
        .orchestratorPalette()
}
