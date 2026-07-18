import Foundation

/// Latency / render budgets for the floating HUD (BIN-59).
///
/// Targets keep interactions feeling local: sub-frame work for chrome,
/// hard caps so no click waits "seconds for a load."
public enum HUDPerformanceBudget: Sendable {
    /// Target wall time for a single HUD body layout pass (one display frame @ 60 Hz).
    public static let renderFrameMilliseconds: Double = 16

    /// Maximum acceptable time to expand the Ask AI field after a click.
    public static let expandInteractionMilliseconds: Double = 50

    /// Maximum acceptable time to settle a drag/snap origin update.
    public static let snapSettleMilliseconds: Double = 8

    /// Maximum acceptable time for a local `memory.*` / search route parse.
    public static let searchRouteMilliseconds: Double = 2

    /// Hard ceiling — anything above this is a failed budget (never "seconds").
    public static let hardCeilingMilliseconds: Double = 250
}

/// Result of a timed HUD operation against a budget.
public struct HUDTimingSample: Equatable, Sendable {
    public var operation: String
    public var elapsedMilliseconds: Double
    public var budgetMilliseconds: Double

    public init(operation: String, elapsedMilliseconds: Double, budgetMilliseconds: Double) {
        self.operation = operation
        self.elapsedMilliseconds = elapsedMilliseconds
        self.budgetMilliseconds = budgetMilliseconds
    }

    /// Whether the sample met its budget.
    public var isWithinBudget: Bool {
        elapsedMilliseconds <= budgetMilliseconds
    }

    /// Whether the sample breached the hard ceiling (always a failure).
    public var breachedHardCeiling: Bool {
        elapsedMilliseconds > HUDPerformanceBudget.hardCeilingMilliseconds
    }
}

/// Lightweight stopwatch for HUD performance proofs (no Instruments dependency).
public struct HUDStopwatch: Sendable {
    private let startedAt: ContinuousClock.Instant

    public init(clock: ContinuousClock = ContinuousClock()) {
        self.startedAt = clock.now
    }

    /// Elapsed milliseconds since construction.
    public func elapsedMilliseconds(clock: ContinuousClock = ContinuousClock()) -> Double {
        let duration = startedAt.duration(to: clock.now)
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return seconds * 1_000
    }

    /// Measure a synchronous closure and return a timing sample.
    public static func measure(
        operation: String,
        budgetMilliseconds: Double,
        work: () -> Void
    ) -> HUDTimingSample {
        let watch = HUDStopwatch()
        work()
        return HUDTimingSample(
            operation: operation,
            elapsedMilliseconds: watch.elapsedMilliseconds(),
            budgetMilliseconds: budgetMilliseconds
        )
    }
}
