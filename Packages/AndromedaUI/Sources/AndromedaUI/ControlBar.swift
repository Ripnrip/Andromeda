import SwiftUI
#if canImport(Combine)
import Combine
#endif

// MARK: - Control-plane model

/// The health of a capability — drives every status dot and glow in the bar.
public enum AndromedaHealth: String, CaseIterable, Sendable {
    case live      // resolving traffic, green
    case partial   // reachable but degraded, amber
    case spec      // declared, not yet wired, dim

    public var color: Color {
        switch self {
        case .live:    return .andromedaLive
        case .partial: return .andromedaAmber
        case .spec:    return .andromedaDim
        }
    }
    public var label: String { rawValue }
}

/// One of the six locked pillars for the floating control bar.
/// Distinct from control-plane nav `Pillar` (sidebar sections).
/// Clients address `id` only — Andromeda resolves provider/secrets/routing.
public struct BarPillar: Identifiable, Sendable {
    public let id: String          // stable capability id, e.g. "memory.recall"
    public let name: String
    public let short: String
    public let symbol: String      // SF Symbol
    public var health: AndromedaHealth

    public init(id: String, name: String, short: String, symbol: String, health: AndromedaHealth) {
        self.id = id; self.name = name; self.short = short; self.symbol = symbol; self.health = health
    }

    /// The six pillars, locked 2026-07-19.
    /// `infer.write` remains a stable client id but is an episodic-store alias today —
    /// never advertise it as LLM inference (see AGENTS.md).
    public static let all: [BarPillar] = [
        .init(id: "memory.recall",  name: "Memory · Anima",  short: "memory",  symbol: "waveform",              health: .live),
        .init(id: "mcp.host",       name: "MCP host",        short: "mcp",     symbol: "point.3.connected.trianglepath.dotted", health: .partial),
        .init(id: "skills.invoke",  name: "Skills registry", short: "skills",  symbol: "sparkles",              health: .spec),
        .init(id: "infer.write",    name: "infer.write",     short: "infer",   symbol: "square.and.pencil",     health: .spec),
        .init(id: "secrets.broker", name: "Secrets broker",  short: "secrets", symbol: "lock.shield.fill",      health: .spec),
        .init(id: "fleet.pulse",    name: "Fleet runtime",   short: "fleet",   symbol: "chart.line.uptrend.xyaxis", health: .partial),
    ]
}

// MARK: - Border beam (MagicUI-style traveling comet)

/// A comet of light traveling clockwise around a rounded border — the
/// signature "alive" edge of every Andromeda glass surface.
public struct BorderBeam: ViewModifier {
    @Environment(\.andromedaMotionActive) private var motionActive

    public var cornerRadius: CGFloat
    public var lineWidth: CGFloat
    public var duration: Double
    @State private var angle = 0.0

    public init(cornerRadius: CGFloat = 20, lineWidth: CGFloat = 1.4, duration: Double = 8) {
        self.cornerRadius = cornerRadius; self.lineWidth = lineWidth; self.duration = duration
    }

    public func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [.clear, .clear, .andromedaTeal, .andromedaGlow, .clear]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: lineWidth
                )
                .allowsHitTesting(false)
        )
        .onAppear {
            guard motionActive else { return }   // frozen: beam parked at 0°
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}

public extension View {
    func borderBeam(cornerRadius: CGFloat = 20, lineWidth: CGFloat = 1.4, duration: Double = 8) -> some View {
        modifier(BorderBeam(cornerRadius: cornerRadius, lineWidth: lineWidth, duration: duration))
    }

    /// Frosted-glass panel: translucent fill, hairline, soft shadow — the
    /// shared substrate for the bar, dock, and curtain.
    func andromedaGlass(cornerRadius: CGFloat = 20) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.andromedaTeal.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
    }
}

// MARK: - HUD core glyph (breathe + orbit + pulse)

/// The Andromeda mark: a breathing ring, an orbiting satellite, and a
/// pulsing core. Scales to any size; used in the bar, dock, and menu bar.
public struct HUDCoreGlyph: View {
    public var size: CGFloat
    @State private var breathe = false
    @State private var spin = false
    @State private var pulse = false
    public init(size: CGFloat = 40) { self.size = size }
    public var body: some View {
        ZStack {
            Circle().strokeBorder(Color.andromedaTeal, lineWidth: size * 0.038)
                .padding(size * 0.08)
                .scaleEffect(breathe ? 1.1 : 0.82)
                .opacity(breathe ? 0.25 : 0.95)
            Circle().strokeBorder(Color.andromedaGlow.opacity(0.6), lineWidth: 1)
                .padding(size * 0.2)
            Circle().fill(Color.andromedaGlow)
                .frame(width: size * 0.12, height: size * 0.12)
                .shadow(color: .andromedaGlow, radius: size * 0.14)
                .offset(y: -size * 0.42)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle().fill(Color.andromedaTeal)
                .frame(width: size * 0.3, height: size * 0.3)
                .shadow(color: .andromedaTeal, radius: pulse ? size * 0.4 : size * 0.16)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(Motion.breathe) { breathe = true }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(Motion.pulse) { pulse = true }
        }
    }
}

// MARK: - Pillar button

public struct PillarButton: View {
    public var pillar: BarPillar
    public var showLabel: Bool
    @State private var hovering = false
    public init(_ pillar: BarPillar, showLabel: Bool = true) {
        self.pillar = pillar; self.showLabel = showLabel
    }
    public var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: pillar.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.andromedaGlow)
                    .frame(width: 22, height: 22)
                    // Memory streams a live waveform; the symbol animates for it.
                    .symbolEffect(.variableColor.iterative, isActive: pillar.id == "memory.recall")
                Circle().fill(pillar.health.color)
                    .frame(width: 5, height: 5)
                    .shadow(color: pillar.health.color, radius: 3)
                    .offset(x: 4, y: -2)
                    .opacity(pillar.health == .live ? 1 : 0.8)
            }
            if showLabel {
                Text(pillar.short)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.andromedaMuted)
            }
        }
        .padding(.horizontal, 11).padding(.top, 7).padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.andromedaTeal.opacity(hovering ? 0.14 : 0))
        )
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(duration: 0.28, bounce: 0.4), value: hovering)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
    }
}

// MARK: - Fleet status

public struct FleetStatus: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    public var count: Int
    @State private var beat = false
    public init(count: Int = 3) { self.count = count }
    public var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.andromedaLive)
                .frame(width: 8, height: 8)
                .shadow(color: .andromedaLive, radius: 6)
                .scaleEffect(beat ? 1.35 : 1)
                .animation(.spring(duration: 0.4, bounce: 0.6).repeatForever(autoreverses: true), value: beat)
            VStack(alignment: .leading, spacing: 0) {
                Text("fleet · \(count)").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.andromedaGlow)
                Text("healthy").font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.andromedaMuted)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.andromedaLive.opacity(0.1)))
        .onAppear { if motionActive { beat = true } }
    }
}
