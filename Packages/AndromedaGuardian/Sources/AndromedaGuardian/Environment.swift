import Foundation
import OSLog

// MARK: - Composition root (dependency injection, framework-free)
//
// The repo has zero DI containers (no Swinject/Factory/swift-dependencies
// anywhere), so the guardian does not import one for a single package.
// The DI pattern IS the canon shape here: protocol boundaries + constructor
// injection, with ONE composition root that names every wiring in one place.
// `GuardianEnvironment` is that root — production presets, test fixtures,
// and partial overrides are values, not container registrations.
//
// When the graph outgrows this (several packages resolving shared services),
// the upgrade path is pointfree `swift-dependencies` — the shape below maps
// 1:1 onto DependencyValues and the call sites do not change.

/// Every dependency the guardian needs, resolved in one value.
public struct GuardianEnvironment: Sendable {
    public var configuration: GuardianConfiguration
    public var census: any CensusProvider
    public var sampler: any PressureProvider
    public var signaler: any ProcessSignaler
    public var telemetry: any TelemetrySink
    /// Sweep-event broadcaster the HTTP/SSE surface consumes.
    public var broadcaster: GuardianEventBroadcaster

    public init(
        configuration: GuardianConfiguration,
        census: any CensusProvider,
        sampler: any PressureProvider,
        signaler: any ProcessSignaler,
        telemetry: any TelemetrySink,
        broadcaster: GuardianEventBroadcaster
    ) {
        self.configuration = configuration
        self.census = census
        self.sampler = sampler
        self.signaler = signaler
        self.telemetry = telemetry
        self.broadcaster = broadcaster
    }

    /// Production wiring: libproc census, swap sampler, kill(2),
    /// JSONL telemetry + live event broadcast.
    public static var production: GuardianEnvironment {
        let broadcaster = GuardianEventBroadcaster()
        return GuardianEnvironment(
            configuration: GuardianConfiguration(),
            census: LibprocCensus(),
            sampler: SwapPressureSampler(),
            signaler: POSIXSignaler(),
            telemetry: CompositeTelemetrySink(sinks: [
                JSONLTelemetrySink(),
                broadcaster,
            ]),
            broadcaster: broadcaster
        )
    }

    /// Builds the concrete generic guardian from this environment.
    /// The existential providers are opened into the generic coordinator via
    /// type-erasing boxes — call sites stay declarative.
    public func makeGuardian() -> Guardian<AnyCensusProvider, AnyPressureProvider, AnyProcessSignaler> {
        Guardian(
            configuration: configuration,
            census: AnyCensusProvider(census),
            sampler: AnyPressureProvider(sampler),
            signaler: AnyProcessSignaler(signaler),
            telemetry: telemetry
        )
    }
}

// MARK: - Type erasers
//
// Small, single-purpose boxes so the environment can hold existentials while
// the coordinator stays generic (no `any` in its type parameters).

public struct AnyCensusProvider: CensusProvider {
    private let _sampleAll: @Sendable () throws -> [ProcessSample]
    public init(_ base: any CensusProvider) {
        _sampleAll = { try base.sampleAll() }
    }
    public func sampleAll() throws -> [ProcessSample] { try _sampleAll() }
}

public struct AnyPressureProvider: PressureProvider {
    private let _pressure: @Sendable (GuardianConfiguration) -> Pressure
    public init(_ base: any PressureProvider) {
        _pressure = { base.pressure(configuration: $0) }
    }
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
    public func matchesIdentity(_ pid: Int32, sampledStartTime: Date) -> Bool {
        _matchesIdentity(pid, sampledStartTime)
    }
}
