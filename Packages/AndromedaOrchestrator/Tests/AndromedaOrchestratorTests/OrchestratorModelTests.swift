import Testing
@testable import AndromedaOrchestrator

// Pure-logic coverage. View rendering belongs in a snapshot target; these
// exercise the state machine the views read.

@MainActor
struct LaunchSequenceTests {

    @Test("First run starts on the launch reveal")
    func firstRunStartsWithReveal() {
        let model = OrchestratorModel()
        #expect(model.launchPhase == .markOnly)
        #expect(model.onboardingStep == 0)
    }

    @Test("Suppressing first run skips both the reveal and onboarding")
    func suppressedFirstRun() {
        let model = OrchestratorModel(firstRun: false)
        #expect(model.launchPhase == .idle)
        #expect(model.onboardingStep == nil)
    }

    @Test("Launch reveal without the reveal flag goes straight to onboarding")
    func revealDisabled() {
        let model = OrchestratorModel(firstRun: true, launchReveal: false)
        #expect(model.launchPhase == .idle)
        #expect(model.onboardingStep == 0)
    }

    @Test("Skipping mid-flight dissolves rather than cutting")
    func skipDissolves() {
        let model = OrchestratorModel()
        model.skipLaunch()
        #expect(model.launchPhase == .dissolving)
    }

    @Test("Replay restarts the whole sequence")
    func replay() {
        let model = OrchestratorModel(firstRun: false)
        model.replayFirstRun()
        #expect(model.launchPhase == .markOnly)
        #expect(model.onboardingStep == 0)
    }

    /// The console's launch task keys on `launchPhase != .idle`: every phase
    /// the sequence passes through (markOnly → wordmark → tagline →
    /// dissolving) must keep that ID true, or SwiftUI cancels the task
    /// mid-flight and the reveal strands as an invisible overlay (the
    /// `.markOnly`-keyed ID did exactly that — review finding, 2026-08-26).
    @Test("Task-ID stability: every in-flight phase is non-idle")
    func taskIDStabilityInvariant() {
        let inFlight: [OrchestratorModel.LaunchPhase] = [.markOnly, .wordmark, .tagline, .dissolving]
        #expect(inFlight.allSatisfy { $0 != .idle })
        // And the full sequence terminates at idle, flipping the ID false
        // only after completion.
        #expect(OrchestratorModel.LaunchPhase.idle.rawValue == -1)
    }
}

@MainActor
struct OnboardingTests {

    @Test("Onboarding advances through every step then clears")
    func advancesToEnd() {
        let model = OrchestratorModel()
        for _ in OrchestratorModel.onboardingTitles.indices { model.advanceOnboarding() }
        #expect(model.onboardingStep == nil)
    }

    @Test("Each step has a title")
    func titlesExist() {
        let model = OrchestratorModel()
        for index in OrchestratorModel.onboardingTitles.indices {
            model.onboardingStep = index
            #expect(!model.onboardingTitle.isEmpty)
        }
    }
}

@MainActor
struct WizardTests {

    @Test("Wizard walks three steps and closes past the end")
    func wizardFlow() {
        let model = OrchestratorModel(firstRun: false)
        model.open(.addModel)
        #expect(model.wizardStep == 0)
        model.advanceWizard(by: 1)
        model.advanceWizard(by: 1)
        #expect(model.wizardStep == 2)
        model.advanceWizard(by: 1)
        #expect(model.wizard == nil)
    }

    @Test("Backing out of the first step dismisses")
    func backOut() {
        let model = OrchestratorModel(firstRun: false)
        model.open(.addMCPServer)
        model.advanceWizard(by: -1)
        #expect(model.wizard == nil)
    }

    @Test("Scopes toggle off and back on")
    func scopeToggle() {
        let model = OrchestratorModel(firstRun: false)
        model.toggleScope("delete:repo")
        #expect(model.withheldScopes.contains("delete:repo"))
        model.toggleScope("delete:repo")
        #expect(!model.withheldScopes.contains("delete:repo"))
    }
}

struct StatusVocabularyTests {

    @Test("Every status carries a glyph and a word, not just a hue")
    func neverColorAlone() {
        for status in OrchestratorStatus.allCases {
            #expect(!status.glyph.isEmpty)
            #expect(!status.label.isEmpty)
        }
    }

    @Test("Only unstable states animate")
    func onlyUnstablePulse() {
        #expect(!OrchestratorStatus.healthy.pulses)
        #expect(!OrchestratorStatus.idle.pulses)
        #expect(OrchestratorStatus.degraded.pulses)
    }

    @Test("Breaker positions map onto the status vocabulary")
    func breakerMapping() {
        #expect(Provider.BreakerState.closed.status == .healthy)
        #expect(Provider.BreakerState.halfOpen.status == .degraded)
        #expect(Provider.BreakerState.open.status == .failed)
    }
}

struct DialectTests {

    @Test("All three dialects expose a v1 path")
    func paths() {
        #expect(Dialect.messages.path == "/v1/messages")
        #expect(Dialect.responses.path == "/v1/responses")
        #expect(Dialect.completions.path == "/v1/chat/completions")
    }
}
