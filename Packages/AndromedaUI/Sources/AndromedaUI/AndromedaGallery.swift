import SwiftUI

// MARK: - Registry

/// A named specimen in the library — used by the gallery and the
/// snapshot-test sweep so both stay in lock-step with the catalogue.
public struct AndromedaSpecimen: Identifiable {
    public var id: String { name }
    public let name: String
    public let view: AnyView
    public init(_ name: String, _ view: some View) {
        self.name = name
        self.view = AnyView(view)
    }
}

public enum AndromedaCatalogue {
    /// Every animation the package ships, in gallery order.
    @MainActor public static var specimens: [AndromedaSpecimen] {
        [
            // Core
            .init("LivePulse", LivePulse()),
            .init("BreathingRing", BreathingRing()),
            .init("OrbitingSatellite", OrbitingSatellite()),
            .init("RecallWaveform", RecallWaveform()),
            .init("ScanSweep", ScanSweep()),
            .init("HUDCore", HUDCore()),
            .init("FleetConstellation", FleetConstellation()),
            .init("ShimmerSkeleton", ShimmerSkeleton()),
            // In the wild
            .init("Typewriter", Typewriter()),
            .init("Fireworks", Fireworks()),
            .init("PulsingHeart", PulsingHeart()),
            .init("SlideToUnlock", SlideToUnlock()),
            .init("NumericCrossfade", NumericCrossfade()),
            .init("HueRotation", HueRotation()),
            .init("CharacterFlip", CharacterFlip()),
            .init("DashMarch", DashMarch()),
            .init("SignatureDraw", SignatureDraw()),
            .init("SpringReactions", SpringReactions()),
            .init("LikeBurst", LikeBurst()),
            .init("OvershootBounce", OvershootBounce()),
            .init("PetalBloom", PetalBloom()),
            .init("Jiggle", Jiggle()),
            .init("JelloSquash", JelloSquash()),
            .init("EasingTrio", EasingTrio()),
            .init("Thinking", Thinking()),
            .init("InnerOuterBorder", InnerOuterBorder()),
            .init("IncomingCall", IncomingCall()),
            .init("GlassMorph", GlassMorph()),
            .init("BookmarkTuck", BookmarkTuck()),
            .init("Panel3DSway", Panel3DSway()),
            .init("AnchorHop", AnchorHop()),
            .init("ConfettiBurst", ConfettiBurst()),
            .init("RubberBand", RubberBand()),
            // Event-driven
            .init("RecallSkeletonRow", RecallSkeletonRow(width: 150)),
            .init("MemoryRecallControl", MemoryRecallControl()),
        ]
    }
}

// MARK: - Gallery

/// A scrolling grid of every specimen, on the theme-aware surface.
public struct AndromedaGallery: View {
    public init() {}
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]
    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AndromedaCatalogue.specimens) { specimen in
                    VStack(spacing: 8) {
                        ZStack { AndromedaSurface(); specimen.view }
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.andromedaTeal.opacity(0.12)))
                        Text(specimen.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(AndromedaSurface().ignoresSafeArea())
    }
}

#Preview("Gallery · Dark")  { AndromedaGallery().preferredColorScheme(ColorScheme.dark) }
#Preview("Gallery · Light") { AndromedaGallery().preferredColorScheme(ColorScheme.light) }
