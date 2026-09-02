import SwiftUI

// MARK: - Launch reveal

//
// What the user sees when Andromeda comes up out of the HUD: the workspace
// dims and blurs away, the mark flies up out of the HUD corner, the wordmark
// resolves by closing its tracking, and a line types in underneath.
// Click anywhere or press Escape to skip.

public struct LaunchRevealView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable public var model: OrchestratorModel

    @State private var flown = false
    @State private var haloExpanded = false

    public init(model: OrchestratorModel) {
        self.model = model
    }

    private var dissolving: Bool {
        model.launchPhase == .dissolving
    }

    public var body: some View {
        ZStack {
            palette.void
                .opacity(dissolving ? 0.82 : 0.94)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                mark
                if model.launchPhase.rawValue >= OrchestratorModel.LaunchPhase.wordmark.rawValue {
                    VStack(spacing: 14) {
                        wordmark
                        if model.launchPhase.rawValue >= OrchestratorModel.LaunchPhase.tagline.rawValue {
                            TypedText("waking the control plane",
                                      font: OrchestratorFont.editorial(15))
                                .foregroundStyle(palette.muted)
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }

            if model.launchPhase.rawValue >= OrchestratorModel.LaunchPhase.wordmark.rawValue {
                VStack {
                    Spacer()
                    Kicker("click anywhere to continue")
                        .padding(.bottom, 40)
                }
            }
        }
        .opacity(dissolving ? 0 : 1)
        .scaleEffect(dissolving ? 1.06 : 1)
        .animation(.easeIn(duration: 0.62), value: dissolving)
        .animation(OrchestratorMotion.entrance, value: model.launchPhase)
        .contentShape(.rect)
        .onTapGesture { model.skipLaunch() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Skip the Andromeda launch animation")
        .accessibilityAction { model.skipLaunch() }
        .task {
            guard !reduceMotion else { flown = true; haloExpanded = true; return }
            withAnimation(.spring(duration: 1.05, bounce: 0.24)) { flown = true }
            withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.55)) {
                haloExpanded = true
            }
        }
    }

    private var mark: some View {
        ZStack {
            // Angular halo — the mark's own silhouette expanding outward.
            AndromedaTrefoil()
                .stroke(palette.cyan.opacity(haloExpanded ? 0 : 0.5), lineWidth: 1.1)
                .frame(width: 352, height: 352)
                .scaleEffect(haloExpanded ? 2.5 : 0.2)

            Circle()
                .fill(RadialGradient(colors: [palette.cyan.opacity(0.2), .clear],
                                     center: .center, startRadius: 0, endRadius: 250))
                .frame(width: 504, height: 504)

            AndromedaMarkView(size: 168)
                // Flies up out of the HUD's bottom-right corner.
                .offset(x: flown ? 0 : 300, y: flown ? 0 : 268)
                .scaleEffect(flown ? 1 : 0.14)
                .blur(radius: flown ? 0 : 6)
                .opacity(flown ? 1 : 0)
        }
        .frame(width: 168, height: 168)
    }

    private var wordmark: some View {
        Text("ANDROMEDA")
            .font(OrchestratorFont.mono(15, .medium))
            .tracking(flown ? 4.5 : 11)
            .foregroundStyle(palette.ink)
            .blur(radius: flown ? 0 : 4)
            .animation(.spring(duration: 1.1, bounce: 0.1), value: flown)
    }
}

#Preview("Launch reveal") {
    LaunchRevealView(model: OrchestratorModel())
        .frame(width: 900, height: 620)
        .background(OrchestratorPalette.obsidian.void)
        .orchestratorPalette()
}
