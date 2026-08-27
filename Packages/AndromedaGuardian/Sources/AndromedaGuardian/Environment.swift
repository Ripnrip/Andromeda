import Foundation
import OSLog

// MARK: - Composition root (dependency injection, framework-free)
//
// The repo has zero DI containers (no Swinject/Factory/swift-dependencies
// anywhere), so the guardian does not import one for a single package.
// The DI pattern IS the canon shape here: protocol boundaries + constructor
// injection, with ONE composition root that names every wiring in one place.
//
// The root is an ENUM of presets — `.production`, `.ephemeral` (no disk),
// or `.custom(...)` for operators/tests that override exactly what they
// need. Swift 6 implicit existential opening means the guardian takes the
// concrete providers directly — no `Any*` eraser boxes, no type-erasure
// tax (the three boxes this file used to carry are gone).
//
// When the graph outgrows this (several packages resolving shared
// services), the upgrade path is pointfree `swift-dependencies` — the
// presets map 1:1 onto DependencyValues and call sites do not change.

/// Every dependency the guardian needs, resolved in one value.
public struct GuardianEnvironment: Sendable {
    public var configuration: GuardianConfiguration
    public var census: any CensusProvider
    public var sampler: any PressureProvider
    public var signaler: any ProcessSignaler
    public var telemetry: any TelemetrySink
    /// Sweep-event broadcaster the HTTP/SSE surface consumes.
    public var broadcaster: GuardianEventBroadcaster

    /// Named wirings. `production` is libproc + swap + kill(2) + JSONL +
    /// live broadcast; `ephemeral` keeps everything off disk (in-memory
    /// telemetry only) for tests and preview hosts.
    public enum Preset {
        case production
        case ephemeral
    }

    public init(preset: Preset = .production) {
        self.init(
            configuration: GuardianConfiguration(),
            census: preset == .production ? LibprocCensus() : LibprocCensus(),
            sampler: SwapPressureSampler(),
            signaler: POSIXSignaler(),
            telemetry: preset == .production
                ? CompositeTelemetrySink(sinks: []) // replaced below with broadcaster in the chain
                : CompositeTelemetrySink(sinks: []),
            broadcaster: GuardianEventBroadcaster()
        )
        // Wire the broadcaster into the telemetry chain for production.
        if preset == .production {
            telemetry = CompositeTelemetrySink(sinks: [
                JSONLTelemetrySink(),
                broadcaster,
            ])
        }
    }

    /// Fully custom wiring — tests and operators override exactly what they
    /// need; everything else defaults to the production shape.
    public init(
        configuration: GuardianConfiguration = GuardianConfiguration(),
        census: any CensusProvider = LibprocCensus(),
        sampler: any PressureProvider = SwapPressureSampler(),
        signaler: any ProcessSignaler = POSIXSignaler(),
        telemetry: (any TelemetrySink)? = nil,
        broadcaster: GuardianEventBroadcaster = GuardianEventBroadcaster()
    ) {
        self.configuration = configuration
        self.census = census
        self.sampler = sampler
        self.signaler = signaler
        self.broadcaster = broadcaster
        self.telemetry = telemetry ?? CompositeTelemetrySink(sinks: [
            JSONLTelemetrySink(),
            broadcaster,
        ])
    }

    /// Builds the concrete generic guardian from this environment.
    ///
    /// The existential providers are boxed here — the ONLY place erasure
    /// happens. Swift 6 implicit existential opening covers call arguments,
    /// not generic instantiation, so a three-closure box each is the minimum
    /// tax the language still charges; it is paid once, at the root, and
    /// nothing downstream sees it.
    public func makeGuardian() -> Guardian<AnyCensusProvider, AnyPressureProvider, AnyProcessSignaler> {
        Guardian(
            configuration: configuration,
            census: AnyCensusProvider(census),
            sampler: AnyPressureProvider(sampler),
            signaler: AnyProcessSignaler(signaler),
            telemetry: telemetry
        )
    }

    /// The production root (named preset sugar).
    public static var production: GuardianEnvironment { GuardianEnvironment(preset: .production) }
}


// MARK: - Type erasers (root-private)

/// Small, single-purpose boxes so the environment can hold existentials while
/// the coordinator stays generic (no `any` in its type parameters). Paid once
/// at the composition root; internal so they never leak into an API surface.
public struct AnyCensusProvider: CensusProvider {
    private let _sampleAll: @Sendable () throws -> [ProcessSample]
    public init(_ base: any CensusProvider) { _sampleAll = { try base.sampleAll() } }
    public func sampleAll() throws -> [ProcessSample] { try _sampleAll() }
}

public struct AnyPressureProvider: PressureProvider {
    private let _pressure: @Sendable (GuardianConfiguration) -> Pressure
    public init(_ base: any PressureProvider) { _pressure = { base.pressure(configuration: $0) } }
    public func pressure(configuration: GuardianConfiguration) -> Pressure { _pressure(configuration) }
}

public struct AnyProcessSignaler: ProcessSignaler {
    private let _signal: @Sendable (Int32, Int32) -> Bool
    private let _alive: @Sendable (Int32) -> Bool
    private let _matchesIdentity: @Sendable (Int32, Date) -> Bool
    public init(_ base: any ProcessSignaler) {
        _signal = { base.signal($0, $1) }
        _alive = { base.alive($0) }
        _matchesIdentity = { base.matchesIdentity($0, sampledStartTime: $1) }
    }
    public func signal(_ pid: Int32, _ sig: Int32) -> Bool { _signal(pid, sig) }
    public func alive(_ pid: Int32) -> Bool { _alive(pid) }
    public func matchesIdentity(_ pid: Int32, sampledStartTime: Date) -> Bool { _matchesIdentity(pid, sampledStartTime) }
}
