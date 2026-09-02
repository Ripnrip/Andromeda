import SwiftUI

// MARK: - Controls

public struct ConsoleButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, ghost, quiet, danger }

    @Environment(\.palette) private var palette
    public var kind: Kind

    public init(kind: Kind = .ghost) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        let accent: Color = switch kind {
        case .primary, .ghost: palette.cyan
        case .quiet: palette.hairline
        case .danger: palette.red
        }
        let fill: Color = switch kind {
        case .primary: palette.cyan.opacity(0.14)
        case .danger: palette.red.opacity(0.12)
        case .ghost: palette.panel
        case .quiet: .clear
        }
        let label: Color = kind == .quiet ? palette.muted : palette.ink

        return configuration.label
            .font(OrchestratorFont.mono(10, .semibold))
            .tracking(0.9)
            .foregroundStyle(label)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(fill.opacity(configuration.isPressed ? 1.8 : 1), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accent.opacity(kind == .quiet ? 1 : 0.5), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(OrchestratorMotion.settle, value: configuration.isPressed)
    }
}

/// Sidebar row. A real `Button` so VoiceOver and keyboard both work.
public struct NavRow: View {
    @Environment(\.palette) private var palette
    public var screen: OrchestratorModel.Screen
    public var badge: String?
    public var isSelected: Bool
    public var action: () -> Void

    public init(screen: OrchestratorModel.Screen, badge: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.screen = screen
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(screen.glyph)
                    .font(OrchestratorFont.mono(11, .semibold))
                    .foregroundStyle(isSelected ? palette.cyan : palette.dim)
                Text(screen.title)
                    .font(OrchestratorFont.sans(12.5, isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.ink : palette.muted)
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(OrchestratorFont.mono(9.5))
                        .foregroundStyle(palette.dim)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(isSelected ? palette.cyan.opacity(0.1) : .clear, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? palette.cyan.opacity(0.4) : .clear, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A labelled number with an optional sparkline — the console's KPI unit.
public struct MetricTile: View {
    @Environment(\.palette) private var palette
    public var label: String
    public var value: String
    public var unit: String?
    public var note: String?
    public var samples: [Double]
    public var tint: Color?

    public init(label: String, value: String, unit: String? = nil, note: String? = nil,
                samples: [Double] = [], tint: Color? = nil)
    {
        self.label = label
        self.value = value
        self.unit = unit
        self.note = note
        self.samples = samples
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(OrchestratorFont.mono(21, .semibold))
                    .foregroundStyle(tint ?? palette.ink)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(OrchestratorFont.mono(10)).foregroundStyle(palette.dim)
                }
            }
            if !samples.isEmpty {
                Sparkline(samples: samples, tint: tint ?? palette.cyan)
                    .frame(height: 22)
            }
            if let note {
                Text(note).font(OrchestratorFont.mono(10)).foregroundStyle(palette.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

public struct Sparkline: View {
    public var samples: [Double]
    public var tint: Color

    public init(samples: [Double], tint: Color) {
        self.samples = samples
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            let maxValue = max(samples.max() ?? 1, 0.0001)
            let step = samples.count > 1 ? geo.size.width / CGFloat(samples.count - 1) : 0
            let points = samples.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step,
                        y: geo.size.height * (1 - CGFloat(value / maxValue)))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.22), .clear],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// Horizontal share bar used for traffic split and spend.
public struct ShareBar: View {
    @Environment(\.palette) private var palette
    public var share: Double
    public var tint: Color

    public init(share: Double, tint: Color) {
        self.share = share
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.panelHi)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * share))
            }
        }
        .frame(height: 6)
        .animation(OrchestratorMotion.settle, value: share)
        .accessibilityHidden(true)
    }
}

// MARK: - Canvas parity for every control

//
// One preview per control kind — the Xcode canvas grid shows the whole
// vocabulary at a glance; each has a snapshot twin in the parity suite.

#Preview("Buttons · all kinds") {
    VStack(alignment: .leading, spacing: 12) {
        Button("PRIMARY") {}
            .buttonStyle(ConsoleButtonStyle(kind: .primary))
        Button("DANGER") {}
            .buttonStyle(ConsoleButtonStyle(kind: .danger))
        Button("GHOST") {}
            .buttonStyle(ConsoleButtonStyle(kind: .ghost))
        Button("QUIET") {}
            .buttonStyle(ConsoleButtonStyle(kind: .quiet))
    }
    .padding(24)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}

#Preview("NavRow · plain + selected") {
    VStack(alignment: .leading, spacing: 8) {
        NavRow(screen: .usage, badge: nil, isSelected: false) {}
        NavRow(screen: .usage, badge: "3", isSelected: true) {}
    }
    .frame(width: 280)
    .padding(24)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}

#Preview("MetricTile · both") {
    HStack(spacing: 14) {
        MetricTile(label: "req/min", value: "1,240", samples: CatalogueSamples.wave)
        MetricTile(label: "tokens/s", value: "18.4", unit: "tok", note: "p95 across aliases", samples: CatalogueSamples.climb)
    }
    .padding(24)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}

#Preview("Sparkline + ShareBar") {
    VStack(alignment: .leading, spacing: 14) {
        Sparkline(samples: CatalogueSamples.wave, tint: .cyan)
            .frame(width: 220)
        ShareBar(share: 0.62, tint: .cyan)
            .frame(width: 220)
    }
    .padding(24)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}

#Preview("Kicker + TypedText") {
    VStack(alignment: .leading, spacing: 8) {
        Kicker("v1 gateway")
        TypedText("one base URL for every client", font: OrchestratorFont.editorial(18))
    }
    .frame(width: 300, alignment: .leading)
    .padding(24)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}
