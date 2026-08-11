import Foundation

public protocol PowerAssertionBackend: Sendable {
    func apply(
        preventSystemSleep: Bool,
        preventDisplaySleep: Bool,
        reason: String
    ) async

    func clear() async
}

/// Swift-native macOS implementation backed by ProcessInfo activity assertions.
///
/// The backend maintains one aggregate macOS activity. PowerAssertionManager
/// owns the individual logical leases and recomputes the aggregate state.
public actor ProcessInfoPowerAssertionBackend: PowerAssertionBackend {
    private nonisolated(unsafe) var activity: NSObjectProtocol?

    public init() {}

    public func apply(
        preventSystemSleep: Bool,
        preventDisplaySleep: Bool,
        reason: String
    ) async {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }

        var options: ProcessInfo.ActivityOptions = [.background]

        if preventSystemSleep {
            options.insert(.idleSystemSleepDisabled)
        }

        if preventDisplaySleep {
            options.insert(.idleDisplaySleepDisabled)
        }

        guard preventSystemSleep || preventDisplaySleep else {
            return
        }

        activity = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: reason
        )
    }

    public func clear() async {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    deinit {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
}
