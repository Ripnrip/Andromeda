import Foundation

public enum PowerEvent: Sendable, Equatable {
    case acquired(PowerLease, activeLeaseCount: Int)
    case released(PowerLease, activeLeaseCount: Int)
    case assertionChanged(
        systemSleepPrevented: Bool,
        displaySleepPrevented: Bool,
        activeLeaseCount: Int
    )
}

public protocol PowerEventSink: Sendable {
    func emit(_ event: PowerEvent) async
}

public struct NoopPowerEventSink: PowerEventSink {
    public init() {}
    public func emit(_ event: PowerEvent) async {}
}
