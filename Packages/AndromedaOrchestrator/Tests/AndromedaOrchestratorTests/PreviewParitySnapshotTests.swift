import SnapshotTesting
import SwiftUI
import Testing

@testable import AndromedaOrchestrator

/// Xcode-preview parity: every `#Preview` state in the package has a snapshot
/// twin here, so the canvas grid and the recorded baseline matrix can never
/// drift apart. A new preview state without a baseline fails the catalogue
/// review, not a user's screen.
///
/// Twins mirror each preview's exact view tree, scheme pinning, and frame.
/// Telemetry is pinned (`SnapshotFixtures`) so the live simulator cannot move
/// pixels under the baseline. Launch-reveal twins pin the `.wordmark` beat:
/// the `.markOnly` beat auto-advances one second after appear (`.task`), which
/// would race the capture.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter PreviewParitySnapshotTests`
/// (CI: tip the PR head with `[record-snapshots]`; baselines are runner-image-bound.)
@Suite(.serialized, .snapshots(record: OrchestratorSnapshotSupport.recordMode))
@MainActor
struct PreviewParitySnapshotTests {

    private func verify(
        _ view: some View,
        _ size: CGSize,
        name: String,
        dark: Bool,
        filePath: StaticString = #filePath,
        testName: String = #function
    ) throws {
        try OrchestratorSnapshotSupport.requireBaselines(file: filePath)
        let host = OrchestratorSnapshotHosting.makeHost(view, size, dark: dark)
        assertSnapshot(
            of: host,
            as: .orchestratorImage(precision: 0.98, perceptualPrecision: 0.96),
            named: "\(name)-\(dark ? "dark" : "light")",
            file: filePath,
            testName: testName
        )
    }

    // MARK: - Console shell

    /// Twin of `#Preview("Console · obsidian")`.
    @Test("Console · obsidian")
    func consoleObsidian() throws {
        try verify(
            OrchestratorConsole(model: SnapshotFixtures.steadyModel(), scheme: .dark)
                .frame(width: 1440, height: 900),
            CGSize(width: 1440, height: 900),
            name: "console-obsidian",
            dark: true
        )
    }

    /// Twin of `#Preview("Console · light")`.
    @Test("Console · light")
    func consoleLight() throws {
        try verify(
            OrchestratorConsole(model: SnapshotFixtures.steadyModel(), scheme: .light)
                .frame(width: 1440, height: 900),
            CGSize(width: 1440, height: 900),
            name: "console-light",
            dark: false
        )
    }

    /// Twin of `#Preview("Console · first run")` — reveal pinned to the
    /// `.wordmark` beat so the baseline cannot race the auto-advancing
    /// launch sequence.
    @Test("Console · first run")
    func consoleFirstRun() throws {
        let model = SnapshotFixtures.steadyModel()
        model.onboardingStep = 0
        model.launchPhase = .wordmark
        try verify(
            OrchestratorConsole(model: model, scheme: .dark)
                .frame(width: 1440, height: 900),
            CGSize(width: 1440, height: 900),
            name: "console-first-run",
            dark: true
        )
    }

    // MARK: - HUD

    /// Twin of `#Preview("HUD · docked")`.
    @Test("HUD · docked")
    func hudDocked() throws {
        try verify(
            HUDPanel(model: SnapshotFixtures.steadyModel())
                .padding(24)
                .background(OrchestratorPalette.obsidian.void)
                .orchestratorPalette(),
            CGSize(width: 460, height: 300),
            name: "hud-docked",
            dark: true
        )
    }

    /// Twin of `#Preview("HUD · light")`.
    @Test("HUD · light")
    func hudLight() throws {
        try verify(
            HUDPanel(model: SnapshotFixtures.steadyModel())
                .padding(24)
                .background(OrchestratorPalette.observatory.void)
                .environment(\.colorScheme, .light)
                .orchestratorPalette(),
            CGSize(width: 460, height: 300),
            name: "hud-light",
            dark: false
        )
    }

    // MARK: - Wizards

    /// Twin of `#Preview("Add a model")`.
    @Test("Wizard · add a model")
    func wizardAddModel() throws {
        try verify(
            AddResourceSheet(model: SnapshotFixtures.steadyModel(), wizard: .addModel)
                .orchestratorPalette(),
            CGSize(width: 760, height: 580),
            name: "wizard-add-model",
            dark: true
        )
    }

    /// Twin of `#Preview("Add an MCP server · light")`.
    @Test("Wizard · add an MCP server · light")
    func wizardAddMCPServerLight() throws {
        let model = SnapshotFixtures.steadyModel()
        model.wizardStep = 1
        try verify(
            AddResourceSheet(model: model, wizard: .addMCPServer)
                .environment(\.colorScheme, .light)
                .orchestratorPalette(),
            CGSize(width: 760, height: 580),
            name: "wizard-add-mcp-server",
            dark: false
        )
    }

    // MARK: - Brand + vocabulary

    /// Twin of `#Preview("Mark")`.
    @Test("Mark sizes")
    func markSizes() throws {
        try verify(
            HStack(spacing: 24) {
                AndromedaMarkView(size: 120)
                AndromedaMarkView(size: 56)
                AndromedaMarkView(size: 28)
            }
            .padding(40)
            .background(OrchestratorPalette.obsidian.void)
            .orchestratorPalette(),
            CGSize(width: 400, height: 220),
            name: "mark-sizes",
            dark: true
        )
    }

    /// Twin of `#Preview("Status vocabulary")`.
    @Test("Status vocabulary")
    func statusVocabulary() throws {
        try verify(
            VStack(alignment: .leading, spacing: 14) {
                ForEach(OrchestratorStatus.allCases, id: \.self) { StatusBadge($0) }
                TypedText("waking the control plane", font: OrchestratorFont.editorial(18))
            }
            .padding(28)
            .background(OrchestratorPalette.obsidian.void)
            .orchestratorPalette(),
            CGSize(width: 340, height: 430),
            name: "status-vocabulary",
            dark: true
        )
    }

    /// Twin of `#Preview("Palette")` — both schemes side by side.
    @Test("Palette · both schemes")
    func paletteBothSchemes() throws {
        try verify(
            HStack(spacing: 0) {
                ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Andromeda").font(OrchestratorFont.mono(11, .semibold))
                        Text("orchestrator").font(OrchestratorFont.editorial(22))
                    }
                    .padding(20)
                    .frame(width: 200, height: 120, alignment: .leading)
                    .background(OrchestratorPalette.forScheme(scheme).void)
                    .foregroundStyle(OrchestratorPalette.forScheme(scheme).ink)
                    .environment(\.colorScheme, scheme)
                }
            }
            .fixedSize(),
            CGSize(width: 420, height: 130),
            name: "palette",
            dark: true
        )
    }

    // MARK: - Launch + onboarding

    /// Twin of `#Preview("Launch reveal")` — pinned to the `.wordmark` beat.
    @Test("Launch reveal")
    func launchReveal() throws {
        let model = SnapshotFixtures.steadyModel()
        model.launchPhase = .wordmark
        try verify(
            LaunchRevealView(model: model)
                .frame(width: 900, height: 620)
                .background(OrchestratorPalette.obsidian.void)
                .orchestratorPalette(),
            CGSize(width: 900, height: 620),
            name: "launch-reveal",
            dark: true
        )
    }

    /// Twin of `#Preview("Onboarding · welcome")`.
    @Test("Onboarding · welcome")
    func onboardingWelcome() throws {
        try verify(
            OnboardingFlow(model: SnapshotFixtures.onboardingModel(step: 0))
                .frame(width: 980, height: 700)
                .orchestratorPalette(),
            CGSize(width: 980, height: 700),
            name: "onboarding-welcome",
            dark: true
        )
    }

    /// Twin of `#Preview("Onboarding · consolidation")`.
    @Test("Onboarding · consolidation")
    func onboardingConsolidation() throws {
        try verify(
            OnboardingFlow(model: SnapshotFixtures.onboardingModel(step: 2))
                .frame(width: 980, height: 700)
                .orchestratorPalette(),
            CGSize(width: 980, height: 700),
            name: "onboarding-consolidation",
            dark: true
        )
    }

    // MARK: - Screens

    /// Twin of `#Preview("States · obsidian")`.
    @Test("States · obsidian")
    func statesObsidian() throws {
        try verify(
            ScrollView {
                StatesScreen(model: SnapshotFixtures.steadyModel()).padding(18)
            }
            .frame(width: 1240, height: 900)
            .background(OrchestratorPalette.obsidian.void)
            .orchestratorPalette(),
            CGSize(width: 1240, height: 900),
            name: "states-obsidian",
            dark: true
        )
    }

    /// Twin of `#Preview("States · light")`.
    @Test("States · light")
    func statesLight() throws {
        try verify(
            ScrollView {
                StatesScreen(model: SnapshotFixtures.steadyModel()).padding(18)
            }
            .frame(width: 1240, height: 900)
            .background(OrchestratorPalette.observatory.void)
            .environment(\.colorScheme, .light)
            .orchestratorPalette(),
            CGSize(width: 1240, height: 900),
            name: "states-light",
            dark: false
        )
    }

    /// Twin of `#Preview("Usage")`.
    @Test("Usage · obsidian")
    func usage() throws {
        try verify(
            UsageScreen(model: SnapshotFixtures.steadyModel())
                .padding(18)
                .frame(width: 1240, height: 800)
                .background(OrchestratorPalette.obsidian.void)
                .orchestratorPalette(),
            CGSize(width: 1240, height: 800),
            name: "usage",
            dark: true
        )
    }

    /// Twin of `#Preview("Gateway · light")`.
    @Test("Gateway · light")
    func gatewayLight() throws {
        try verify(
            GatewayScreen(model: SnapshotFixtures.steadyModel())
                .padding(18)
                .frame(width: 1240, height: 860)
                .background(OrchestratorPalette.observatory.void)
                .environment(\.colorScheme, .light)
                .orchestratorPalette(),
            CGSize(width: 1240, height: 860),
            name: "gateway",
            dark: false
        )
    }

    // MARK: - Gallery

    /// Twin of `#Preview("Gallery · obsidian")`.
    @Test("Gallery · obsidian")
    func galleryObsidian() throws {
        try verify(
            OrchestratorGallery()
                .frame(width: 1280, height: 900)
                .orchestratorPalette(),
            CGSize(width: 1280, height: 900),
            name: "gallery-obsidian",
            dark: true
        )
    }

    /// Twin of `#Preview("Gallery · light")`.
    @Test("Gallery · light")
    func galleryLight() throws {
        try verify(
            OrchestratorGallery()
                .frame(width: 1280, height: 900)
                .environment(\.colorScheme, .light)
                .orchestratorPalette(),
            CGSize(width: 1280, height: 900),
            name: "gallery-light",
            dark: false
        )
    }
}
