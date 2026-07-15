/**
 * 🎭 The CloudKitSyncEngine - The Cosmic Memory Mirror
 *
 * "One-way lanterns from the local hot store into Apple's private vault.
 * Wi-Fi, charge, and battery gates hush the ritual when the flesh is tired;
 * private and internal thoughts never leave the sanctum."
 *
 * - The Spellbinding Museum Director of Celestial Sync
 */

import Foundation
import SwiftData
import CloudKit

// 🛡️ The local error taxonomy for our sync rituals
public enum SyncError: Error, Sendable, LocalizedError, Equatable {
    case syncDisabled
    case networkDisconnected
    case wifiRequired
    case chargingRequired
    case batteryTooLow(currentLevel: Float)
    case cloudKitError(String)
    case serializationError(String)
    case retryLimitExceeded
    case missingContentHash
    case sealVerificationFailed(String)

    public var isPrerequisiteFailure: Bool {
        switch self {
        case .syncDisabled, .networkDisconnected, .wifiRequired, .chargingRequired, .batteryTooLow:
            return true
        default:
            return false
        }
    }

    /// 🌐 Network / CloudKit transport storms — fail-open rather than poison the hot store.
    public var isNetworkFailure: Bool {
        switch self {
        case .cloudKitError, .retryLimitExceeded:
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .syncDisabled:
            return "🌙 Synchronization gates are closed by user command."
        case .networkDisconnected:
            return "🌩️ The device is stranded in complete offline darkness."
        case .wifiRequired:
            return "🌊 Sync is forbidden on cellular winds; Wi-Fi is required."
        case .chargingRequired:
            return "🔌 Direct power current is required for this sync ritual."
        case .batteryTooLow(let level):
            return "🔋 Battery level (\(Int(level * 100))%) has faded below the safety threshold."
        case .cloudKitError(let message):
            return "☁️ CloudKit database refused our memories: \(message)"
        case .serializationError(let message):
            return "🎨 Record transformation failed: \(message)"
        case .retryLimitExceeded:
            return "💥 Cloud sync attempt limit exceeded — failing open so the hot store stays sovereign."
        case .missingContentHash:
            return "🔏 Record lacks contentHash seal material; refusing celestial export."
        case .sealVerificationFailed(let message):
            return "🔏 AnimaSeal gate refused export: \(message)"
        }
    }
}

/// 🌟 Outcome of a one-way local → CloudKit push (never mutates local from remote).
public enum SyncResult: Sendable, Equatable {
    /// 🎉 Uploaded exportable records; cloaked rows stayed home.
    case completed(uploaded: Int, skippedVisibility: Int)
    /// 🌊 Transport failed after retries — local store untouched (fail-open).
    case failedOpen(attempts: Int, reason: String)
}

// 📡 The protocol abstracting CloudKit Database operations for pure, isolated unit testing magic
public protocol CloudKitDatabase: Sendable {
    func save(_ record: CKRecord) async throws -> CKRecord
    func record(for recordID: CKRecord.ID) async throws -> CKRecord
    func deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID
    func records(
        matching query: CKQuery,
        inZoneWith zoneID: CKRecordZone.ID?,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
}

// 💎 Making Apple's real CKDatabase conform to our mystical protocol
extension CKDatabase: CloudKitDatabase {}

// 🎬 The Star of the Show: Our modern, actor-isolated Synchronization Engine
public actor CloudKitSyncEngine {
    /// 📜 Canonical CloudKit record type for episodic cold replicas (BIN-22 schema gate).
    public static let recordType = "AnimaEpisodicRecord"

    /// 🏠 Canonical package home for MemoryKit (Andromeda mirrors this tree).
    public static let packageHomeMarker = "Packages/MemoryKit"

    // 🌟 The local container holding all our episodic records
    private let modelContainer: ModelContainer

    // 🌟 Actor-isolated ModelContext for database transactions
    private let modelContext: ModelContext

    // 🌟 The database gateway to Apple's private CloudKit vault (private DB only)
    private let ckDatabase: any CloudKitDatabase

    // 🌟 The device state monitor watching physical constraints
    private let deviceMonitor: any DeviceStateMonitoring

    // 🌟 The celestial synchronization settings
    private var syncConfig: SyncConfig

    // 🌟 Optional seal verifier — when set, unsigned / broken chains refuse export (BIN-22 seal gate)
    private let sealVerifier: (@Sendable ([AnimaEpisodicRecordSnapshot]) -> Result<Void, SyncError>)?

    // 🌟 State ledgers to keep our console illuminated
    public private(set) var isSyncingInProgress: Bool = false
    public private(set) var lastSyncDate: Date? = nil
    public private(set) var lastSyncResult: SyncResult? = nil
    /// 🔮 True when the last transport attempt failed open (satellites may be stale).
    public private(set) var isCloudDirty: Bool = false

    public init(
        modelContainer: ModelContainer,
        ckDatabase: any CloudKitDatabase,
        deviceMonitor: any DeviceStateMonitoring,
        syncConfig: SyncConfig = SyncConfig(),
        sealVerifier: (@Sendable ([AnimaEpisodicRecordSnapshot]) -> Result<Void, SyncError>)? = nil
    ) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = false
        self.ckDatabase = ckDatabase
        self.deviceMonitor = deviceMonitor
        self.syncConfig = syncConfig
        self.sealVerifier = sealVerifier
    }

    // 🌟 Dynamic tuning of our cosmic configuration
    public func updateConfig(_ newConfig: SyncConfig) {
        self.syncConfig = newConfig
    }

    // 🌟 Check whether the physical tides allow synchronization to proceed
    private func verifySyncPrerequisites() throws {
        guard syncConfig.isSyncEnabled else {
            throw SyncError.syncDisabled
        }

        let connection = deviceMonitor.currentConnectionStatus()
        guard connection != .disconnected else {
            throw SyncError.networkDisconnected
        }

        if syncConfig.syncOnlyOnWifi && connection == .cellular {
            throw SyncError.wifiRequired
        }

        let battery = deviceMonitor.currentBatteryState()
        switch battery {
        case .charging, .full:
            break
        case .discharging(let level):
            if syncConfig.syncOnlyWhileCharging {
                throw SyncError.chargingRequired
            }
            if level < syncConfig.minBatteryLevel {
                throw SyncError.batteryTooLow(currentLevel: level)
            }
        case .unknown:
            if syncConfig.syncOnlyWhileCharging {
                throw SyncError.chargingRequired
            }
        }
    }

    /// 🔏 Fail-closed gates: missing hash or AnimaSeal refusal must never soft-open.
    private static func isSealOrSchemaFailure(_ error: SyncError) -> Bool {
        switch error {
        case .missingContentHash, .sealVerificationFailed:
            return true
        default:
            return false
        }
    }

    /// 🌟 Execute the one-way local → CloudKit private DB push.
    /// Prerequisite gate failures throw. Network/CloudKit storms fail-open via `SyncResult.failedOpen`.
    @discardableResult
    public func sync() async throws -> SyncResult {
        guard !isSyncingInProgress else {
            print("🌙 ⚠️ Gentle reminder: Synchronization is already in progress.")
            if let last = lastSyncResult {
                return last
            }
            return .failedOpen(attempts: 0, reason: "sync already in progress")
        }

        isSyncingInProgress = true
        defer { isSyncingInProgress = false }

        print("🌐 ✨ ONE-WAY SYNCHRONIZATION AWAKENS! (local → CloudKit private DB)")

        try verifySyncPrerequisites()

        var attempts = 0
        var lastTransportReason = "unknown transport storm"

        while attempts < syncConfig.maxRetryAttempts {
            do {
                try verifySyncPrerequisites()

                let outcome = try await performOneWayPushRitual()
                lastSyncDate = Date()
                lastSyncResult = outcome
                isCloudDirty = false
                print("🎉 ✨ SYNCHRONIZATION MASTERPIECE COMPLETE! \(outcome)")
                return outcome
            } catch let error as SyncError where error.isPrerequisiteFailure {
                throw error
            } catch let error as SyncError where Self.isSealOrSchemaFailure(error) {
                throw error
            } catch {
                attempts += 1
                lastTransportReason = error.localizedDescription
                print("🌩️ Temporary setback on sync attempt \(attempts)/\(syncConfig.maxRetryAttempts): \(lastTransportReason)")

                if attempts >= syncConfig.maxRetryAttempts {
                    print("💥 😭 SYNCHRONIZATION TRANSPORT HALTED — FAILING OPEN! Hot store remains sovereign.")
                    let open = SyncResult.failedOpen(attempts: attempts, reason: lastTransportReason)
                    lastSyncResult = open
                    isCloudDirty = true
                    return open
                }

                try await Task.sleep(nanoseconds: UInt64(syncConfig.retryDelay * 1_000_000_000))
            }
        }

        let open = SyncResult.failedOpen(attempts: attempts, reason: lastTransportReason)
        lastSyncResult = open
        isCloudDirty = true
        return open
    }

    // 🌟 One-way push: exportable local records → private CloudKit. Never pull/merge remote → local.
    private func performOneWayPushRitual() async throws -> SyncResult {
        print("🎪 📦 Commencing one-way push ritual (no remote→local merge)...")

        let localRecords = try modelContext.fetch(FetchDescriptor<AnimaEpisodicRecord>())
        let snapshots = localRecords.map(\.toSnapshot)

        if let sealVerifier {
            switch sealVerifier(snapshots) {
            case .success:
                break
            case .failure(let sealError):
                throw sealError
            }
        }

        var skippedVisibility = 0
        var candidates: [AnimaEpisodicRecord] = []

        for local in localRecords {
            guard VisibilityFilter.isAllowed(
                visibility: local.visibility,
                target: .externalReplication
            ) else {
                skippedVisibility += 1
                print("🛡️ Cloaked memory stays home (\(local.visibility)): \(local.contentHash)")
                continue
            }

            guard !local.contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SyncError.missingContentHash
            }

            candidates.append(local)
        }

        var uploaded = 0
        for local in candidates {
            let recordID = CKRecord.ID(recordName: local.id.uuidString)
            let ckRecord = await loadOrCreateRecord(recordID: recordID)
            populate(ckRecord, from: local)

            do {
                _ = try await ckDatabase.save(ckRecord)
                uploaded += 1
                print("🎉 Successfully uploaded local memory to cloud: \(local.contentHash)")
            } catch {
                throw SyncError.cloudKitError("Failed to save local memory: \(error.localizedDescription)")
            }
        }

        return .completed(uploaded: uploaded, skippedVisibility: skippedVisibility)
    }

    private func loadOrCreateRecord(recordID: CKRecord.ID) async -> CKRecord {
        do {
            return try await ckDatabase.record(for: recordID)
        } catch {
            return CKRecord(recordType: Self.recordType, recordID: recordID)
        }
    }

    private func populate(_ ckRecord: CKRecord, from local: AnimaEpisodicRecord) {
        ckRecord["contentHash"] = local.contentHash as CKRecordValue
        ckRecord["createdAt"] = local.createdAt as CKRecordValue
        ckRecord["project"] = local.project as CKRecordValue
        ckRecord["agent"] = local.agent as CKRecordValue
        ckRecord["narrative"] = local.narrative as CKRecordValue
        ckRecord["visibility"] = local.visibility as CKRecordValue
        ckRecord["provenance"] = local.provenance as CKRecordValue
        ckRecord["tags"] = local.tags as CKRecordValue
        if let matPath = local.materializedPath {
            ckRecord["materializedPath"] = matPath as CKRecordValue
        }
    }
}
