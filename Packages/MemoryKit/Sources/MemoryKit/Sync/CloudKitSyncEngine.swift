/**
 * 🎭 The CloudKitSyncEngine - The Cosmic Memory Mirror
 *
 * "Reflecting our temporal thoughts in the celestial vault.
 * It sweeps across local SwiftData records and mirrors them
 * in the secure sky of Apple's CloudKit private database,
 * ensuring our satellites sing in harmonious chorus."
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
    
    public var isPrerequisiteFailure: Bool {
        switch self {
        case .syncDisabled, .networkDisconnected, .wifiRequired, .chargingRequired, .batteryTooLow:
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
            return "💥 Cloud sync attempt limit exceeded. The show cannot go on."
        }
    }
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
    // 🌟 The local container holding all our episodic records
    private let modelContainer: ModelContainer
    
    // 🌟 Actor-isolated ModelContext for database transactions
    private let modelContext: ModelContext
    
    // 🌟 The database gateway to Apple's private CloudKit vault
    private let ckDatabase: any CloudKitDatabase
    
    // 🌟 The device state monitor watching physical constraints
    private let deviceMonitor: any DeviceStateMonitoring
    
    // 🌟 The celestial synchronization settings
    private var syncConfig: SyncConfig
    
    // 🌟 State ledgers to keep our console illuminated
    public private(set) var isSyncingInProgress: Bool = false
    public private(set) var lastSyncDate: Date? = nil
    
    public init(
        modelContainer: ModelContainer,
        ckDatabase: any CloudKitDatabase,
        deviceMonitor: any DeviceStateMonitoring,
        syncConfig: SyncConfig = SyncConfig()
    ) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = false
        self.ckDatabase = ckDatabase
        self.deviceMonitor = deviceMonitor
        self.syncConfig = syncConfig
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
            // 🔋 Rich current flows freely, no battery constraints can hold us!
            break
        case .discharging(let level):
            if syncConfig.syncOnlyWhileCharging {
                throw SyncError.chargingRequired
            }
            if level < syncConfig.minBatteryLevel {
                throw SyncError.batteryTooLow(currentLevel: level)
            }
        case .unknown:
            // 🔮 In the dark about battery state, we play it safe or proceed cautiously
            if syncConfig.syncOnlyWhileCharging {
                throw SyncError.chargingRequired
            }
        }
    }
    
    // 🌟 Execute the celestial sync ritual, uploading and downloading memories
    public func sync() async throws {
        guard !isSyncingInProgress else {
            print("🌙 ⚠️ Gentle reminder: Synchronization is already in progress.")
            return
        }
        
        isSyncingInProgress = true
        defer { isSyncingInProgress = false }
        
        print("🌐 ✨ SYNCHRONIZATION AWAKENS!")
        
        // 🔮 Validate prerequisites immediately before entering the retry cycle
        try verifySyncPrerequisites()
        
        var attempts = 0
        while attempts < syncConfig.maxRetryAttempts {
            do {
                // Check again in case state shifted during sleep
                try verifySyncPrerequisites()
                
                try await performSyncRitual()
                lastSyncDate = Date()
                print("🎉 ✨ SYNCHRONIZATION MASTERPIECE COMPLETE!")
                return
            } catch let error as SyncError where error.isPrerequisiteFailure {
                // If it is a prerequisite/static sync error, throw immediately
                throw error
            } catch {
                attempts += 1
                print("🌩️ Temporary setback on sync attempt \(attempts)/\(syncConfig.maxRetryAttempts): \(error.localizedDescription)")
                
                if attempts >= syncConfig.maxRetryAttempts {
                    print("💥 😭 SYNCHRONIZATION TEMPORARILY HALTED! Retry limit reached.")
                    throw SyncError.retryLimitExceeded
                }
                
                // Wait for the retry delay before next attempt
                try await Task.sleep(nanoseconds: UInt64(syncConfig.retryDelay * 1_000_000_000))
            }
        }
    }
    
    // 🌟 Perform the actual record pulling and pushing magic
    private func performSyncRitual() async throws {
        print("🎪 📦 Commencing the dual pull-push sync ritual...")
        
        // 🔮 Pull Phase: Fetch remote CloudKit records
        let query = CKQuery(recordType: "AnimaEpisodicRecord", predicate: NSPredicate(value: true))
        
        let matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)]
        do {
            let response = try await ckDatabase.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: nil,
                resultsLimit: CKQueryOperation.maximumResults
            )
            matchResults = response.matchResults
        } catch {
            throw SyncError.cloudKitError("Failed to fetch remote memories: \(error.localizedDescription)")
        }
        
        var remoteRecordsByID: [CKRecord.ID: CKRecord] = [:]
        for (recordID, result) in matchResults {
            switch result {
            case .success(let record):
                remoteRecordsByID[recordID] = record
            case .failure(let failure):
                print("🌙 ⚠️ Gentle reminder: Skipping damaged memory record \(recordID.recordName): \(failure.localizedDescription)")
            }
        }
        
        // Update local SwiftData context with remote records
        for (_, remoteRecord) in remoteRecordsByID {
            guard let contentHash = remoteRecord["contentHash"] as? String,
                  let createdAt = remoteRecord["createdAt"] as? Date,
                  let project = remoteRecord["project"] as? String,
                  let agent = remoteRecord["agent"] as? String,
                  let narrative = remoteRecord["narrative"] as? String,
                  let visibility = remoteRecord["visibility"] as? String,
                  let provenance = remoteRecord["provenance"] as? String,
                  let tags = remoteRecord["tags"] as? [String] else {
                print("🌙 ⚠️ Gentle reminder: Remote record holds un-transmutable content. Skipping.")
                continue
            }
            
            let materializedPath = remoteRecord["materializedPath"] as? String
            let idString = remoteRecord.recordID.recordName
            guard let recordID = UUID(uuidString: idString) else { continue }
            
            // Check if local record exists
            let localDescriptor = FetchDescriptor<AnimaEpisodicRecord>(
                predicate: #Predicate { $0.id == recordID }
            )
            let localMatch = try modelContext.fetch(localDescriptor).first
            
            if let local = localMatch {
                // Conflict resolution: Remote newer wins
                if createdAt > local.createdAt {
                    local.contentHash = contentHash
                    local.createdAt = createdAt
                    local.project = project
                    local.agent = agent
                    local.narrative = narrative
                    local.visibility = visibility
                    local.provenance = provenance
                    local.tags = tags
                    local.materializedPath = materializedPath
                    print("💎 Crystallized remote update for local memory: \(contentHash)")
                }
            } else {
                // Insert brand new remote record
                let newRecord = AnimaEpisodicRecord(
                    id: recordID,
                    contentHash: contentHash,
                    createdAt: createdAt,
                    project: project,
                    agent: agent,
                    narrative: narrative,
                    visibility: visibility,
                    provenance: provenance,
                    tags: tags,
                    materializedPath: materializedPath
                )
                modelContext.insert(newRecord)
                print("✨ Consecrated new remote memory locally: \(contentHash)")
            }
        }
        
        // Save local pull-updates
        try modelContext.save()
        
        // 🔮 Push Phase: Query all local records and upload new or updated ones
        let localRecords = try modelContext.fetch(FetchDescriptor<AnimaEpisodicRecord>())
        
        for local in localRecords {
            let recordID = CKRecord.ID(recordName: local.id.uuidString)
            let remoteMatch = remoteRecordsByID[recordID]
            
            let shouldUpload: Bool
            if let remote = remoteMatch {
                if let remoteCreatedAt = remote["createdAt"] as? Date {
                    shouldUpload = local.createdAt > remoteCreatedAt
                } else {
                    shouldUpload = true
                }
            } else {
                shouldUpload = true
            }
            
            if shouldUpload {
                let ckRecord: CKRecord
                if let existing = remoteMatch {
                    ckRecord = existing
                } else {
                    ckRecord = CKRecord(recordType: "AnimaEpisodicRecord", recordID: recordID)
                }
                
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
                
                do {
                    _ = try await ckDatabase.save(ckRecord)
                    print("🎉 Successfully uploaded local memory to cloud: \(local.contentHash)")
                } catch {
                    throw SyncError.cloudKitError("Failed to save local memory: \(error.localizedDescription)")
                }
            }
        }
    }
}
