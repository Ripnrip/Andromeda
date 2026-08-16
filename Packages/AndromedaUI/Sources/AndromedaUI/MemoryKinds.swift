import SwiftUI

// MARK: - The Andromeda mark
// An obscured nested triangle — the aurora peak. Use as app glyph / core.

public struct AndromedaMark: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.92))
        p.closeSubpath()
        return p
    }
}

/// The breathing core glyph with the triangle mark inside — matches the
/// Control Plane title bar and the floating bar.
public struct AndromedaCore: View {
    public var size: CGFloat
    @State private var breathe = false
    @State private var spin = false
    public init(size: CGFloat = 40) { self.size = size }
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        ZStack {
            Circle().stroke(Color.andromedaTeal, lineWidth: 1.5)
                .padding(size * 0.08)
                .scaleEffect(breathe ? 1.15 : 0.82)
                .opacity(breathe ? 0.25 : 0.95)
                .andromedaLoop(.easeInOut(duration: 1.8).repeatForever(), value: breathe)
            Circle().fill(Color.andromedaGlow)
                .frame(width: size * 0.12, height: size * 0.12)
                .shadow(color: .andromedaGlow, radius: 4)
                .offset(y: -size * 0.5)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .andromedaLoop(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
            AndromedaLogo(size: size * 0.5)
        }
        .frame(width: size, height: size)
        .onAppear { guard motionActive else { return }; breathe = true; spin = true }
    }
}

// MARK: - The eight jobs of memory

public struct MemoryKind: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case shipped, partial, specified
        var label: String { rawValue }
        var color: Color {
            switch self {
            case .shipped: return .andromedaLive
            case .partial: return .andromedaAmber
            case .specified: return .andromedaDim
            }
        }
    }
    /// Stable identity from the kind index (avoids non-deterministic `UUID()` in static catalogs).
    public var id: String { index }
    public let index: String
    public let name: String
    public let quote: String
    public let status: Status
    public let differentiator: Bool
}

public enum AndromedaMemory {
    /// The eight distinct jobs — memory is not a chat log with RAG.
    public static let kinds: [MemoryKind] = [
        .init(index: "01", name: "Episodic",     quote: "“We talked Tuesday.” Timed, ordered, compactable capture.", status: .shipped,   differentiator: false),
        .init(index: "02", name: "Semantic",     quote: "“Chapter 3 has the state machine.” Structure-first recall.", status: .partial, differentiator: false),
        .init(index: "03", name: "Photographic", quote: "“I’ve seen that diagram.” Vision recall over screenshots.",  status: .specified, differentiator: false),
        .init(index: "04", name: "Integrity",    quote: "“Can I trust this memory?” Merkle proofs over memory trees.", status: .partial, differentiator: true),
        .init(index: "05", name: "Meditation",   quote: "Morning reflection that reads the dream journal and sets intention.", status: .partial, differentiator: false),
        .init(index: "06", name: "Soul",         quote: "Presence, mood, relationship depth — context, not a chatbot.", status: .partial, differentiator: false),
        .init(index: "07", name: "Awareness",    quote: "Speak only when it matters. Silence is a feature.", status: .partial, differentiator: true),
        .init(index: "08", name: "Dreaming",     quote: "Night: Review → Shadow → Insight → Integration.", status: .partial, differentiator: true),
    ]
}

/// A single memory-kind card.
public struct MemoryKindCard: View {
    public var kind: MemoryKind
    public init(_ kind: MemoryKind) { self.kind = kind }
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.index).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(kind.status.color).frame(width: 6, height: 6)
                        .shadow(color: kind.status.color, radius: 3)
                    Text(kind.status.label).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(kind.status.color)
                }
            }
            HStack(spacing: 5) {
                Text(kind.name).font(.system(size: 15, weight: .medium))
                if kind.differentiator { Text("✦").font(.system(size: 12)).foregroundStyle(Color.andromedaTeal) }
            }
            Text(kind.quote).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.andromedaTeal.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.andromedaTeal.opacity(0.14))))
    }
}

/// The eight jobs of memory as an adaptive grid.
public struct MemoryKindsGrid: View {
    public init() {}
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The eight jobs of memory").font(.custom("Instrument Serif", size: 20))
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(AndromedaMemory.kinds) { MemoryKindCard($0) }
            }
        }
        .padding(16)
        .background(AndromedaSurface().ignoresSafeArea())
    }
}

#Preview("Memory kinds · dark")  { MemoryKindsGrid().frame(width: 680).preferredColorScheme(ColorScheme.dark) }
#Preview("Memory kinds · light") { MemoryKindsGrid().frame(width: 680).preferredColorScheme(ColorScheme.light) }
#Preview("AndromedaCore") { SchemePair { AndromedaCore(size: 48) } }
