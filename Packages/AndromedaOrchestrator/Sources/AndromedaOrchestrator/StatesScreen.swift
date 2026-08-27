import SwiftUI

// MARK: - States gallery
//
// The six canonical states. Each names the cause, the blast radius, and the
// one action that fixes it — and each carries hue + glyph + word, never hue
// alone. Extends the vocabulary in `Pillars/PillarStates.swift`.

struct StatesScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                ScreenHeader(
                    title: "When there is nothing, or something is wrong",
                    subtitle: "Every state names the cause, the blast radius, and the one action that fixes it."
                )
                Button("REPLAY FIRST RUN") { model.replayFirstRun() }
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                emptyRegistry.entrance(0, step: 0.07)
                idleGateway.entrance(1, step: 0.07)
                reconciling.entrance(2, step: 0.07)
                breakerHalfOpen.entrance(3, step: 0.07)
                credentialError.entrance(4, step: 0.07)
                offlineLane.entrance(5, step: 0.07)
            }
        }
    }

    // MARK: Cards

    private var emptyRegistry: some View {
        StateCard(status: .idle, kicker: "Empty · registry",
                  title: "No MCP servers yet",
                  body: "Three client configs on this machine already list nine servers between them. Import once and every client shares one supervised host.") {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(palette.hairline, style: .init(lineWidth: 1, dash: [4, 4]))
                    .background(palette.void, in: .rect(cornerRadius: 10))
                AndromedaMarkView(size: 52, tint: palette.dim).opacity(0.5)
            }
            .frame(height: 96)
        } actions: {
            Button("SCAN CONFIGS") { model.open(.addMCPServer) }
                .buttonStyle(ConsoleButtonStyle(kind: .primary))
            Button("ADD MANUALLY") { model.open(.addMCPServer) }
                .buttonStyle(ConsoleButtonStyle(kind: .quiet))
        }
    }

    private var idleGateway: some View {
        StateCard(status: .idle, kicker: "Empty · stream",
                  title: "Gateway up · nothing calling it",
                  body: "Listening on all three dialects. The first request will land here within a second of a client pointing at it.") {
            ScanningPlaceholder().frame(height: 96)
        } actions: {
            HStack(spacing: 8) {
                Text("POST").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.cyan)
                Text("gw.andromeda.local/v1/messages")
                    .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 8, fill: palette.void)
        }
    }

    private var reconciling: some View {
        StateCard(status: .verifying, kicker: "Loading · reconciling",
                  title: "Reconciling registry…",
                  body: "Reading nine servers, deduping three token copies. Traffic keeps flowing on the last known-good registry while this runs.") {
            VStack(spacing: 7) {
                ForEach(Array([0.88, 0.62, 0.94, 0.47].enumerated()), id: \.offset) { index, width in
                    SkeletonBar(widthFraction: width, delay: Double(index) * 0.12)
                }
            }
            .padding(12)
            .frame(height: 96)
            .panel(radius: 10, fill: palette.void)
        } actions: {
            HStack(spacing: 9) {
                AndromedaMarkView(size: 20)
                Text("step 2 of 3 · 4s elapsed")
                    .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
            }
        }
    }

    private var breakerHalfOpen: some View {
        StateCard(status: .degraded, kicker: "Degraded · breaker half-open",
                  title: "Traffic already moved",
                  body: "gpt-omni is answering from bedrock/claude-sonnet-4.5. Callers saw no error — only 96ms more latency.",
                  accent: palette.amber) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("openai · 8.4% 5xx")
                        .font(OrchestratorFont.mono(11, .semibold)).foregroundStyle(palette.ink)
                    Spacer()
                    Text("probing in 3s")
                        .font(OrchestratorFont.mono(10)).foregroundStyle(palette.amber)
                }
                ShareBar(share: 0.6, tint: palette.amber)
                Text("1 probe in flight · 3 shed")
                    .font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
            }
            .padding(12)
            .frame(height: 96)
            .panel(radius: 10, fill: palette.void, border: palette.amber.opacity(0.3))
        } actions: {
            Button("HOLD TRAFFIC") {}.buttonStyle(ConsoleButtonStyle(kind: .quiet))
        }
    }

    private var credentialError: some View {
        StateCard(status: .failed, kicker: "Error · credential",
                  title: "The broker holds a stale key",
                  body: "No client ever saw the value, so nothing leaked and nothing needs redeploying. Re-bind once, here.",
                  accent: palette.red) {
            VStack(alignment: .leading, spacing: 6) {
                Text("401 invalid_api_key").foregroundStyle(palette.red)
                Text("host api.openai.com").foregroundStyle(palette.muted)
                Text("secret proxy:openai_key · rotated 14m ago").foregroundStyle(palette.muted)
            }
            .font(OrchestratorFont.mono(10.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(height: 96)
            .panel(radius: 10, fill: palette.void, border: palette.red.opacity(0.3))
        } actions: {
            Button("RE-BIND SECRET") {}.buttonStyle(ConsoleButtonStyle(kind: .danger))
            Button("VIEW LOG") {}.buttonStyle(ConsoleButtonStyle(kind: .quiet))
        }
    }

    private var offlineLane: some View {
        StateCard(status: .idle, kicker: "Offline · local lane",
                  title: "Serving from the local lane",
                  body: "qwen3-14b is answering everything. Quality is lower and the console says so — spend is $0 and 41 calls are queued for replay.") {
            HStack {
                VStack(spacing: 4) {
                    Text("cloud").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.dim)
                    Text("unreachable").font(OrchestratorFont.mono(9.5)).foregroundStyle(palette.dim)
                }
                .frame(maxWidth: .infinity)
                Text("⇢").font(OrchestratorFont.mono(12)).foregroundStyle(palette.hairline)
                VStack(spacing: 4) {
                    Text("ollama").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.cyan)
                    Text("100% of traffic").font(OrchestratorFont.mono(9.5)).foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(height: 96)
            .panel(radius: 10, fill: palette.void)
        } actions: {
            Button("QUEUE CLOUD RETRIES") {}.buttonStyle(ConsoleButtonStyle(kind: .ghost))
        }
    }
}

// MARK: - State card

struct StateCard<Visual: View, Actions: View>: View {
    @Environment(\.palette) private var palette

    var status: OrchestratorStatus
    var kicker: String
    var title: String
    var body_: String
    var accent: Color?
    @ViewBuilder var visual: Visual
    @ViewBuilder var actions: Actions

    init(status: OrchestratorStatus, kicker: String, title: String, body: String,
         accent: Color? = nil,
         @ViewBuilder visual: () -> Visual,
         @ViewBuilder actions: () -> Actions) {
        self.status = status
        self.kicker = kicker
        self.title = title
        self.body_ = body
        self.accent = accent
        self.visual = visual()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(status.glyph)
                    .font(OrchestratorFont.mono(10, .semibold))
                    .foregroundStyle(accent ?? palette.dim)
                Kicker(kicker, tint: accent ?? palette.dim)
            }
            visual
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(OrchestratorFont.sans(13.5, .semibold))
                    .foregroundStyle(palette.ink)
                Text(body_)
                    .font(OrchestratorFont.sans(11.5))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) { actions }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: accent.map { $0.opacity(0.06) },
               border: accent.map { $0.opacity(0.42) })
    }
}

// MARK: - State visuals

struct SkeletonBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var widthFraction: Double
    var delay: Double
    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.panelHi)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, palette.cyan.opacity(0.16), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .offset(x: shimmer ? geo.size.width : -geo.size.width)
                            .mask(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 10)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { shimmer = true }
        }
        .accessibilityHidden(true)
    }
}

struct ScanningPlaceholder: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.void
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
                    .mask {
                        HStack(spacing: 6) {
                            ForEach(0..<24, id: \.self) { _ in
                                Rectangle().frame(width: 6)
                            }
                        }
                    }
                    .padding(.horizontal, geo.size.width * 0.09)
                if !reduceMotion {
                    LinearGradient(colors: [.clear, palette.cyan.opacity(0.14), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.34)
                        .offset(x: sweep ? geo.size.width * 0.5 : -geo.size.width * 0.5)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(palette.hairline, lineWidth: 1) }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { sweep = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview("States · obsidian") {
    ScrollView {
        StatesScreen(model: OrchestratorModel(firstRun: false)).padding(18)
    }
    .frame(width: 1240, height: 900)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}

#Preview("States · light") {
    ScrollView {
        StatesScreen(model: OrchestratorModel(firstRun: false)).padding(18)
    }
    .frame(width: 1240, height: 900)
    .background(OrchestratorPalette.observatory.void)
    .environment(\.colorScheme, .light)
    .orchestratorPalette()
}
