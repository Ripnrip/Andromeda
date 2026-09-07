import SwiftUI

// MARK: - Registry

//
// One catalogue of named specimens — the gallery, the snapshot sweep, and the
// docs all read from this list so nothing drifts. A specimen without a row
// here is a component nobody can browse or regression-check.

/// A named specimen in the console library.
public struct OrchestratorSpecimen: Identifiable {
    public let id = UUID()
    public let name: String
    public let group: OrchestratorGroup
    public let view: AnyView

    public init(_ name: String, group: OrchestratorGroup = .vocabulary, _ view: some View) {
        self.name = name
        self.group = group
        self.view = AnyView(view)
    }
}

/// The shelves of the console library.
public enum OrchestratorGroup: String, CaseIterable, Identifiable, Sendable {
    case brand = "Brand"
    case vocabulary = "Status vocabulary"
    case controls = "Console controls"
    case hud = "HUD"
    case screens = "Screens"
    case flows = "Flows & wizards"

    public var id: String {
        rawValue
    }
}

/// Deterministic telemetry samples shared by catalogue specimens — a fixed
/// wave, not RNG, so the snapshot sweep is byte-stable.
public enum CatalogueSamples {
    public static let wave: [Double] = (0 ..< 28).map { i -> Double in
        0.45 + 0.28 * sin(Double(i) * 0.55) + 0.08 * sin(Double(i) * 1.9)
    }

    public static let climb: [Double] = (0 ..< 20).map { i -> Double in
        0.2 + Double(i) * 0.035 + 0.04 * sin(Double(i))
    }
}

@MainActor
public enum OrchestratorCatalogue {
    /// Every specimen the console ships, in gallery order.
    public static var specimens: [OrchestratorSpecimen] {
        OrchestratorGroup.allCases.flatMap { specimens(in: $0) }
    }

    public static func specimens(in group: OrchestratorGroup) -> [OrchestratorSpecimen] {
        switch group {
        case .brand: brand
        case .vocabulary: vocabulary
        case .controls: controls
        case .hud: hud
        case .screens: screens + selfJournal
        case .flows: flows
        }
    }

    /// The angular trefoil and its range of sizes.
    static let brand: [OrchestratorSpecimen] = [
        .init("Mark · 120", group: .brand, AndromedaMarkView(size: 120)),
        .init("Mark · 56", group: .brand, AndromedaMarkView(size: 56)),
        .init("Mark · 28", group: .brand, AndromedaMarkView(size: 28)),
    ]

    /// The five states — glyph + word + hue, never color alone.
    static let vocabulary: [OrchestratorSpecimen] =
        OrchestratorStatus.allCases.map { status in
            OrchestratorSpecimen("Badge · \(status.label)", group: .vocabulary, StatusBadge(status))
        }

    /// The console's atoms: buttons, navigation, metrics, charts.
    static let controls: [OrchestratorSpecimen] = [
        .init(
            "Button · primary", group: .controls,
            Button("Add a resource") {}.buttonStyle(ConsoleButtonStyle(kind: .primary))
        ),
        .init(
            "Button · ghost", group: .controls,
            Button("Refresh") {}.buttonStyle(ConsoleButtonStyle(kind: .ghost))
        ),
        .init(
            "Button · quiet", group: .controls,
            Button("Dismiss") {}.buttonStyle(ConsoleButtonStyle(kind: .quiet))
        ),
        .init(
            "Button · danger", group: .controls,
            Button("Disconnect") {}.buttonStyle(ConsoleButtonStyle(kind: .danger))
        ),
        .init(
            "NavRow · selected", group: .controls,
            NavRow(screen: .overview, isSelected: true) {}
        ),
        .init(
            "NavRow · plain", group: .controls,
            NavRow(screen: .usage, badge: "3", isSelected: false) {}
        ),
        .init(
            "MetricTile · sparkline", group: .controls,
            MetricTile(label: "req/min", value: "1,240", samples: CatalogueSamples.wave)
        ),
        .init(
            "MetricTile · unit + note", group: .controls,
            MetricTile(
                label: "tokens/s", value: "18.4", unit: "tok",
                note: "p95 across aliases", samples: CatalogueSamples.climb
            )
        ),
        .init(
            "Sparkline", group: .controls,
            Sparkline(samples: CatalogueSamples.wave, tint: .cyan)
        ),
        .init(
            "ShareBar", group: .controls,
            ShareBar(share: 0.62, tint: .cyan)
                .frame(width: 220)
        ),
        .init(
            "Kicker + TypedText", group: .controls,
            VStack(alignment: .leading, spacing: 8) {
                Kicker("v1 gateway")
                TypedText("one base URL for every client", font: OrchestratorFont.editorial(18))
            }
            .frame(width: 300, alignment: .leading)
        ),
    ]

    /// The docked HUD, steady state.
    static let hud: [OrchestratorSpecimen] = {
        let model = CatalogueFixtures.steadyModel()
        return [
            .init("HUD · docked", group: .hud, HUDPanel(model: model).padding(20)),
        ]
    }()

    /// Compact keyhole crops of the six screens (full-frame twins live in the
    /// preview-parity suite).
    static let screens: [OrchestratorSpecimen] = {
        let model = CatalogueFixtures.steadyModel()
        return [
            .init("Screen · overview", group: .screens,
                  OverviewScreen(model: model).frame(width: 560, height: 340)),
            .init("Screen · registry", group: .screens,
                  RegistryScreen(model: model).frame(width: 560, height: 340)),
            .init("Screen · providers", group: .screens,
                  ProvidersScreen(model: model).frame(width: 560, height: 340)),
            .init("Screen · usage", group: .screens,
                  UsageScreen(model: model).frame(width: 560, height: 340)),
            .init("Screen · gateway", group: .screens,
                  GatewayScreen(model: model).frame(width: 560, height: 340)),
            .init("Screen · states", group: .screens,
                  StatesScreen(model: model).frame(width: 560, height: 340)),
        ]
    }()

    /// The console's own flight recorder — internal observability specimen.
    /// Deterministic: pinned ids, pinned instants, environment-pinned clock
    /// (see the parity twin).
    static let selfJournal: [OrchestratorSpecimen] = {
        let journal = OrchestratorJournal()
        let pinned = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let seeded: [JournalEntry] = [
            (12, OrchestratorEvent.screenChanged(.overview)),
            (10, .wizardOpened(.addModel)),
            (8, .scopeToggled("mcp.write", withheld: true)),
            (6, .probeAdvanced(line: 3, of: 5)),
            (4, .probeCompleted),
            (3, .hudDetached(true)),
            (1, .streamPaused),
        ].map { offset, event in
            JournalEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", Int(offset * 10)))!,
                at: pinned.addingTimeInterval(-offset),
                event: event
            )
        }
        journal.replaceAll(with: seeded)
        return [
            .init("Journal · self", group: .screens,
                  JournalWall(journal: journal)
                      .environment(\.journalNow) { pinned }
                      .frame(width: 520, height: 320)),
        ]
    }()

    /// Onboarding beats and wizard steps.
    static let flows: [OrchestratorSpecimen] = {
        let onboarding = CatalogueFixtures.steadyModel()
        onboarding.onboardingStep = 0
        let model = CatalogueFixtures.steadyModel()
        return [
            .init(
                "Onboarding · welcome", group: .flows,
                OnboardingFlow(model: onboarding)
                    .frame(width: 640, height: 420)
            ),
            .init(
                "Wizard · add a model", group: .flows,
                AddResourceSheet(model: model, wizard: .addModel)
                    .frame(width: 640, height: 480)
            ),
        ]
    }()
}

/// Deterministic gateway requests, shared by gallery specimens and snapshot
/// fixtures — fixed content, no RNG, so renders are byte-stable across
/// processes. Every dialect, cached and uncached, a failover, one degraded row.
public extension SampleData {
    static let deterministicRequests: [GatewayRequest] = [
        GatewayRequest(dialect: .messages, alias: "anthropic/claude-opus-4", route: "anthropic", latencyMS: 212, tokens: 3140, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .responses, alias: "openai/gpt-5.2", route: "openai", latencyMS: 486, tokens: 2210, cached: false, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .completions, alias: "venice/llama-4-405b", route: "venice", latencyMS: 34, tokens: 812, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .messages, alias: "cerebras/llama-4-scout", route: "cerebras", latencyMS: 158, tokens: 1508, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .responses, alias: "osaurus/deepseek-v4", route: "osaurus", latencyMS: 604, tokens: 4020, cached: false, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .completions, alias: "groq/mistral-small", route: "groq", latencyMS: 41, tokens: 640, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .messages, alias: "anthropic/claude-sonnet", route: "anthropic → bedrock", latencyMS: 742, tokens: 2870, cached: false, failedOver: true, status: .degraded),
        GatewayRequest(dialect: .responses, alias: "openai/gpt-5-mini", route: "openai", latencyMS: 329, tokens: 1112, cached: false, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .completions, alias: "openrouter/auto", route: "openrouter", latencyMS: 268, tokens: 1940, cached: false, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .messages, alias: "zai/glm-5.2", route: "zai", latencyMS: 194, tokens: 2460, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .responses, alias: "gemini/2.5-flash", route: "google", latencyMS: 512, tokens: 3380, cached: false, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .completions, alias: "venice/qwen-3-coder", route: "venice", latencyMS: 29, tokens: 970, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .messages, alias: "cerebras/llama-4-maverick", route: "cerebras", latencyMS: 143, tokens: 1760, cached: true, failedOver: false, status: .healthy),
        GatewayRequest(dialect: .responses, alias: "anthropic/claude-opus-4", route: "anthropic", latencyMS: 1064, tokens: 4200, cached: false, failedOver: false, status: .healthy),
    ]
}

/// Fixed-fixture models for catalogue specimens (same shape as the
/// preview-parity `SnapshotFixtures`, internal to the gallery's use).
@MainActor
enum CatalogueFixtures {
    static func steadyModel() -> OrchestratorModel {
        let model = OrchestratorModel(firstRun: false)
        model.isStreaming = false
        model.requests = SampleData.deterministicRequests
        model.requestsPerMinute = 1240
        model.tokensPerSecond = 18.4
        model.cacheHitRate = 0.34
        return model
    }
}
