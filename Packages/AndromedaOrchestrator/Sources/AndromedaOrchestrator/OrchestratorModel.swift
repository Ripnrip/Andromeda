import Observation
import SwiftUI

// MARK: - Console state
//
// One `@Observable` owner for navigation, the simulated request stream, and
// the first-run sequence. Views read it; nothing in here imports a view.

@MainActor
@Observable
public final class OrchestratorModel {

    public enum Screen: String, CaseIterable, Identifiable, Sendable {
        case overview, registry, providers, usage, gateway, states
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .overview:  "Orchestrator"
            case .registry:  "MCP registry"
            case .providers: "Providers & models"
            case .usage:     "Usage & telemetry"
            case .gateway:   "v1 Gateway"
            case .states:    "First-run & states"
            }
        }

        public var glyph: String {
            switch self {
            case .overview:  "◉"
            case .registry:  "⬡"
            case .providers: "⌁"
            case .usage:     "◫"
            case .gateway:   "⇌"
            case .states:    "◇"
            }
        }
    }

    /// The reveal that plays over the desktop when Andromeda launches.
    public enum LaunchPhase: Int, Sendable {
        case idle = -1, markOnly = 0, wordmark = 1, tagline = 2, dissolving = 3
    }

    public enum Wizard: String, Identifiable, Sendable {
        case addModel, addMCPServer
        public var id: String { rawValue }
    }

    // Navigation
    public var screen: Screen = .overview
    public var hudDetached = false

    // First run
    public var launchPhase: LaunchPhase = .idle
    public var onboardingStep: Int? = 0

    // Sheets
    public var wizard: Wizard?
    public var wizardStep = 0
    public var wizardSelection = 0
    public var withheldScopes: Set<String> = []
    public var probeProgress = 0

    // Live telemetry
    public var requests: [GatewayRequest] = []
    public var requestsPerMinute: Double = 1_240
    public var tokensPerSecond: Double = 18.4
    public var cacheHitRate: Double = 0.34
    public var isStreaming = true
    public var streamSpeed: Double = 1

    public private(set) var providers = SampleData.providers
    public let mcpServers = SampleData.mcpServers
    public let aliases = SampleData.aliases
    public let spend = SampleData.spend

    public init(firstRun: Bool = true, launchReveal: Bool = true) {
        if !firstRun {
            onboardingStep = nil
            launchPhase = .idle
        } else if launchReveal {
            launchPhase = .markOnly
        }
        requests = (0..<14).map { _ in Self.makeRequest() }
    }

    // MARK: Launch reveal

    /// Runs the four-beat reveal. Cancelling the task (skip / Esc) leaves the
    /// phase wherever the caller put it.
    public func runLaunchSequence() async {
        launchPhase = .markOnly
        try? await Task.sleep(for: .milliseconds(1000))
        guard !Task.isCancelled else { return }
        launchPhase = .wordmark
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        launchPhase = .tagline
        try? await Task.sleep(for: .milliseconds(2450))
        guard !Task.isCancelled else { return }
        launchPhase = .dissolving
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        launchPhase = .idle
    }

    public func skipLaunch() {
        guard launchPhase != .idle else { return }
        launchPhase = .dissolving
    }

    public func replayFirstRun() {
        onboardingStep = 0
        launchPhase = .markOnly
    }

    // MARK: Onboarding

    public static let onboardingTitles = [
        "One gateway. Every provider.",
        "Found your keys already",
        "Fifty subprocesses become one host",
        "Point everything at one base URL",
    ]

    public var onboardingTitle: String {
        guard let step = onboardingStep, step >= 0, step < Self.onboardingTitles.count else { return "" }
        return Self.onboardingTitles[step]
    }

    public func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        onboardingStep = step >= Self.onboardingTitles.count - 1 ? nil : step + 1
    }

    public func skipOnboarding() { onboardingStep = nil }

    // MARK: Wizards

    public func open(_ wizard: Wizard) {
        self.wizard = wizard
        wizardStep = 0
        wizardSelection = 0
        probeProgress = 0
        withheldScopes = []
    }

    public func advanceWizard(by delta: Int) {
        let next = wizardStep + delta
        if next < 0 || next > 2 {
            wizard = nil
            wizardStep = 0
        } else {
            wizardStep = next
            if next == 2 { probeProgress = 0 }
        }
    }

    public func toggleScope(_ scope: String) {
        if withheldScopes.contains(scope) { withheldScopes.remove(scope) }
        else { withheldScopes.insert(scope) }
    }

    /// Walks the verification checklist one line at a time.
    public func runProbe(lineCount: Int) async {
        probeProgress = 0
        while probeProgress < lineCount {
            try? await Task.sleep(for: .milliseconds(620))
            guard !Task.isCancelled else { return }
            probeProgress += 1
        }
    }

    // MARK: Simulated stream

    /// Drives the live request ticker. Backed by `.task`, cancelled on
    /// disappear — never a retained `Timer`.
    public func streamRequests() async {
        while !Task.isCancelled {
            let interval = Duration.milliseconds(Int(900 / max(streamSpeed, 0.1)))
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, isStreaming else { continue }
            tick()
        }
    }

    private func tick() {
        requests.insert(Self.makeRequest(), at: 0)
        if requests.count > 24 { requests.removeLast(requests.count - 24) }
        requestsPerMinute += Double.random(in: -34...38)
        requestsPerMinute = min(max(requestsPerMinute, 980), 1_680)
        tokensPerSecond += Double.random(in: -1.2...1.3)
        tokensPerSecond = min(max(tokensPerSecond, 12), 26)
        cacheHitRate += Double.random(in: -0.012...0.012)
        cacheHitRate = min(max(cacheHitRate, 0.22), 0.48)
    }

    private static func makeRequest() -> GatewayRequest {
        let dialect = Dialect.allCases.randomElement() ?? .messages
        let alias = SampleData.aliases.randomElement() ?? SampleData.aliases[0]
        let cached = Double.random(in: 0...1) < 0.34
        let failedOver = Double.random(in: 0...1) < 0.08
        return GatewayRequest(
            dialect: dialect,
            alias: alias.alias,
            route: failedOver ? "\(alias.provider) → bedrock" : alias.provider,
            latencyMS: cached ? Int.random(in: 8...40) : Int.random(in: 180...920),
            tokens: Int.random(in: 240...4_200),
            cached: cached,
            failedOver: failedOver,
            status: failedOver ? .degraded : .healthy
        )
    }

    // MARK: Derived

    public var totalSpend: String {
        let total = spend.reduce(0) { $0 + $1.spend }
        return String(format: "$%.2f", total)
    }

    public var cacheSavings: String {
        let saved = spend.reduce(0) { $0 + $1.spend * $1.cacheHitRate * 0.9 }
        return String(format: "−$%.0f", saved)
    }

    public var healthyServerCount: Int {
        mcpServers.filter { $0.status == .healthy }.count
    }
}
