import SwiftUI

// MARK: - Screen header

struct ScreenHeader: View {
    @Environment(\.palette) private var palette
    var title: String
    var subtitle: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(OrchestratorFont.editorial(21))
                    .italic()
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(OrchestratorFont.sans(12))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let trailing {
                Kicker(trailing)
            }
        }
    }
}

// MARK: - Overview

struct OverviewScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(
                title: "Everything through one door",
                subtitle: "Live traffic across every provider and MCP server, translated into three dialects and metered once.",
                trailing: "simulated live"
            )

            HStack(spacing: 12) {
                MetricTile(label: "requests", value: "\(Int(model.requestsPerMinute))", unit: "/min",
                           note: "+12% vs 1h", samples: sparkSamples(seed: 0), tint: palette.cyan)
                    .entrance(0)
                MetricTile(label: "tokens", value: String(format: "%.1fk", model.tokensPerSecond), unit: "/s",
                           note: "in 78% · out 22%", samples: sparkSamples(seed: 2))
                    .entrance(1)
                MetricTile(label: "cache hit", value: "\(Int(model.cacheHitRate * 100))", unit: "%",
                           note: "\(model.cacheSavings)/day", samples: sparkSamples(seed: 4), tint: palette.green)
                    .entrance(2)
                MetricTile(label: "mcp tools", value: "63", unit: "exposed",
                           note: "\(model.healthyServerCount) of \(model.mcpServers.count) hosts healthy",
                           samples: sparkSamples(seed: 6))
                    .entrance(3)
                MetricTile(label: "spend", value: model.totalSpend, unit: "today",
                           note: "budget $180 · 78% used", samples: sparkSamples(seed: 8), tint: palette.amber)
                    .entrance(4)
            }

            HStack(alignment: .top, spacing: 12) {
                requestStream
                    .frame(maxWidth: .infinity)
                dialectSplit
                    .frame(width: 320)
            }
        }
    }

    private var requestStream: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker("live request stream")
                Spacer()
                Button(model.isStreaming ? "PAUSE" : "RESUME") { model.isStreaming.toggle() }
                    .buttonStyle(ConsoleButtonStyle(kind: .quiet))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)

            Divider().overlay(palette.hairline)

            LazyVStack(spacing: 0) {
                ForEach(model.requests.prefix(12)) { request in
                    HStack(spacing: 12) {
                        Text(request.dialect.rawValue)
                            .font(OrchestratorFont.mono(10, .semibold))
                            .foregroundStyle(tint(for: request.dialect))
                            .frame(width: 84, alignment: .leading)
                        Text(request.alias)
                            .font(OrchestratorFont.mono(11))
                            .foregroundStyle(palette.ink)
                            .frame(width: 110, alignment: .leading)
                        Text(request.route)
                            .font(OrchestratorFont.mono(10.5))
                            .foregroundStyle(request.failedOver ? palette.amber : palette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if request.cached {
                            Text("CACHED")
                                .font(OrchestratorFont.kicker(8.5))
                                .foregroundStyle(palette.green)
                        }
                        Text("\(request.tokens) tok")
                            .font(OrchestratorFont.mono(10))
                            .foregroundStyle(palette.dim)
                            .frame(width: 74, alignment: .trailing)
                        Text("\(request.latencyMS)ms")
                            .font(OrchestratorFont.mono(10.5))
                            .foregroundStyle(palette.muted)
                            .frame(width: 58, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Divider().overlay(palette.hairline.opacity(0.6)) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(OrchestratorMotion.settle, value: model.requests.first?.id)
        }
        .panel()
    }

    private var dialectSplit: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Kicker("dialect split")
                Text("one endpoint, three shapes")
                    .font(OrchestratorFont.mono(10))
                    .foregroundStyle(palette.muted)
            }
            ForEach(Array(Dialect.allCases.enumerated()), id: \.element) { index, dialect in
                let share = [0.54, 0.27, 0.19][index]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dialect.path)
                            .font(OrchestratorFont.mono(11, .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text("\(Int(share * 100))%")
                            .font(OrchestratorFont.mono(10.5))
                            .foregroundStyle(palette.muted)
                    }
                    ShareBar(share: share, tint: tint(for: dialect))
                }
                .entrance(index, step: 0.08)
            }

            Divider().overlay(palette.hairline)

            VStack(alignment: .leading, spacing: 7) {
                Kicker("translation")
                Text("Shapes convert both ways at the edge. A completions client can call an Anthropic-native model and never know.")
                    .font(OrchestratorFont.sans(11.5))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .panel()
    }

    private func tint(for dialect: Dialect) -> Color {
        switch dialect {
        case .messages:    palette.cyan
        case .responses:   palette.green
        case .completions: palette.muted
        }
    }

    private func sparkSamples(seed: Int) -> [Double] {
        (0..<18).map { index in
            let base = sin(Double(index + seed) * 0.55) * 0.4 + 0.6
            return base + Double((index * 7 + seed) % 5) * 0.04
        }
    }
}

// MARK: - Registry

struct RegistryScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(
                title: "Nine servers, one supervised host",
                subtitle: "Every client reads this registry. Duplicates were removed at import; withheld tools never appear in a client's tool list at all.",
                trailing: "\(model.mcpServers.count) servers · 63 tools · 1 config"
            )

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Kicker("server").frame(width: 200, alignment: .leading)
                    Kicker("transport").frame(width: 78, alignment: .leading)
                    Kicker("tools").frame(width: 66, alignment: .leading)
                    Kicker("calls").frame(width: 62, alignment: .leading)
                    Kicker("p95").frame(width: 62, alignment: .leading)
                    Kicker("scopes").frame(maxWidth: .infinity, alignment: .leading)
                    Kicker("health").frame(width: 96, alignment: .leading)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)

                Divider().overlay(palette.hairline)

                ForEach(Array(model.mcpServers.enumerated()), id: \.element.id) { index, server in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.name)
                                .font(OrchestratorFont.mono(11.5, .semibold))
                                .foregroundStyle(palette.ink)
                            Text(server.origin)
                                .font(OrchestratorFont.mono(9.5))
                                .foregroundStyle(palette.dim)
                                .lineLimit(1)
                        }
                        .frame(width: 200, alignment: .leading)

                        Text(server.transport)
                            .font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                            .frame(width: 78, alignment: .leading)
                        Text("\(server.exposedTools)/\(server.tools)")
                            .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.ink)
                            .frame(width: 66, alignment: .leading)
                        Text("\(server.calls)")
                            .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
                            .frame(width: 62, alignment: .leading)
                        Text(server.p95)
                            .font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
                            .frame(width: 62, alignment: .leading)
                        Text(server.scopes)
                            .font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatusBadge(server.status)
                            .frame(width: 96, alignment: .leading)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Divider().overlay(palette.hairline.opacity(0.6)) }
                    .entrance(index, step: 0.035)
                }
            }
            .panel()

            HStack(spacing: 12) {
                reclaimedCard
                Button("＋  ADD AN MCP SERVER") { model.open(.addMCPServer) }
                    .buttonStyle(ConsoleButtonStyle(kind: .primary))
            }
        }
    }

    private var reclaimedCard: some View {
        HStack(spacing: 18) {
            ForEach(Array([("configs collapsed", "4 → 1"), ("duplicate servers", "3 removed"),
                           ("zombie processes", "6 → 0"), ("secrets deduped", "7 → 1")].enumerated()), id: \.offset) { index, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Kicker(fact.0)
                    Text(fact.1)
                        .font(OrchestratorFont.mono(13, .semibold))
                        .foregroundStyle(palette.green)
                }
                .entrance(index, step: 0.06)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: palette.green.opacity(0.06), border: palette.green.opacity(0.32))
    }
}

// MARK: - Providers

struct ProvidersScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var model: OrchestratorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(
                title: "Providers behind the curtain",
                subtitle: "Operators see brands and breakers here. Clients only ever see the alias — that separation is the product.",
                trailing: "\(model.providers.count) providers · \(model.aliases.count) aliases"
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(Array(model.providers.enumerated()), id: \.element.id) { index, provider in
                        providerCard(provider)
                            .entrance(index, step: 0.07)
                    }
                }
                .frame(width: 380)

                aliasTable
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func providerCard(_ provider: Provider) -> some View {
        let status = provider.breaker.status
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name)
                        .font(OrchestratorFont.sans(12.5, .semibold))
                        .foregroundStyle(palette.ink)
                    Text(provider.endpoint)
                        .font(OrchestratorFont.mono(9.5))
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(status, text: provider.breaker.rawValue)
            }

            HStack(spacing: 16) {
                stat("p95", provider.p95)
                stat("errors", provider.errorRate, tint: status == .degraded ? palette.amber : nil)
                stat("models", "\(provider.models)")
                stat("spend", provider.spend)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Kicker("traffic share")
                    Spacer()
                    Text("\(Int(provider.trafficShare * 100))%")
                        .font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                }
                ShareBar(share: provider.trafficShare, tint: status.tint(palette))
            }

            if provider.breaker == .halfOpen {
                Text("Traffic already moved to bedrock. Callers saw no error — only 96ms more latency.")
                    .font(OrchestratorFont.sans(11))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .panel(border: status == .healthy ? nil : status.tint(palette).opacity(0.42))
    }

    private func stat(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Kicker(label)
            Text(value)
                .font(OrchestratorFont.mono(11.5, .semibold))
                .foregroundStyle(tint ?? palette.ink)
        }
    }

    private var aliasTable: some View {
        VStack(spacing: 0) {
            HStack {
                Kicker("aliases clients can call")
                Spacer()
                Button("＋  ADD A MODEL") { model.open(.addModel) }
                    .buttonStyle(ConsoleButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)

            Divider().overlay(palette.hairline)

            ForEach(Array(model.aliases.enumerated()), id: \.element.id) { index, alias in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(alias.alias)
                            .font(OrchestratorFont.mono(12, .semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 130, alignment: .leading)
                        Text("→")
                            .font(OrchestratorFont.mono(10)).foregroundStyle(palette.dim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alias.target)
                                .font(OrchestratorFont.mono(11)).foregroundStyle(palette.muted)
                            Text(alias.provider)
                                .font(OrchestratorFont.mono(9.5)).foregroundStyle(palette.dim)
                        }
                        Spacer()
                        Text(alias.context).font(OrchestratorFont.mono(10)).foregroundStyle(palette.dim)
                        Text(alias.price).font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
                        Text(alias.p95).font(OrchestratorFont.mono(10.5)).foregroundStyle(palette.muted)
                            .frame(width: 56, alignment: .trailing)
                        StatusBadge(alias.status, bordered: false)
                    }
                    HStack(spacing: 6) {
                        ForEach(alias.capabilities, id: \.self) { capability in
                            Text(capability)
                                .font(OrchestratorFont.mono(9.5))
                                .foregroundStyle(palette.cyan)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(palette.cyan.opacity(0.1), in: .rect(cornerRadius: 5))
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Divider().overlay(palette.hairline.opacity(0.6)) }
                .entrance(index, step: 0.05)
            }
        }
        .panel()
    }
}
