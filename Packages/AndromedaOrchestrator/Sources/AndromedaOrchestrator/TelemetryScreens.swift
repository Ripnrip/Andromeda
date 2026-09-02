import SwiftUI

// MARK: - Usage & telemetry

struct UsageScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel
    @State private var range = 0

    private let ranges = ["today", "this week", "this month", "month to date"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                ScreenHeader(
                    title: "One ledger for every provider",
                    subtitle: "Spend, tokens, and cache ROI metered at the gateway — so the number is the same whichever dialect or provider served the call."
                )
                Picker("Range", selection: $range) {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { index, label in
                        Text(label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .labelsHidden()
            }

            HStack(spacing: 12) {
                MetricTile(label: "spend", value: model.totalSpend, unit: ranges[range],
                           note: "▼ 18% vs prior period", samples: curve(seed: 1), tint: palette.ink)
                    .entrance(0)
                MetricTile(label: "requests", value: "47.3k",
                           note: "1.2k/min sustained", samples: curve(seed: 3), tint: palette.cyan)
                    .entrance(1)
                MetricTile(label: "cache saved", value: model.cacheSavings, unit: "/day",
                           note: "38% of eligible calls", samples: curve(seed: 5), tint: palette.green)
                    .entrance(2)
                MetricTile(label: "budget", value: "78", unit: "% used",
                           note: "$180/day soft cap", samples: curve(seed: 7), tint: palette.amber)
                    .entrance(3)
            }

            HStack(alignment: .top, spacing: 12) {
                spendByAlias.frame(maxWidth: .infinity)
                VStack(spacing: 12) {
                    cacheROI
                    honesty
                }
                .frame(width: 340)
            }
        }
    }

    private var spendByAlias: some View {
        VStack(spacing: 0) {
            HStack {
                Kicker("spend by alias")
                Spacer()
                Text("clients never see which provider filled these")
                    .font(OrchestratorFont.mono(10))
                    .foregroundStyle(palette.dim)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)

            Divider().overlay(palette.hairline)

            ForEach(Array(model.spend.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text(row.alias)
                            .font(OrchestratorFont.mono(11.5, .semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 130, alignment: .leading)
                        Text("\(row.requests.formatted()) req")
                            .font(OrchestratorFont.mono(10))
                            .foregroundStyle(palette.muted)
                        Spacer()
                        if row.cacheHitRate > 0 {
                            Text("\(Int(row.cacheHitRate * 100))% cached")
                                .font(OrchestratorFont.mono(10))
                                .foregroundStyle(palette.green)
                        }
                        Text(row.spend == 0 ? "free · local" : String(format: "$%.2f", row.spend))
                            .font(OrchestratorFont.mono(11.5, .semibold))
                            .foregroundStyle(row.spend == 0 ? palette.green : palette.ink)
                            .frame(width: 88, alignment: .trailing)
                            .monospacedDigit()
                    }
                    ShareBar(share: row.share, tint: row.spend == 0 ? palette.green : palette.cyan)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .overlay(alignment: .bottom) { Divider().overlay(palette.hairline.opacity(0.6)) }
                .entrance(index, step: 0.05)
            }
        }
        .panel()
    }

    private var cacheROI: some View {
        VStack(alignment: .leading, spacing: 11) {
            Kicker("prompt cache ROI")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.cacheSavings)
                    .font(OrchestratorFont.mono(26, .semibold))
                    .foregroundStyle(palette.green)
                Text("per day").font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
            }
            ShareBar(share: model.cacheHitRate, tint: palette.green)
            ForEach(Array([("breakpoints injected", "automatic"),
                           ("eligible calls", "62%"),
                           ("hit rate", "\(Int(model.cacheHitRate * 100))%")].enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.0).font(OrchestratorFont.sans(11.5)).foregroundStyle(palette.muted)
                    Spacer()
                    Text(row.1).font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.ink)
                }
                .entrance(index, step: 0.06)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: palette.green.opacity(0.06), border: palette.green.opacity(0.3))
    }

    private var honesty: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("◈").font(OrchestratorFont.mono(11, .semibold)).foregroundStyle(palette.cyan)
                Kicker("what this number is")
            }
            Text("Metered at the gateway from real token counts returned by each provider — not estimated from characters. Local models report $0 because they cost nothing, not because the meter failed.")
                .font(OrchestratorFont.sans(11.5))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: palette.cyan.opacity(0.06), border: palette.cyan.opacity(0.3))
    }

    private func curve(seed: Int) -> [Double] {
        (0..<20).map { index in
            let base = sin(Double(index + seed) * 0.42) * 0.35 + 0.62
            return base + Double((index * 5 + seed) % 4) * 0.03
        }
    }
}

// MARK: - v1 Gateway

struct GatewayScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(
                title: "One endpoint, three dialects",
                subtitle: "Point any SDK at the same base URL. The gateway translates request and response shapes both ways, so a completions client can call an Anthropic-native model without knowing.",
                trailing: "listening · 3 of 3 healthy"
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("base url")
                    Text("https://gw.andromeda.local/v1")
                        .font(OrchestratorFont.mono(16, .semibold))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusBadge(.healthy, text: "LISTENING")
                Button("COPY") {}.buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }
            .padding(16)
            .panel(radius: 12, fill: palette.cyan.opacity(0.08), border: palette.cyan.opacity(0.45))

            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(Dialect.allCases.enumerated()), id: \.element) { index, dialect in
                    endpointCard(dialect, share: [0.54, 0.27, 0.19][index], index: index)
                        .entrance(index, step: 0.09)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                translationPath.frame(maxWidth: .infinity)
                proxyBehaviour.frame(width: 340)
            }
        }
    }

    private func endpointCard(_ dialect: Dialect, share: Double, index: Int) -> some View {
        let tint: Color = index == 0 ? palette.cyan : index == 1 ? palette.green : palette.muted
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dialect.path)
                    .font(OrchestratorFont.mono(12, .semibold))
                    .foregroundStyle(tint)
                Spacer()
                StatusBadge(.healthy, bordered: false)
            }
            Text(dialect.note)
                .font(OrchestratorFont.sans(11.5))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(palette.hairline)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Kicker("share of traffic")
                    Spacer()
                    Text("\(Int(share * 100))%")
                        .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.ink)
                }
                ShareBar(share: share, tint: tint)
            }
            Text(dialect.clients)
                .font(OrchestratorFont.mono(10))
                .foregroundStyle(palette.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var translationPath: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("what happens in the 3ms")
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 11) {
                    Text("\(index + 1)")
                        .font(OrchestratorFont.mono(9.5, .semibold))
                        .foregroundStyle(palette.cyan)
                        .frame(width: 18, height: 18)
                        .background(palette.cyan.opacity(0.12), in: .rect(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.0).font(OrchestratorFont.mono(11, .semibold)).foregroundStyle(palette.ink)
                        Text(step.1).font(OrchestratorFont.sans(11)).foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Text(step.2).font(OrchestratorFont.mono(10)).foregroundStyle(palette.dim)
                }
                .entrance(index, step: 0.05)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var steps: [(String, String, String)] {
        [
            ("parse", "Detect dialect from the path — no client config needed.", "0.2ms"),
            ("resolve alias", "sonnet-latest → the current target and its fallback ladder.", "0.1ms"),
            ("inject secret", "Broker attaches the key. It never enters the agent environment.", "0.4ms"),
            ("cache breakpoints", "System and tool blocks marked automatically.", "0.9ms"),
            ("translate", "Request shape rewritten for the target's native API.", "1.1ms"),
            ("meter", "Real token counts recorded against the alias, once.", "0.3ms"),
        ]
    }

    private var proxyBehaviour: some View {
        VStack(alignment: .leading, spacing: 11) {
            Kicker("proxy behaviour")
            ForEach(Array([("Retries", "3 attempts, jittered backoff"),
                           ("Failover", "cross-vendor, shape-translated"),
                           ("Breaker", "opens at 5% 5xx over 30s"),
                           ("Shedding", "budget cap → haiku-fast"),
                           ("Offline", "local lane, queued replay")].enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0).font(OrchestratorFont.sans(11.5, .semibold)).foregroundStyle(palette.ink)
                    Spacer()
                    Text(row.1)
                        .font(OrchestratorFont.mono(10))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.trailing)
                }
                .entrance(index, step: 0.05)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

#Preview("Usage") {
    UsageScreen(model: OrchestratorModel(firstRun: false))
        .padding(18)
        .frame(width: 1240, height: 800)
        .background(OrchestratorPalette.obsidian.void)
        .orchestratorPalette()
}

#Preview("Gateway · light") {
    GatewayScreen(model: OrchestratorModel(firstRun: false))
        .padding(18)
        .frame(width: 1240, height: 860)
        .background(OrchestratorPalette.observatory.void)
        .environment(\.colorScheme, .light)
        .orchestratorPalette()
}
