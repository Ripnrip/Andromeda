import SwiftUI
#if canImport(Combine)
import Combine
#endif

// MARK: - "In the wild"
// Twenty-five crowd-favourite SwiftUI patterns, retuned to the Andromeda
// palette and timing tokens. Inspired by amosgyamfi/open-swiftui-animations.

/// Text that types itself out, holds, then erases — cursor blinking throughout.
public struct Typewriter: View {
    @Environment(\.andromedaMotionActive) private var motionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Live = motion env on AND Reduce Motion off — the same condition the
    /// pillar timelines use. Both timers must stop under system Reduce Motion,
    /// not just under the custom frozen flag.
    private var liveMotion: Bool { motionActive && !reduceMotion }

    public var text: String
    @State private var count = 0
    @State private var forward = true
    @State private var caretOn = true
    private let step = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()
    private let blink = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    public init(_ text: String = "boot sequence…") { self.text = text }
    public var body: some View {
        HStack(spacing: 1) {
            Text(String(text.prefix(count)))
                .font(.system(size: 15, design: .monospaced))
            Rectangle().frame(width: 2, height: 18).opacity(caretOn ? 1 : 0)
        }
        .foregroundStyle(Color.andromedaGlow)
        .onReceive(step) { _ in
            guard liveMotion else { return }   // frozen / Reduce Motion: stays at frame zero
            if forward { count += 1; if count >= text.count { forward = false } }
            else       { count -= 1; if count <= 0 { forward = true } }
        }
        .onReceive(blink) { _ in
            guard liveMotion else { return }
            caretOn.toggle()
        }
    }
}

/// A burst of particles launching outward and fading — completions.
public struct Fireworks: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var go = false
    public init() {}
    public var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle().fill(Color.andromedaGlow).frame(width: 5, height: 5)
                    .shadow(color: .andromedaTeal, radius: 4)
                    .offset(x: go ? cos(angle(i)) * 34 : 0, y: go ? sin(angle(i)) * 34 : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: go)
        .onAppear { if motionActive { go = true } }
    }
    private func angle(_ i: Int) -> Double { Double(i) / 8 * 2 * .pi }
}

/// A double-thump heartbeat for likes, favourites, and health signals.
public struct PulsingHeart: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var beat = false
    public init() {}
    public var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 40))
            .foregroundStyle(Color.andromedaLive)
            .scaleEffect(beat ? 1.25 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.6).repeatForever(), value: beat)
            .onAppear { if motionActive { beat = true } }
    }
}

/// A sheen travelling across a label — the invitation to swipe.
public struct SlideToUnlock: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    public var text: String
    @State private var phase: CGFloat = -1
    public init(_ text: String = "slide to deploy") { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Color.andromedaMuted)
            .overlay(
                LinearGradient(colors: [.clear, .andromedaGlow, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 64)
                    .offset(x: phase * 130)
                    .mask(Text(text).font(.system(size: 14, weight: .medium, design: .rounded)))
            )
            .padding(.horizontal, 16).padding(.vertical, 9)
            .overlay(Capsule().stroke(Color.andromedaTeal.opacity(0.3)))
            .onAppear {
                guard motionActive else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// A digit fading up and out as a counter ticks — live totals.
public struct NumericCrossfade: View {
    @Environment(\.andromedaMotionActive) private var motionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Same combined live-motion condition as the pillar timelines — the
    /// ticker must also stop under system Reduce Motion, not just `.andromedaFrozen()`.
    private var liveMotion: Bool { motionActive && !reduceMotion }

    @State private var value = 428
    private let timer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()
    public init() {}
    public var body: some View {
        Text(value, format: .number.grouping(.never))
            .font(.system(size: 30, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.andromedaGlow)
            .contentTransition(.numericText(value: Double(value)))
            .onReceive(timer) { _ in
            guard liveMotion else { return }
            withAnimation(.easeInOut) { value += 7 }
        }
    }
}

/// A tile cycling through the palette on a hue wheel — highlights.
public struct HueRotation: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var hue = 0.0
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(colors: [.andromedaTeal, .andromedaLive],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .shadow(color: .andromedaTeal.opacity(0.5), radius: 12)
            .hueRotation(.degrees(hue))
            .onAppear {
                guard motionActive else { return }
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { hue = 360 }
            }
    }
}

/// Each glyph tumbling on its Y axis in sequence — status words.
public struct CharacterFlip: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    public var text: String
    @State private var flip = false
    public init(_ text: String = "ONLINE") { self.text = text }
    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.andromedaGlow)
                    .rotation3DEffect(.degrees(flip ? 180 : 0), axis: (0, 1, 0))
                    .animation(.spring(duration: 0.6, bounce: 0.3)
                        .delay(Double(i) * 0.12).repeatForever(autoreverses: true), value: flip)
            }
        }
        .onAppear { if motionActive { flip = true } }
    }
}

/// A dashed outline crawling around a shape — active selection.
public struct DashMarch: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var phase: CGFloat = 0
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.andromedaTeal,
                    style: StrokeStyle(lineWidth: 2, dash: [10, 6], dashPhase: phase))
            .frame(width: 58, height: 58)
            .onAppear {
                guard motionActive else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = -32 }
            }
    }
}

/// A path drawing itself on, then erasing — signatures and route reveals.
public struct SignatureDraw: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var to: CGFloat = 0
    public init() {}
    public var body: some View {
        SignatureShape()
            .trim(from: 0, to: to)
            .stroke(Color.andromedaGlow,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 120, height: 52)
            .onAppear {
                guard motionActive else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { to = 1 }
            }
    }
}

struct SignatureShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 34))
        p.addCurve(to: CGPoint(x: 34, y: 30), control1: CGPoint(x: 22, y: 6),  control2: CGPoint(x: 30, y: 6))
        p.addCurve(to: CGPoint(x: 56, y: 24), control1: CGPoint(x: 48, y: 46), control2: CGPoint(x: 48, y: 40))
        p.addCurve(to: CGPoint(x: 84, y: 30), control1: CGPoint(x: 74, y: 4),  control2: CGPoint(x: 74, y: 24))
        p.addCurve(to: CGPoint(x: 114, y: 22), control1: CGPoint(x: 100, y: 44), control2: CGPoint(x: 104, y: 40))
        return p
    }
}

/// Reaction chips popping in with overshoot — messenger-style bursts.
public struct SpringReactions: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    private let symbols = ["heart.fill", "sparkles", "hand.thumbsup.fill"]
    @State private var shown = false
    public init() {}
    public var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { i, s in
                Image(systemName: s).font(.system(size: 13))
                    .foregroundStyle(Color.andromedaGlow)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.andromedaTeal.opacity(0.1)))
                    .overlay(Circle().stroke(Color.andromedaTeal.opacity(0.2)))
                    .scaleEffect(shown ? 1 : 0)
                    .animation(.spring(duration: 0.45, bounce: 0.6)
                        .delay(Double(i) * 0.12).repeatForever(autoreverses: true), value: shown)
            }
        }
        .onAppear { if motionActive { shown = true } }
    }
}

/// A heart that thumps while sparks radiate — the tap-to-like moment.
public struct LikeBurst: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var go = false
    public init() {}
    public var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Circle().fill(Color.andromedaTeal).frame(width: 4, height: 4)
                    .offset(x: go ? cos(angle(i)) * 26 : 0, y: go ? sin(angle(i)) * 26 : 0)
                    .opacity(go ? 0 : 1)
            }
            Image(systemName: "heart.fill").font(.system(size: 26))
                .foregroundStyle(Color.andromedaLive)
                .scaleEffect(go ? 1 : 0.6)
        }
        .animation(.spring(duration: 0.7, bounce: 0.5).repeatForever(autoreverses: true), value: go)
        .onAppear { if motionActive { go = true } }
    }
    private func angle(_ i: Int) -> Double { Double(i) / 6 * 2 * .pi }
}

/// An element dropping in and settling past its mark — playful entrances.
public struct OvershootBounce: View {
    @Environment(\.andromedaMotionActive) private var motionActive

    @State private var dropped = false
    public init() {}
    public var body: some View {
        Circle().fill(Color.andromedaTeal).frame(width: 22, height: 22)
            .shadow(color: .andromedaTeal, radius: 10)
            .offset(y: dropped ? 0 : -26)
            .animation(.spring(duration: 0.6, bounce: 0.55).repeatForever(autoreverses: true), value: dropped)
            .onAppear { if motionActive { dropped = true } }
    }
}

// MARK: - Previews

#Preview("Typewriter")       { SchemePair { Typewriter() } }
#Preview("Fireworks")        { SchemePair { Fireworks() } }
#Preview("PulsingHeart")     { SchemePair { PulsingHeart() } }
#Preview("SlideToUnlock")    { SchemePair { SlideToUnlock() } }
#Preview("NumericCrossfade") { SchemePair { NumericCrossfade() } }
#Preview("HueRotation")      { SchemePair { HueRotation() } }
#Preview("CharacterFlip")    { SchemePair { CharacterFlip() } }
#Preview("DashMarch")        { SchemePair { DashMarch() } }
#Preview("SignatureDraw")    { SchemePair { SignatureDraw() } }
#Preview("SpringReactions")  { SchemePair { SpringReactions() } }
#Preview("LikeBurst")        { SchemePair { LikeBurst() } }
#Preview("OvershootBounce")  { SchemePair { OvershootBounce() } }
