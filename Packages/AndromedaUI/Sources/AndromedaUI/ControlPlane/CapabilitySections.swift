import SwiftUI

// MARK: - Capability list section (MCP / Skills / Secrets / Fleet)

public struct CapabilityListSection: View {
    public var pillar: Pillar
    public var onAdd: (() -> Void)?
    public init(pillar: Pillar, onAdd: (() -> Void)? = nil) { self.pillar = pillar; self.onAdd = onAdd }

    private var addLabel: String? {
        switch pillar {
        case .mcp: return "Mount server"
        case .skills: return "Register skill"
        case .secrets: return "Seal secret"
        default: return nil
        }
    }
    private let cols = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let addLabel {
                HStack { Spacer(); AddButton(label: addLabel) { onAdd?() } }
            }
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(ControlPlaneData.items(for: pillar)) { it in card(it) }
            }
        }
    }

    private func card(_ it: CapabilityItem) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: pillar.symbol).font(.system(size: 16))
                        .foregroundStyle(Color.andromedaTeal)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.andromedaTeal.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.name).font(AndromedaFont.ui(14, .medium)).foregroundStyle(Color.andromedaInk)
                        Text(it.ref).font(AndromedaFont.mono(10.5)).foregroundStyle(Color.andromedaMuted)
                    }
                    Spacer(minLength: 0)
                    DotStatus(text: it.status, color: it.statusColor)
                }
                Text(it.desc).font(AndromedaFont.ui(12.5)).foregroundStyle(Color.andromedaMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Color.andromedaTeal.opacity(0.14))
                HStack(spacing: 16) {
                    ForEach(it.metrics, id: \.0) { m in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.0).font(AndromedaFont.mono(14, .medium)).foregroundStyle(Color.andromedaInk)
                            Text(m.1).font(AndromedaFont.mono(9.5)).foregroundStyle(Color.andromedaMuted)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(it.name), \(it.status). \(it.desc)")
    }
}

// MARK: - Models section (infer.write capability lanes)

public struct ModelsSection: View {
    public var onAdd: (() -> Void)?
    public init(onAdd: (() -> Void)? = nil) { self.onAdd = onAdd }
    @State private var tab = "models"
    @State private var query = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CAVEAT · infer.write is an episodic-store alias today — not LLM generation. Lanes below are stable capability IDs only.")
                .font(AndromedaFont.mono(11))
                .foregroundStyle(Color.andromedaAmber)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(["models", "speed", "health"], id: \.self) { t in
                    SegTab(label: t.capitalized, active: tab == t) { tab = t }
                }
            }
            switch tab {
            case "speed": speed
            case "health": health
            default: models
            }
        }
    }

    private var filtered: [ModelRow] {
        query.isEmpty ? ControlPlaneData.models
            : ControlPlaneData.models.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Color.andromedaMuted)
                    TextField("Search capability lanes…", text: $query).textFieldStyle(.plain)
                        .font(AndromedaFont.ui(13)).foregroundStyle(Color.andromedaInk)
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.andromedaTeal.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.andromedaTeal.opacity(0.14))))
                Text("\(filtered.count) lanes").font(AndromedaFont.mono(12)).foregroundStyle(Color.andromedaMuted)
                AddButton(label: "Add route") { onAdd?() }
            }
            .padding(.bottom, 8)
            ForEach(filtered) { m in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(AndromedaFont.mono(14, .medium)).foregroundStyle(Color.andromedaInk)
                        Text("stable capability · curtain resolves routing").font(AndromedaFont.ui(11)).foregroundStyle(Color.andromedaMuted)
                    }
                    Spacer()
                    DotStatus(text: m.tier, color: m.tierColor)
                    pill("Copy", filled: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.14))))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(m.name), \(m.tier)")
            }
        }
    }

    private func pill(_ t: String, filled: Bool) -> some View {
        Text(t).font(filled ? AndromedaFont.ui(11, .medium) : AndromedaFont.mono(11))
            .foregroundStyle(filled ? Color.andromedaInk : Color.andromedaMuted)
            .padding(.horizontal, 13).padding(.vertical, 5)
            .background(Capsule().fill(filled ? Color.andromedaTeal.opacity(0.35) : .clear)
                .overlay(filled ? nil : Capsule().stroke(Color.andromedaTeal.opacity(0.14))))
    }

    private var speed: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("No live latency board — LLM proxy not shipped. Showing capability lanes only.")
                .font(AndromedaFont.mono(11))
                .foregroundStyle(Color.andromedaAmber)
                .padding(.bottom, 6)
            ForEach(ControlPlaneData.speed) { s in
                HStack(spacing: 14) {
                    Text(s.rank).font(AndromedaFont.mono(13, .medium)).foregroundStyle(Color.andromedaMuted).frame(width: 18)
                    Text(s.name).font(AndromedaFont.mono(14, .medium)).foregroundStyle(Color.andromedaInk)
                    Spacer()
                    Text(s.latency).font(AndromedaFont.mono(13)).foregroundStyle(Color.andromedaDim).frame(width: 80, alignment: .trailing)
                    Text(s.tps).font(AndromedaFont.mono(13)).foregroundStyle(Color.andromedaDim).frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.14))))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("rank \(s.rank), \(s.name), \(s.latency), \(s.tps)")
            }
        }
    }

    private var health: some View {
        let cards: [(String, String, Color, String)] = [
            ("infer.write", "spec", .andromedaDim, "episodic-store alias — not LLM generation"),
            ("proxy routing", "unbuilt", .andromedaAmber, "provider selection stays behind the curtain"),
            ("client catalog", "IDs only", .andromedaTeal, "no provider model brands on this surface"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
            ForEach(cards, id: \.0) { c in
                GlassCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(c.0).font(AndromedaFont.mono(11)).foregroundStyle(Color.andromedaMuted)
                        Text(c.1).font(AndromedaFont.serif(30)).foregroundStyle(c.2)
                        Text(c.3).font(AndromedaFont.ui(11)).foregroundStyle(Color.andromedaMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
