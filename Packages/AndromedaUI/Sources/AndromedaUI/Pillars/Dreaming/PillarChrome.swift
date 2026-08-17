import SwiftUI

// MARK: - Shared chrome
// Every pillar card is the same four parts: header (icon · title · badge),
// a live stage, the state chips, and the note rail that explains the state.

/// Pill that names the current state in the HUD's own voice.
public struct DreamPillarBadge: View {
    public var text: String
    public var accent: Color
    public init(_ text: String, accent: Color) { self.text = text; self.accent = accent }

    public var body: some View {
        Text(text.uppercased())
            .font(AndromedaFont.mono(8.5))
            .tracking(1)
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent.opacity(0.30)))
            .fixedSize()
            .jello(on: text)
            .animation(.easeInOut(duration: 0.45), value: text)
    }
}

/// The single scrolling line of machine truth at the top of a stage.
public struct PillarLog: View {
    public var text: String
    public var tint: Color
    /// Types itself in, Typewriter-style — used where the line is a live feed.
    public var typing: Bool

    public init(_ text: String, tint: Color, typing: Bool = false) {
        self.text = text; self.tint = tint; self.typing = typing
    }

    public var body: some View {
        if typing {
            TypingLog(text, tint: tint)
                .id(text)
        } else {
            plain
        }
    }

    private var plain: some View {
        Text(text)
            .font(AndromedaFont.mono(9))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.5), value: text)
    }
}

/// Selectable states. Tapping pins a pillar; the driver stops cycling it.
public struct DreamPillarChipRow<S: PillarState>: View {
    @Binding public var selection: S
    public var onPick: (() -> Void)?

    public init(selection: Binding<S>, onPick: (() -> Void)? = nil) {
        self._selection = selection; self.onPick = onPick
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(S.allCases)) { state in
                let on = state == selection
                Button {
                    selection = state
                    onPick?()
                } label: {
                    Text(state.label)
                        .font(AndromedaFont.mono(9.5))
                        .foregroundStyle(on ? Color.andromedaInk : Color.andromedaMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(on ? state.accent.opacity(0.15) : Color.andromedaTeal.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(on ? state.accent.opacity(0.5) : Color.andromedaTeal.opacity(0.10))
                        )
                        .offset(y: on ? -1 : 0)
                }
                .buttonStyle(.plain)
                .keyframePop(on: on)
                .accessibilityLabel(state.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .animation(Motion.spring(0.35, 0.35), value: selection)
    }
}

/// The sentence under a card. Reserves height so cards do not jump as
/// states cycle.
public struct PillarNote: View {
    public var text: String
    public var accent: Color
    public var minHeight: CGFloat

    public init(_ text: String, accent: Color, minHeight: CGFloat = 56) {
        self.text = text; self.accent = accent; self.minHeight = minHeight
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Capsule().fill(accent.opacity(0.35)).frame(width: 2)
            Text(text)
                .cpBody()
                .foregroundStyle(Color.andromedaMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: minHeight, alignment: .top)
        .animation(.easeInOut(duration: 0.35), value: text)
    }
}

/// The dark inset a scene animates inside.
public struct PillarStage<Content: View>: View {
    public var accent: Color
    public var height: CGFloat
    public var glow: Bool
    private let content: Content

    public init(accent: Color, height: CGFloat = 158, glow: Bool = false,
                @ViewBuilder _ content: () -> Content) {
        self.accent = accent; self.height = height; self.glow = glow; self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if glow {
                    RadialGradient(colors: [accent.opacity(0.18), Color.andromedaVoid.opacity(0.95)],
                                   center: .init(x: 0.5, y: 1.25), startRadius: 10, endRadius: height * 1.6)
                } else {
                    Color.andromedaVoid.opacity(0.6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.16)))
            .animation(.easeInOut(duration: 0.6), value: accent)
    }
}

/// A complete pillar card: header, stage, chips, note.
public struct PillarPanel<S: PillarState, Icon: View, Scene: View>: View {
    public var title: String
    public var subtitle: String
    public var stageHeight: CGFloat
    public var glow: Bool
    @Binding public var state: S
    public var onPick: (() -> Void)?
    private let icon: Icon
    private let scene: Scene

    public init(
        title: String,
        subtitle: String,
        state: Binding<S>,
        stageHeight: CGFloat = 158,
        glow: Bool = false,
        onPick: (() -> Void)? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder scene: () -> Scene
    ) {
        self.title = title; self.subtitle = subtitle; self._state = state
        self.stageHeight = stageHeight; self.glow = glow; self.onPick = onPick
        self.icon = icon(); self.scene = scene()
    }

    public var body: some View {
        let accent = state.accent
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                icon
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.25)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).cpTitle().foregroundStyle(Color.andromedaInk)
                    Text(subtitle).font(AndromedaFont.mono(9.5)).foregroundStyle(Color.andromedaMuted)
                }
                Spacer(minLength: 8)
                DreamPillarBadge(state.badge, accent: accent)
            }

            PillarStage(accent: accent, height: stageHeight, glow: glow) { scene }
                .padding(.top, 14)

            DreamPillarChipRow(selection: $state, onPick: onPick)
                .padding(.top, 12)

            PillarNote(state.note, accent: accent)
                .padding(.top, 11)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(Color.andromedaPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.18)))
        .animation(.easeInOut(duration: 0.6), value: accent)
    }
}

// MARK: - Icons
// Nine marks, drawn as Shapes so they scale and tint with the state.

public struct DreamingMark: View {
    public var accent: Color
    public var awake: Bool
    public var spin: Double
    public init(accent: Color, awake: Bool, spin: Double = 0) {
        self.accent = accent; self.awake = awake; self.spin = spin
    }
    public var body: some View {
        ZStack {
            // Full moon awake, crescent asleep.
            Circle().stroke(accent, lineWidth: 2).frame(width: 18, height: 18)
                .overlay(alignment: .trailing) {
                    if !awake {
                        Circle().fill(Color.andromedaPanel)
                            .frame(width: 14, height: 14).offset(x: 3)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            Circle().fill(accent).frame(width: 4, height: 4)
                .offset(y: -13)
                .rotationEffect(.degrees(spin))
                .opacity(awake ? 0.35 : 1)
            Circle().fill(accent.opacity(0.55)).frame(width: 3, height: 3)
        }
        .frame(width: 26, height: 26)
    }
}

public struct MemoryMark: View {
    public var accent: Color
    public var corePulse: Double
    public init(accent: Color, corePulse: Double = 1) { self.accent = accent; self.corePulse = corePulse }
    public var body: some View {
        ZStack {
            HexagonMark().stroke(accent.opacity(0.85), lineWidth: 2).frame(width: 22, height: 24)
            Path { p in
                p.move(to: CGPoint(x: 11, y: 0)); p.addLine(to: CGPoint(x: 11, y: 12))
                p.move(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 22, y: 18))
                p.move(to: CGPoint(x: 11, y: 12)); p.addLine(to: CGPoint(x: 0, y: 18))
            }
            .stroke(accent.opacity(0.45), lineWidth: 1.2)
            .frame(width: 22, height: 24)
            Circle().fill(accent).frame(width: 6, height: 6).scaleEffect(corePulse)
        }
        .frame(width: 26, height: 26)
    }
}

public struct HexagonMark: Shape, Sendable {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let pts = [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.26), CGPoint(x: 1, y: 0.74),
                   CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.74), CGPoint(x: 0, y: 0.26)]
        for (i, u) in pts.enumerated() {
            let pt = CGPoint(x: rect.minX + u.x * rect.width, y: rect.minY + u.y * rect.height)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// The seven smaller marks, selected by pillar.
public struct PillarMark: View {
    public enum Kind: Sendable { case perception, writePath, proxy, skills, mcp, fabric, fleet }
    public var kind: Kind
    public var accent: Color
    public init(_ kind: Kind, accent: Color) { self.kind = kind; self.accent = accent }

    public var body: some View {
        Canvas { ctx, size in
            let s = size.width / 44
            func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var stroke = Path()
            var fills: [Path] = []

            switch kind {
            case .perception:
                fills.append(Path(ellipseIn: CGRect(x: 12 * s, y: 19 * s, width: 6 * s, height: 6 * s)))
                stroke.addArc(center: at(22, 22), radius: 11 * s,
                              startAngle: .degrees(-52), endAngle: .degrees(52), clockwise: false)
                stroke.move(to: at(29, 9))
                stroke.addArc(center: at(22, 22), radius: 17 * s,
                              startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
            case .writePath:
                stroke.move(to: at(7, 22)); stroke.addLine(to: at(24, 22))
                stroke.move(to: at(18, 15)); stroke.addLine(to: at(25, 22)); stroke.addLine(to: at(18, 29))
                stroke.move(to: at(31, 10)); stroke.addLine(to: at(31, 34))
                stroke.move(to: at(31, 10)); stroke.addLine(to: at(37, 10))
                stroke.move(to: at(31, 34)); stroke.addLine(to: at(37, 34))
            case .proxy:
                stroke.addEllipse(in: CGRect(x: 7 * s, y: 15 * s, width: 14 * s, height: 14 * s))
                stroke.move(to: at(21, 22)); stroke.addLine(to: at(30, 22))
                stroke.move(to: at(25, 22))
                stroke.addCurve(to: at(37, 12), control1: at(29, 22), control2: at(30, 12))
                stroke.move(to: at(25, 22))
                stroke.addCurve(to: at(37, 32), control1: at(29, 22), control2: at(30, 32))
                fills.append(Path(ellipseIn: CGRect(x: 35.5 * s, y: 9.5 * s, width: 5 * s, height: 5 * s)))
                fills.append(Path(ellipseIn: CGRect(x: 35.5 * s, y: 29.5 * s, width: 5 * s, height: 5 * s)))
            case .skills:
                stroke.addPath(HexagonMark().path(in: CGRect(x: 10 * s, y: 7 * s, width: 24 * s, height: 30 * s)))
                stroke.move(to: at(22, 16)); stroke.addLine(to: at(22, 28))
                stroke.move(to: at(16, 22)); stroke.addLine(to: at(28, 22))
            case .mcp:
                stroke.move(to: at(6, 22)); stroke.addLine(to: at(16, 22))
                stroke.move(to: at(28, 22)); stroke.addLine(to: at(38, 22))
                stroke.move(to: at(16, 14))
                stroke.addArc(center: at(16, 22), radius: 8 * s,
                              startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                stroke.closeSubpath()
                stroke.move(to: at(28, 14))
                stroke.addArc(center: at(28, 22), radius: 8 * s,
                              startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
                stroke.closeSubpath()
            case .fabric:
                stroke.addPath(Path(roundedRect: CGRect(x: 8 * s, y: 8 * s, width: 12 * s, height: 12 * s), cornerRadius: 2 * s))
                stroke.addPath(Path(roundedRect: CGRect(x: 24 * s, y: 8 * s, width: 12 * s, height: 12 * s), cornerRadius: 6 * s))
                stroke.addPath(Path(roundedRect: CGRect(x: 8 * s, y: 24 * s, width: 12 * s, height: 12 * s), cornerRadius: 6 * s))
                fills.append(Path(roundedRect: CGRect(x: 24 * s, y: 24 * s, width: 12 * s, height: 12 * s), cornerRadius: 2 * s))
            case .fleet:
                stroke.move(to: at(6, 22)); stroke.addLine(to: at(14, 22))
                stroke.addLine(to: at(18, 12)); stroke.addLine(to: at(24, 32))
                stroke.addLine(to: at(28, 22)); stroke.addLine(to: at(38, 22))
            }

            ctx.stroke(stroke, with: .color(accent),
                       style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
            for f in fills { ctx.fill(f, with: .color(accent)) }
        }
        .frame(width: 24, height: 24)
    }
}
