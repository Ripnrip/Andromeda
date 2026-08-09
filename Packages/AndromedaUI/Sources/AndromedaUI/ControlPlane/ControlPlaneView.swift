import SwiftUI

// MARK: - Control Plane shell
// The full macOS control-plane window: title bar, capability sidebar, and a
// routed content area. Theme-aware (dark void / light observatory).

public struct ControlPlaneView: View {
    @State private var selection: Pillar
    public init(initial: Pillar = .memory) { _selection = State(initialValue: initial) }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Color.andromedaTeal.opacity(0.14))
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Color.andromedaTeal.opacity(0.14))
                content
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
        .background(AndromedaSurface().ignoresSafeArea())
    }

    // Title bar
    private var titleBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { c in
                    Circle().fill(c).frame(width: 12, height: 12)
                }
            }
            AndromedaCore(size: 24).padding(.leading, 4)
            Text("Andromeda").font(AndromedaFont.ui(13.5, .semibold)).foregroundStyle(Color.andromedaInk)
            Text("Control Plane").font(AndromedaFont.ui(13)).foregroundStyle(Color.andromedaMuted)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Color.andromedaLive).frame(width: 6, height: 6).shadow(color: .andromedaLive, radius: 4)
                Text("3 nodes healthy").font(AndromedaFont.mono(11)).foregroundStyle(Color.andromedaLive)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.andromedaLive.opacity(0.12)))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    // Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow("Capabilities").padding(.horizontal, 10).padding(.bottom, 6)
            ForEach(Pillar.allCases) { p in navRow(p) }
            Spacer()
            Text("Clients call stable IDs. Andromeda resolves providers, secrets & routing server-side.")
                .font(AndromedaFont.ui(10.5)).foregroundStyle(Color.andromedaMuted)
                .padding(10)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.andromedaTeal.opacity(0.14)), alignment: .top)
        }
        .padding(.horizontal, 10).padding(.vertical, 14)
        .frame(width: 216)
    }

    private func navRow(_ p: Pillar) -> some View {
        let active = selection == p
        return Button { selection = p } label: {
            HStack(spacing: 11) {
                Image(systemName: p.symbol).font(.system(size: 15))
                    .foregroundStyle(active ? Color.andromedaGlow : Color.andromedaMuted).frame(width: 19)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title).font(AndromedaFont.ui(13, .medium)).foregroundStyle(active ? Color.andromedaInk : Color.andromedaMuted)
                    Text(p.capabilityID).font(AndromedaFont.mono(9.5)).foregroundStyle(Color.andromedaMuted)
                }
                Spacer(minLength: 0)
                Circle().fill(p.status.color).frame(width: 6, height: 6).shadow(color: p.status.color, radius: 4)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(active ? Color.andromedaTeal.opacity(0.12) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(active ? Color.andromedaTeal.opacity(0.35) : .clear)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p.title), \(p.status.dot)")
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    // Content
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(selection.title.components(separatedBy: " ·").first ?? selection.title).cpDisplay().foregroundStyle(Color.andromedaInk)
                        StatusBadge(selection.status)
                    }
                    Text(selection.blurb).font(AndromedaFont.ui(13.5)).foregroundStyle(Color.andromedaMuted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
                }
                Spacer()
                Text(selection.capabilityID).font(AndromedaFont.mono(11)).foregroundStyle(Color.andromedaMuted)
            }
            .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 16)
            Divider().overlay(Color.andromedaTeal.opacity(0.14))
            ScrollView {
                section.padding(26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var section: some View {
        switch selection {
        case .memory: MemorySection()
        case .models: ModelsSection()
        case .search: SearchSection()
        case .settings: SettingsSection()
        case .mcp, .skills, .secrets, .fleet: CapabilityListSection(pillar: selection)
        }
    }
}

#Preview("Control Plane · dark")  { ControlPlaneView().frame(width: 1120, height: 780).preferredColorScheme(ColorScheme.dark) }
#Preview("Control Plane · light") { ControlPlaneView().frame(width: 1120, height: 780).preferredColorScheme(ColorScheme.light) }
