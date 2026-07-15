/**
 * 🎭 The SyncConfig - The Celestial Tuning Fork
 *
 * "Harmonizing the digital wind with the material flesh.
 * It governs when our memories take flight to the cloud,
 * hushed when the battery fades, or when the connection grows thin.
 * Cold sync is one-way: local hot store → CloudKit private DB only."
 *
 * - The Cosmic Process Orchestrator of Celestial Sync
 */

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// 🔮 The cosmic configurations governing our synchronization ritual
public struct SyncConfig: Sendable, Equatable {
    public var isSyncEnabled: Bool
    public var syncOnlyOnWifi: Bool
    public var syncOnlyWhileCharging: Bool
    public var minBatteryLevel: Float
    public var syncInterval: TimeInterval
    public var maxRetryAttempts: Int
    public var retryDelay: TimeInterval

    /// 🧭 Conflict / direction policy — cold sync is always local → cloud (never remote→local merge).
    public var direction: SyncDirection

    /// 🏠 Package-home gate: expects MemoryKit under `Packages/MemoryKit` (multibrain canonical; Andromeda mirrors).
    public var expectedPackageHomeMarker: String

    public init(
        isSyncEnabled: Bool = true,
        syncOnlyOnWifi: Bool = true,
        syncOnlyWhileCharging: Bool = false,
        minBatteryLevel: Float = 0.20,
        syncInterval: TimeInterval = 300,
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 10,
        direction: SyncDirection = .localToCloudKitPrivateDB,
        expectedPackageHomeMarker: String = CloudKitSyncEngine.packageHomeMarker
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.syncOnlyOnWifi = syncOnlyOnWifi
        self.syncOnlyWhileCharging = syncOnlyWhileCharging
        self.minBatteryLevel = minBatteryLevel
        self.syncInterval = syncInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.direction = direction
        self.expectedPackageHomeMarker = expectedPackageHomeMarker
    }

    /// 🧪 Test-friendly defaults (Wi-Fi gate off so unit trials control connection explicitly).
    public static func testing(
        isSyncEnabled: Bool = true,
        syncOnlyOnWifi: Bool = false,
        syncOnlyWhileCharging: Bool = false,
        minBatteryLevel: Float = 0.20,
        maxRetryAttempts: Int = 3,
        retryDelay: TimeInterval = 0.05
    ) -> SyncConfig {
        SyncConfig(
            isSyncEnabled: isSyncEnabled,
            syncOnlyOnWifi: syncOnlyOnWifi,
            syncOnlyWhileCharging: syncOnlyWhileCharging,
            minBatteryLevel: minBatteryLevel,
            maxRetryAttempts: maxRetryAttempts,
            retryDelay: retryDelay
        )
    }
}

/// 🧭 Directional policy for cold sync (BIN-22 conflict gate).
public enum SyncDirection: String, Sendable, Equatable {
    /// One-way local hot store → CloudKit private database. Local always wins; no pull merge.
    case localToCloudKitPrivateDB
}

public enum BatteryState: Sendable, Equatable {
    case charging
    case discharging(level: Float)
    case full
    case unknown
}

public enum ConnectionStatus: Sendable, Equatable {
    case wifi
    case cellular
    case disconnected
}

public protocol DeviceStateMonitoring: Sendable {
    func currentBatteryState() -> BatteryState
    func currentConnectionStatus() -> ConnectionStatus
}

public final class SystemDeviceStateMonitor: DeviceStateMonitoring {
    public init() {}

    public func currentBatteryState() -> BatteryState {
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
        return .full
        #endif
    }

    public func currentConnectionStatus() -> ConnectionStatus {
        return .wifi
    }
}
