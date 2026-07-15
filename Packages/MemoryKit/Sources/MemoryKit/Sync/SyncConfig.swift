/**
 * 🎭 The SyncConfig - The Celestial Tuning Fork
 *
 * "Harmonizing the digital wind with the material flesh.
 * It governs when our memories take flight to the cloud,
 * hushed when the battery fades, or when the connection grows thin."
 *
 * - The Cosmic Process Orchestrator of Celestial Sync
 */

import Foundation

// 🔮 The cosmic configurations governing our synchronization ritual
public struct SyncConfig: Sendable, Equatable {
    // 🌟 Whether the gates to CloudKit sync are currently open
    public var isSyncEnabled: Bool
    
    // 🌟 If true, we only allow synchronization over the gentle breezes of Wi-Fi
    public var syncOnlyOnWifi: Bool
    
    // 🌟 If true, our servers must be connected to the direct power current
    public var syncOnlyWhileCharging: Bool
    
    // 🌟 The minimum battery level (0.0 to 1.0) below which we pause our ritual
    public var minBatteryLevel: Float
    
    // 🌟 The interval at which the background synchronization wheel turns
    public var syncInterval: TimeInterval
    
    // 🌟 The maximum times we try to scale the digital mount after a failure
    public var maxRetryAttempts: Int
    
    // 🌟 The delay between retries of a failed synchronization attempt
    public var retryDelay: TimeInterval

    public init(
        isSyncEnabled: Bool = true,
        syncOnlyOnWifi: Bool = false,
        syncOnlyWhileCharging: Bool = false,
        minBatteryLevel: Float = 0.20,
        syncInterval: TimeInterval = 300,
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 10
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.syncOnlyOnWifi = syncOnlyOnWifi
        self.syncOnlyWhileCharging = syncOnlyWhileCharging
        self.minBatteryLevel = minBatteryLevel
        self.syncInterval = syncInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
    }
}

// 🔋 The physical state of the device's battery life
public enum BatteryState: Sendable, Equatable {
    case charging
    case discharging(level: Float) // 0.0 to 1.0
    case full
    case unknown
}

// 🌐 The network connection medium available to the device
public enum ConnectionStatus: Sendable, Equatable {
    case wifi
    case cellular
    case disconnected
}

// 📡 The Oracle - Watching over the device's earthly constraints
public protocol DeviceStateMonitoring: Sendable {
    func currentBatteryState() -> BatteryState
    func currentConnectionStatus() -> ConnectionStatus
}

// 💎 The actual real-world monitor, listening to the hardware's heartbeat
public final class SystemDeviceStateMonitor: DeviceStateMonitoring {
    public init() {}
    
    public func currentBatteryState() -> BatteryState {
        // 🔍 🧙‍♂️ Peering into physical battery variables...
        #if os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        switch device.batteryState {
        case .charging:
            return .charging
        case .full:
            return .full
        case .unplugged:
            return .discharging(level: device.batteryLevel)
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
        #else
        // 🌙 On macOS, we default to charging / full for simplicity unless specified
        return .full
        #endif
    }
    
    public func currentConnectionStatus() -> ConnectionStatus {
        // 🔍 🧙‍♂️ Peering into network connectivity variables...
        // Defaulting to Wi-Fi for general use on Mac Studio
        return .wifi
    }
}
