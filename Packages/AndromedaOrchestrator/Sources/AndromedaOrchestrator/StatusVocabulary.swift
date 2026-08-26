import SwiftUI

// MARK: - Status
//
// House rule: status is never communicated by color alone. Every status
// carries a hue, a glyph, and a word — so it survives grayscale, color-vision
// differences, and a screenshot in a bug report.

public enum OrchestratorStatus: String, Sendable, CaseIterable {
    case healthy
    case degraded
    case failed
    case idle
    case verifying

    /// ● ◐ ◯ ○ — the glyph is load-bearing, not decoration.
    public var glyph: String {
        switch self {
        case .healthy:   "●"
        case .degraded:  "◐"
        case .failed:    "◯"
        case .idle:      "○"
        case .verifying: "◐"
        }
    }

    public var label: String {
        switch self {
        case .healthy:   "HEALTHY"
        case .degraded:  "DEGRADED"
        case .failed:    "FAILED"
        case .idle:      "IDLE"
        case .verifying: "VERIFYING"
        }
    }

    public func tint(_ palette: OrchestratorPalette) -> Color {
        switch self {
        case .healthy:   palette.cyan
        case .degraded:  palette.amber
        case .failed:    palette.red
        case .idle:      palette.dim
        case .verifying: palette.amber
        }
    }

    /// Only unstable states animate — a healthy row must sit still.
    public var pulses: Bool {
        self == .degraded || self == .verifying || self == .failed
    }
}

/// Glyph + word, in the status hue.
public struct StatusBadge: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var status: OrchestratorStatus
    public var text: String?
    public var bordered: Bool

    @State private var pulsing = false

    public init(_ status: OrchestratorStatus, text: String? = nil, bordered: Bool = true) {
        self.status = status
        self.text = text
        self.bordered = bordered
    }

    private var word: String { text ?? status.label }

    public var body: some View {
        HStack(spacing: 7) {
            Text(status.glyph)
                .font(OrchestratorFont.mono(10, .semibold))
                .opacity(pulsing ? 0.45 : 1)
            Text(word)
                .font(OrchestratorFont.kicker(9))
                .tracking(1.0)
        }
        .foregroundStyle(status.tint(palette))
        .padding(.horizontal, bordered ? 8 : 0)
        .padding(.vertical, bordered ? 4 : 0)
        .background {
            if bordered {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(status.tint(palette).opacity(0.42), lineWidth: 1)
            }
        }
        .task {
            guard status.pulses, !reduceMotion else { return }
            withAnimation(OrchestratorMotion.pulse) { pulsing = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.lowercased())")
    }
}

/// Small uppercase section kicker used above every panel.
public struct Kicker: View {
    @Environment(\.palette) private var palette
    public var text: String
    public var tint: Color?

    public init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text.uppercased())
            .font(OrchestratorFont.kicker())
            .tracking(1.4)
            .foregroundStyle(tint ?? palette.dim)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// Text that types itself in, one character at a time, with a blinking caret.
/// Reduce Motion resolves it instantly.
public struct TypedText: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var full: String
    public var font: Font
    public var perCharacter: Duration
    public var showsCaret: Bool

    @State private var shown = ""
    @State private var caretOn = true

    public init(
        _ full: String,
        font: Font,
        perCharacter: Duration = .milliseconds(26),
        showsCaret: Bool = true
    ) {
        self.full = full
        self.font = font
        self.perCharacter = perCharacter
        self.showsCaret = showsCaret
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(shown)
                .font(font)
                .foregroundStyle(palette.ink)
            if showsCaret {
                Rectangle()
                    .fill(palette.cyan)
                    .frame(width: 2, height: 16)
                    .opacity(caretOn ? 1 : 0)
                    .animation(.easeInOut(duration: 0.1), value: caretOn)
            }
        }
        .task(id: full) { await type() }
        .task(id: full) { await blink() }
        .accessibilityLabel(full)
    }

    private func type() async {
        guard !reduceMotion else { shown = full; return }
        shown = ""
        for character in full {
            try? await Task.sleep(for: perCharacter)
            guard !Task.isCancelled else { return }
            shown.append(character)
        }
    }

    private func blink() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(520))
            caretOn.toggle()
        }
    }
}

/// Applies the console's one entrance curve with a per-row stagger.
public struct EntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var index: Int
    var step: Double
    @State private var shown = false

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .scaleEffect(shown ? 1 : 0.988, anchor: .top)
            .blur(radius: shown ? 0 : 2)
            .task {
                guard !reduceMotion else { shown = true; return }
                try? await Task.sleep(for: .seconds(OrchestratorMotion.stagger(index, step: step)))
                withAnimation(OrchestratorMotion.entrance) { shown = true }
            }
    }
}

public extension View {
    /// Gentle rise-and-settle entrance. Pass the row index for a cascade.
    func entrance(_ index: Int = 0, step: Double = 0.055) -> some View {
        modifier(EntranceModifier(index: index, step: step))
    }
}

#Preview("Status vocabulary") {
    VStack(alignment: .leading, spacing: 14) {
        ForEach(OrchestratorStatus.allCases, id: \.self) { StatusBadge($0) }
        TypedText("waking the control plane", font: OrchestratorFont.editorial(18))
    }
    .padding(28)
    .background(OrchestratorPalette.obsidian.void)
    .orchestratorPalette()
}
