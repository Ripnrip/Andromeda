import SwiftUI

// MARK: - Memory section

public struct MemorySection: View {
    public init() {}
    @State private var scope = "total"
    @State private var layer = "swiftdata"

    private let scopes: [(String, String, String, String)] = [
        ("total", "Total", "151", "memories"),
        ("agent", "Per-agent", "38", "avg / agent"),
        ("cli", "CLI", "27", "cli-scoped"),
        ("ide", "IDE", "19", "ide-scoped"),
    ]
    private var cur: (String, String, String, String) { scopes.first { $0.0 == scope } ?? scopes[0] }
    private var sel: MemLayer { ControlPlaneData.layers.first { $0.key == layer } ?? ControlPlaneData.layers[0] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                ForEach(scopes, id: \.0) { s in SegTab(label: s.1, active: scope == s.0) { scope = s.0 } }
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    salience
                    layers
                }
                .frame(maxWidth: .infinity)
                changes.frame(width: 320)
            }
            MemoryKindsGrid()
        }
    }

    private var salience: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    (Text(cur.2).font(AndromedaFont.ui(14, .medium)) + Text("  \(cur.3)").font(AndromedaFont.mono(12)))
                        .foregroundStyle(Color.andromedaInk)
                    Spacer()
                    Text("salience map").font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
                }
                clusterMap
                Divider().overlay(Color.andromedaTeal.opacity(0.14))
                HStack(spacing: 16) {
                    legend("core", Color(red: 0.42, green: 0.45, blue: 1))
                    legend("reference", .andromedaMuted)
                    legend("skills", .andromedaAmber)
                }
            }
        }
    }

    private var clusterMap: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 18) {
                clusterNode("persona", Color(red: 0.42, green: 0.45, blue: 1))
                clusterNode("ecosystem", Color(red: 0.42, green: 0.45, blue: 1))
                clusterNode("human", Color(red: 0.42, green: 0.45, blue: 1))
            }
            VStack(alignment: .leading, spacing: 12) {
                clusterBox("SKILLS · 28", count: 14, color: .andromedaAmber)
                clusterBox("REFERENCE · 19", count: 9, color: .andromedaMuted)
            }
            VStack(spacing: 18) {
                clusterNode("anti-patterns", .andromedaTeal)
                clusterNode("onboarding", .andromedaLive)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .center)
    }

    private func clusterNode(_ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(color).frame(width: 14, height: 14).shadow(color: color, radius: 6)
            Text(label).font(AndromedaFont.mono(9.5)).foregroundStyle(Color.andromedaMuted)
        }
    }

    private func clusterBox(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AndromedaFont.mono(9)).tracking(1.4).foregroundStyle(Color.andromedaMuted)
            let cols = [GridItem(.adaptive(minimum: 12), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle().fill(color.opacity(0.85)).frame(width: 9, height: 9)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.14))))
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(t).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted) }
    }

    private var layers: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Storage layers").font(AndromedaFont.ui(13, .medium)).foregroundStyle(Color.andromedaInk)
                    Spacer()
                    Text("explore the stack behind memory.recall").font(AndromedaFont.ui(11)).foregroundStyle(Color.andromedaMuted)
                }
                FlowRow(spacing: 7) {
                    ForEach(ControlPlaneData.layers) { l in
                        Button { layer = l.key } label: {
                            HStack(spacing: 7) {
                                Text(l.name).font(AndromedaFont.ui(12, .medium)).foregroundStyle(layer == l.key ? Color.andromedaInk : Color.andromedaMuted)
                                Text(l.count).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(layer == l.key ? Color.andromedaTeal.opacity(0.14) : .clear)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(layer == l.key ? Color.andromedaTeal.opacity(0.35) : Color.andromedaTeal.opacity(0.14))))
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(layer == l.key ? [.isSelected, .isButton] : .isButton)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(sel.name).font(AndromedaFont.ui(15, .medium)).foregroundStyle(Color.andromedaInk)
                        Text(sel.kind).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaTeal)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.andromedaTeal.opacity(0.12)))
                        Spacer()
                        Text(sel.count).font(AndromedaFont.mono(13, .medium)).foregroundStyle(Color.andromedaGlow)
                    }
                    Text(sel.path).font(AndromedaFont.mono(11)).foregroundStyle(Color.andromedaMuted)
                    Text(sel.detail).font(AndromedaFont.ui(12.5)).foregroundStyle(Color.andromedaMuted).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.andromedaTeal.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.andromedaTeal.opacity(0.14))))
            }
        }
    }

    private var changes: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent memory changes").font(AndromedaFont.ui(13, .medium)).foregroundStyle(Color.andromedaInk)
                    Spacer()
                    Text("182 in 6 mo").font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
                }
                heatmap
                ForEach(ControlPlaneData.changes) { m in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(m.dreaming ? Color.andromedaLive : Color.andromedaMuted).frame(width: 7, height: 7)
                            .shadow(color: m.dreaming ? .andromedaLive : .clear, radius: 4).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(m.author).font(AndromedaFont.mono(11, .medium)).foregroundStyle(m.dreaming ? Color.andromedaLive : Color.andromedaMuted)
                                Spacer()
                                Text(m.time).font(AndromedaFont.mono(10)).foregroundStyle(Color.andromedaMuted)
                            }
                            Text(m.text).font(AndromedaFont.ui(12)).foregroundStyle(Color.andromedaInk).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(m.author), \(m.time): \(m.text)")
                }
            }
        }
    }

    private var heatmap: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 26)
        return LazyVGrid(columns: cols, spacing: 3) {
            ForEach(0..<182, id: \.self) { i in
                let o = [0.08, 0.24, 0.5, 0.85][(i * 7 + i / 5) % 4]
                RoundedRectangle(cornerRadius: 2).fill(Color.andromedaTeal.opacity(o)).aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityLabel("Contribution heatmap, 182 changes in six months")
    }
}

/// Minimal wrapping HStack for chips.
struct FlowRow<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content
    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) { self.spacing = spacing; self.content = content() }
    var body: some View {
        // simple two-line wrap via fixed layout fallback
        HStack(spacing: spacing) { content }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
