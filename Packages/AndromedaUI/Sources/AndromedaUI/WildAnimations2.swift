import SwiftUI
#if canImport(Combine)
import Combine
#endif

// MARK: - "In the wild" (continued)

/// Petals arranged around an anchor, rotating as one — decorative loaders.
public struct PetalBloom: View {
    @State private var spin = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.andromedaTeal, .andromedaLive],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 11, height: 26)
                    .offset(y: -13)
                    .rotationEffect(.degrees(Double(i) / 6 * 360), anchor: .bottom)
            }
            Circle().fill(Color.andromedaGlow).frame(width: 10, height: 10)
                .shadow(color: .andromedaGlow, radius: 8)
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
        .andromedaLoop(.linear(duration: 8).repeatForever(autoreverses: false), value: spin)
        .onAppear { guard motionActive else { return }; spin = true }
    }
}

/// A bell shaking to draw the eye — new notifications.
public struct Jiggle: View {
    @State private var go = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        Image(systemName: "bell.fill").font(.system(size: 34))
            .foregroundStyle(Color.andromedaTeal)
            .rotationEffect(.degrees(go ? 9 : -9), anchor: .top)
            .andromedaLoop(.spring(duration: 0.25, bounce: 0.7).repeatForever(autoreverses: true), value: go)
            .onAppear { guard motionActive else { return }; go = true }
    }
}

/// Squash-and-stretch on a blob — a tactile press feedback.
public struct JelloSquash: View {
    @State private var squish = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [.andromedaTeal, .andromedaLive],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 40, height: 40)
            .scaleEffect(x: squish ? 1.2 : 0.85, y: squish ? 0.8 : 1.16)
            .andromedaLoop(.spring(duration: 0.5, bounce: 0.7).repeatForever(autoreverses: true), value: squish)
            .onAppear { guard motionActive else { return }; squish = true }
    }
}

/// Constant, decelerating, and springy — the same travel, three curves.
public struct EasingTrio: View {
    @State private var go = false
    private let curves: [Animation] = [
        .linear(duration: 1.3),
        .easeOut(duration: 1.3),
        .spring(duration: 1.3, bounce: 0.5),
    ]
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(curves.enumerated()), id: \.offset) { _, curve in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.andromedaTeal.opacity(0.1)).frame(width: 110, height: 8)
                    Circle().fill(Color.andromedaTeal).frame(width: 10, height: 10)
                        .shadow(color: .andromedaTeal, radius: 6)
                        .offset(x: go ? 100 : 0)
                        .andromedaLoop(curve.repeatForever(autoreverses: true), value: go)
                }
            }
        }
        .onAppear { guard motionActive else { return }; go = true }
    }
}

/// A balance beam tipping while dots pulse — the model weighing options.
public struct Thinking: View {
    @State private var tilt = false
    @State private var bounce = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule().fill(Color.andromedaMuted).frame(width: 64, height: 2)
                HStack {
                    Circle().fill(Color.andromedaTeal).frame(width: 8, height: 8)
                    Spacer()
                    Circle().fill(Color.andromedaLive).frame(width: 8, height: 8)
                }.frame(width: 64)
            }
            .rotationEffect(.degrees(tilt ? 9 : -9))
            .andromedaLoop(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: tilt)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.andromedaGlow).frame(width: 5, height: 5)
                        .offset(y: bounce ? -3 : 3)
                        .andromedaLoop(.easeInOut(duration: 0.45)
                            .delay(Double(i) * 0.15).repeatForever(autoreverses: true), value: bounce)
                }
            }
        }
        .onAppear { guard motionActive else { return }; tilt = true; bounce = true }
    }
}

/// Concentric strokes pulsing in and out of phase — focus states.
public struct InnerOuterBorder: View {
    @State private var glow = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        RoundedRectangle(cornerRadius: 14).strokeBorder(Color.andromedaTeal, lineWidth: 1.5)
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 9).strokeBorder(Color.andromedaLive, lineWidth: 1.5)
                    .padding(6)
                    .opacity(glow ? 1 : 0.35)
            )
            .scaleEffect(glow ? 1.05 : 1)
            .andromedaLoop(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: glow)
            .onAppear { guard motionActive else { return }; glow = true }
    }
}

/// Expanding rings under a hue-shifting glyph — ringing, live connection.
public struct IncomingCall: View {
    @State private var animate = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(Color.andromedaTeal, lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                    .scaleEffect(animate ? 1.9 : 0.5)
                    .opacity(animate ? 0 : 0.9)
                    .andromedaLoop(.easeOut(duration: 2.4)
                        .delay(Double(i) * 0.7).repeatForever(autoreverses: false), value: animate)
            }
            Image(systemName: "phone.fill").font(.system(size: 20))
                .foregroundStyle(Color.andromedaLive)
                .hueRotation(.degrees(animate ? 60 : 0))
                .andromedaLoop(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear { guard motionActive else { return }; animate = true }
    }
}

/// Two glass shapes drifting together and apart, morphing corners.
/// On iOS 26 / macOS 26 wrap the pair in a `GlassEffectContainer`.
public struct GlassMorph: View {
    @State private var apart = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        HStack(spacing: apart ? 14 : -6) {
            morphBlob
            morphBlob
        }
        .andromedaLoop(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: apart)
        .onAppear { guard motionActive else { return }; apart = true }
    }
    private var morphBlob: some View {
        RoundedRectangle(cornerRadius: apart ? 8 : 13)
            .fill(LinearGradient(colors: [.andromedaTeal, .andromedaGlow],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 26, height: 26)
            .shadow(color: .andromedaTeal.opacity(0.5), radius: 12)
    }
}

/// A bookmark dropping into place with a bounce — save-to-favourites.
public struct BookmarkTuck: View {
    @State private var saved = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        Image(systemName: "bookmark.fill").font(.system(size: 30))
            .foregroundStyle(Color.andromedaTeal)
            .offset(y: saved ? 0 : -22)
            .scaleEffect(saved ? 1 : 0.6)
            .opacity(saved ? 1 : 0)
            .andromedaLoop(.spring(duration: 0.5, bounce: 0.5).repeatForever(autoreverses: true), value: saved)
            .onAppear { guard motionActive else { return }; saved = true }
    }
}

/// A card swinging on its vertical axis — product showcases.
public struct Panel3DSway: View {
    @State private var angle = -27.0
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [.andromedaTeal.opacity(0.6), .andromedaLive.opacity(0.35)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 70, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.andromedaTeal.opacity(0.4)))
            .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
            .onAppear {
                guard motionActive else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { angle = 27 }
            }
    }
}

/// A token travelling between fixed anchor points — layout hand-offs.
public struct AnchorHop: View {
    @State private var index = 0
    private let anchors = [
        CGPoint(x: 10, y: 10), CGPoint(x: 74, y: 10),
        CGPoint(x: 74, y: 36), CGPoint(x: 10, y: 36),
    ]
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Same combined live-motion condition as the pillar timelines and the
    /// other timer-gated specimens — `.andromedaFrozen()` or system Reduce
    /// Motion pins the token at its current anchor.
    private var liveMotion: Bool { motionActive && !reduceMotion }
    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<anchors.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).stroke(Color.andromedaMuted.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .offset(x: anchors[i].x, y: anchors[i].y)
            }
            RoundedRectangle(cornerRadius: 4).fill(Color.andromedaTeal)
                .frame(width: 14, height: 14)
                .shadow(color: .andromedaTeal, radius: 8)
                .offset(x: anchors[index].x - 3, y: anchors[index].y - 3)
                .animation(.spring(duration: 0.5, bounce: 0.4), value: index)
        }
        .frame(width: 96, height: 54)
        .onReceive(timer) { _ in
            guard liveMotion else { return }
            index = (index + 1) % anchors.count
        }
    }
}

/// Coloured shards flung outward and tumbling — success and reward.
public struct ConfettiBurst: View {
    @State private var go = false
    private let palette: [Color] = [.andromedaTeal, .andromedaLive, .andromedaGlow]
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(palette[i % 3])
                    .frame(width: 5, height: 8)
                    .offset(x: go ? cos(angle(i)) * 30 : 0, y: go ? sin(angle(i)) * 30 : 0)
                    .rotationEffect(.degrees(go ? 180 : 0))
                    .opacity(go ? 0 : 1)
            }
        }
        .andromedaLoop(.easeOut(duration: 2).repeatForever(autoreverses: false), value: go)
        .onAppear { guard motionActive else { return }; go = true }
    }
    private func angle(_ i: Int) -> Double { Double(i) / 8 * 2 * .pi }
}

/// A pill stretching under a pull and snapping back — pull-to-refresh.
public struct RubberBand: View {
    @State private var pull = false
    public init() {}
    @Environment(\.andromedaMotionActive) private var motionActive
    public var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.andromedaTeal, .andromedaLive],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 56, height: 14)
            .scaleEffect(x: pull ? 1.45 : 0.9)
            .andromedaLoop(.spring(duration: 0.6, bounce: 0.7).repeatForever(autoreverses: true), value: pull)
            .onAppear { guard motionActive else { return }; pull = true }
    }
}

// MARK: - Previews

#Preview("PetalBloom")       { SchemePair { PetalBloom() } }
#Preview("Jiggle")           { SchemePair { Jiggle() } }
#Preview("JelloSquash")      { SchemePair { JelloSquash() } }
#Preview("EasingTrio")       { SchemePair { EasingTrio() } }
#Preview("Thinking")         { SchemePair { Thinking() } }
#Preview("InnerOuterBorder") { SchemePair { InnerOuterBorder() } }
#Preview("IncomingCall")     { SchemePair { IncomingCall() } }
#Preview("GlassMorph")       { SchemePair { GlassMorph() } }
#Preview("BookmarkTuck")     { SchemePair { BookmarkTuck() } }
#Preview("Panel3DSway")      { SchemePair { Panel3DSway() } }
#Preview("AnchorHop")        { SchemePair { AnchorHop() } }
#Preview("ConfettiBurst")    { SchemePair { ConfettiBurst() } }
#Preview("RubberBand")       { SchemePair { RubberBand() } }
