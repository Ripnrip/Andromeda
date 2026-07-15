/**
 * 🎭 The CloudKitSyncTests - The Celestial Trial Grounds
 *
 * "Subjecting our memory synchronization ritual to the trials of the physical realm.
 * We summon digital storms, drain virtual batteries, sever ethereal connections,
 * and witness the glorious resilience of the CloudKitSyncEngine as it perseveres."
 *
 * - The Theatrical Quality Assurance Virtuoso of Celestial Sync
 */

import Testing
import Foundation
import SwiftData
import CloudKit
@testable import MemoryKit

// 📡 The Thread-Safe Oracle's Mirror - Mocking the physical device state as a thread-safe actor
public final class MockDeviceStateMonitor: DeviceStateMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _batteryState: BatteryState = .full
    private var _connectionStatus: ConnectionStatus = .wifi
    
    public init() {}
    
    public func setBatteryState(_ state: BatteryState) {
        lock.lock()
        defer { lock.unlock() }
        _batteryState = state
    }
    
    public func setConnectionStatus(_ status: ConnectionStatus) {
        lock.lock()
        defer { lock.unlock() }
        _connectionStatus = status
    }
    
    public func currentBatteryState() -> BatteryState {
        lock.lock()
        defer { lock.unlock() }
        return _batteryState
    }
    
    public func currentConnectionStatus() -> ConnectionStatus {
        lock.lock()
        defer { lock.unlock() }
        return _connectionStatus
    }
}

// ☁️ The Thread-Safe Celestial Vault - Mocking CloudKit Database as a thread-safe actor
public actor MockCloudKitDatabase: CloudKitDatabase {
    private var savedRecords: [CKRecord.ID: CKRecord] = [:]
    private var savedRecordsHistory: [CKRecord] = []
    
    private var recordsToReturn: [CKRecord] = []
    private var saveErrorToThrow: Error?
    private var recordsErrorToThrow: Error?
    
    // 🎭 Keep track of attempts for validating recovery rituals
    public private(set) var recordsQueryAttempts: Int = 0
    public private(set) var saveAttempts: Int = 0
    
    public init() {}
    
    public func setRecordsToReturn(_ records: [CKRecord]) {
        self.recordsToReturn = records
    }
    
    public func setSaveErrorToThrow(_ error: Error?) {
        self.saveErrorToThrow = error
    }
    
    public func setRecordsErrorToThrow(_ error: Error?) {
        self.recordsErrorToThrow = error
    }
    
    public func save(_ record: CKRecord) async throws -> CKRecord {
        saveAttempts += 1
        if let error = saveErrorToThrow {
            throw error
        }
        savedRecords[record.recordID] = record
        savedRecordsHistory.append(record)
        return record
    }
    
    public func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        guard let record = savedRecords[recordID] else {
            throw CKError(.unknownItem)
        }
        return record
    }
    
    public func deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID {
        savedRecords.removeValue(forKey: recordID)
        return recordID
    }
    
    public func records(
        matching query: CKQuery,
        inZoneWith zoneID: CKRecordZone.ID?,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        recordsQueryAttempts += 1
        if let error = recordsErrorToThrow {
            throw error
        }
        let matchResults = recordsToReturn.map { record in
            (record.recordID, Result<CKRecord, any Error>.success(record))
        }
        return (matchResults, nil)
    }
    
    public func getSavedRecords() -> [CKRecord] {
        return Array(savedRecords.values)
    }
    
    public func getSavedRecordsHistory() -> [CKRecord] {
        return savedRecordsHistory
    }
    
    public func clearAttempts() {
        recordsQueryAttempts = 0
        saveAttempts = 0
    }
}

// 🧪 The Grand Suite of Synchronization Trials
@Suite("CloudKit Synchronization Ritual Trials")
struct CloudKitSyncTests {
    
    // 🌟 Helper to summon an isolated in-memory SwiftData container
    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([AnimaEpisodicRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
    
    @Test("Trial 1: Successful cold replication dual sync (Pull and Push)")
    func testSuccessfulSync() async throws {
        // 🧪 GIVEN: An isolated model container with 1 local memory, and 1 remote memory in CloudKit
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        
        let localRecord = AnimaEpisodicRecord(
            id: UUID(),
            contentHash: "local-sha256",
            createdAt: Date().addingTimeInterval(-3600), // Created 1 hour ago
            project: "Anima Awakening",
            agent: "claude-code",
            narrative: "Local wisdom must flow upstream.",
            visibility: "private",
            provenance: "test-host"
        )
        context.insert(localRecord)
        try context.save()
        
        let remoteID = UUID()
        let remoteRecord = CKRecord(recordType: "AnimaEpisodicRecord", recordID: CKRecord.ID(recordName: remoteID.uuidString))
        remoteRecord["contentHash"] = "remote-sha256" as CKRecordValue
        remoteRecord["createdAt"] = Date() as CKRecordValue // Created just now
        remoteRecord["project"] = "Andromeda Rise" as CKRecordValue
        remoteRecord["agent"] = "codex" as CKRecordValue
        remoteRecord["narrative"] = "Remote stars shine bright." as CKRecordValue
        remoteRecord["visibility"] = "public" as CKRecordValue
        remoteRecord["provenance"] = "remote-host" as CKRecordValue
        remoteRecord["tags"] = ["star", "sky"] as CKRecordValue
        
        let mockCK = MockCloudKitDatabase()
        await mockCK.setRecordsToReturn([remoteRecord])
        
        let mockDevice = MockDeviceStateMonitor()
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice
        )
        
        // 🧪 WHEN: The synchronization ritual commences
        try await engine.sync()
        
        // 🧪 THEN: Both local and remote databases are fully synchronized
        let finalLocalRecords = try context.fetch(FetchDescriptor<AnimaEpisodicRecord>())
        #expect(finalLocalRecords.count == 2)
        
        let finalRemoteRecords = await mockCK.getSavedRecords()
        #expect(finalRemoteRecords.count == 1) // The 1 local record got saved to remote
        #expect(finalRemoteRecords.first?.recordID.recordName == localRecord.id.uuidString)
    }
    
    @Test("Trial 2: Sync is blocked when celestial configurations are disabled")
    func testSyncDisabled() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        let mockDevice = MockDeviceStateMonitor()
        
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(isSyncEnabled: false)
        )
        
        // 🧪 WHEN / THEN: Expect throwing syncDisabled error
        await #expect(throws: SyncError.syncDisabled) {
            try await engine.sync()
        }
    }
    
    @Test("Trial 3: Throttling works gracefully when physical battery is fading")
    func testBatteryLowThrottling() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        let mockDevice = MockDeviceStateMonitor()
        await mockDevice.setBatteryState(.discharging(level: 0.10)) // 10% battery
        
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(minBatteryLevel: 0.20)
        )
        
        // 🧪 WHEN / THEN: Expect throwing batteryTooLow error
        await #expect(throws: SyncError.batteryTooLow(currentLevel: 0.10)) {
            try await engine.sync()
        }
    }
    
    @Test("Trial 4: Active charging overrides low battery constraints")
    func testBatteryChargingOverridesLowBattery() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        let mockDevice = MockDeviceStateMonitor()
        await mockDevice.setBatteryState(.charging) // Charging!
        
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(minBatteryLevel: 0.20)
        )
        
        // 🧪 WHEN / THEN: Proceeds and completes with no error
        try await engine.sync()
        #expect(await engine.lastSyncDate != nil)
    }
    
    @Test("Trial 5: Wi-Fi restriction holds fast over cellular winds")
    func testWifiRestrictionOnCellular() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        let mockDevice = MockDeviceStateMonitor()
        await mockDevice.setConnectionStatus(.cellular)
        
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(syncOnlyOnWifi: true)
        )
        
        // 🧪 WHEN / THEN: Expect throwing wifiRequired error
        await #expect(throws: SyncError.wifiRequired) {
            try await engine.sync()
        }
    }
    
    @Test("Trial 6: Stranded in offline darkness throws network disconnected")
    func testOfflineDarkness() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        let mockDevice = MockDeviceStateMonitor()
        await mockDevice.setConnectionStatus(.disconnected)
        
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice
        )
        
        // 🧪 WHEN / THEN: Expect throwing networkDisconnected error
        await #expect(throws: SyncError.networkDisconnected) {
            try await engine.sync()
        }
    }
    
    @Test("Trial 7: Interrupted connection recovers seamlessly through a retry ritual")
    func testTransientNetworkFailureRecovery() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        
        // Configure to throw an error initially on querying
        await mockCK.setRecordsErrorToThrow(CKError(.networkFailure))
        
        let mockDevice = MockDeviceStateMonitor()
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(
                maxRetryAttempts: 3,
                retryDelay: 0.05 // Tiny delay for fast testing
            )
        )
        
        // We will clear the error in the background or after 1 attempt
        // To simulate a recovery, we can use a custom Task to clear the mock error after a brief sleep
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            await mockCK.setRecordsErrorToThrow(nil) // Clear error so retry succeeds!
        }
        
        // 🧪 WHEN: Commencing sync
        try await engine.sync()
        
        // 🧪 THEN: The ritual succeeds after a retry
        #expect(await mockCK.recordsQueryAttempts == 2)
        #expect(await engine.lastSyncDate != nil)
    }
    
    @Test("Trial 8: Severe connection storm exceeding retry limits fails gracefully")
    func testSyncRetryLimitExceeded() async throws {
        let container = try createTestModelContainer()
        let mockCK = MockCloudKitDatabase()
        await mockCK.setRecordsErrorToThrow(CKError(.networkFailure)) // Permanent error
        
        let mockDevice = MockDeviceStateMonitor()
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: mockDevice,
            syncConfig: SyncConfig(
                maxRetryAttempts: 2,
                retryDelay: 0.01
            )
        )
        
        // 🧪 WHEN / THEN: Exceeds retries and throws retryLimitExceeded
        await #expect(throws: SyncError.retryLimitExceeded) {
            try await engine.sync()
        }
        #expect(await mockCK.recordsQueryAttempts == 2)
    }
}
