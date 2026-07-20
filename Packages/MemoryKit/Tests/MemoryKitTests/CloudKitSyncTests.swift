/**
 * 🎭 The CloudKitSyncTests - The Celestial Trial Grounds
 *
 * "Subjecting our one-way memory push to the trials of the physical realm.
 * We summon digital storms, drain virtual batteries, cloak private thoughts,
 * and prove private/internal never leave — while network storms fail open."
 *
 * - The Theatrical Quality Assurance Virtuoso of Celestial Sync
 */

import Testing
import Foundation
import SwiftData
import CloudKit
@testable import MemoryKit

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

public actor MockCloudKitDatabase: CloudKitDatabase {
    private var savedRecords: [CKRecord.ID: CKRecord] = [:]
    private var savedRecordsHistory: [CKRecord] = []

    private var recordsToReturn: [CKRecord] = []
    private var saveErrorToThrow: Error?
    private var recordsErrorToThrow: Error?
    private var recordForErrorToThrow: Error?
    private var saveFailuresBeforeSuccess: Int?

    public private(set) var recordsQueryAttempts: Int = 0
    public private(set) var saveAttempts: Int = 0
    public private(set) var recordForAttempts: Int = 0

    public init() {}

    public func setRecordsToReturn(_ records: [CKRecord]) {
        self.recordsToReturn = records
        for record in records {
            savedRecords[record.recordID] = record
        }
    }

    public func setSaveErrorToThrow(_ error: Error?) {
        self.saveErrorToThrow = error
    }

    public func setSaveFailuresBeforeSuccess(_ count: Int?) {
        self.saveFailuresBeforeSuccess = count
    }

    public func setRecordsErrorToThrow(_ error: Error?) {
        self.recordsErrorToThrow = error
    }

    public func setRecordForErrorToThrow(_ error: Error?) {
        self.recordForErrorToThrow = error
    }

    public func save(_ record: CKRecord) async throws -> CKRecord {
        saveAttempts += 1
        if let remaining = saveFailuresBeforeSuccess {
            if remaining > 0 {
                saveFailuresBeforeSuccess = remaining - 1
                throw saveErrorToThrow ?? CKError(.networkFailure)
            }
        } else if let error = saveErrorToThrow {
            throw error
        }
        savedRecords[record.recordID] = record
        savedRecordsHistory.append(record)
        return record
    }

    public func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        recordForAttempts += 1
        if let error = recordForErrorToThrow {
            throw error
        }
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
        Array(savedRecords.values)
    }

    public func getSavedRecordsHistory() -> [CKRecord] {
        savedRecordsHistory
    }

    public func clearAttempts() {
        recordsQueryAttempts = 0
        saveAttempts = 0
        recordForAttempts = 0
    }
}

@Suite("CloudKit Synchronization Ritual Trials")
struct CloudKitSyncTests {

    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([AnimaEpisodicRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func insert(
        into context: ModelContext,
        hash: String,
        visibility: String,
        narrative: String = "wisdom",
        id: UUID = UUID()
    ) throws -> AnimaEpisodicRecord {
        let record = AnimaEpisodicRecord(
            id: id,
            contentHash: hash,
            createdAt: Date(),
            project: "Anima Awakening",
            agent: "claude-code",
            narrative: narrative,
            visibility: visibility,
            provenance: "test-host"
        )
        context.insert(record)
        try context.save()
        return record
    }

    @Test("Trial 1: One-way local→cloud push uploads public/friends only")
    func testOneWayPushExportsAllowedVisibility() async throws {
        let container = try createTestModelContainer()
        let context = ModelContext(container)

        let localPublic = try insert(into: context, hash: "local-public-sha", visibility: "public")

        let remoteOnlyID = UUID()
        let remoteRecord = CKRecord(
            recordType: CloudKitSyncEngine.recordType,
            recordID: CKRecord.ID(recordName: remoteOnlyID.uuidString)
        )
        remoteRecord["contentHash"] = "remote-sha256" as CKRecordValue
        remoteRecord["createdAt"] = Date() as CKRecordValue
        remoteRecord["project"] = "Andromeda Rise" as CKRecordValue
        remoteRecord["agent"] = "codex" as CKRecordValue
        remoteRecord["narrative"] = "Remote stars shine bright." as CKRecordValue
        remoteRecord["visibility"] = "public" as CKRecordValue
        remoteRecord["provenance"] = "remote-host" as CKRecordValue
        remoteRecord["tags"] = ["star", "sky"] as CKRecordValue

        let mockCK = MockCloudKitDatabase()
        await mockCK.setRecordsToReturn([remoteRecord])

        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing()
        )

        let result = try await engine.sync()

        let finalLocalRecords = try context.fetch(FetchDescriptor<AnimaEpisodicRecord>())
        #expect(finalLocalRecords.count == 1)
        #expect(finalLocalRecords.first?.id == localPublic.id)
        #expect(result == .completed(uploaded: 1, skippedVisibility: 0))

        let history = await mockCK.getSavedRecordsHistory()
        #expect(history.count == 1)
        #expect(history.first?.recordID.recordName == localPublic.id.uuidString)

        let remoteStillInMock = await mockCK.getSavedRecords().contains {
            $0.recordID.recordName == remoteOnlyID.uuidString
        }
        #expect(remoteStillInMock)
        #expect(await mockCK.recordsQueryAttempts == 0)
    }

    @Test("Trial 1b: private and internal NEVER export to CloudKit")
    func testPrivateInternalNeverExport() async throws {
        let container = try createTestModelContainer()
        let context = ModelContext(container)

        _ = try insert(into: context, hash: "priv-hash", visibility: "private")
        _ = try insert(into: context, hash: "int-hash", visibility: "internal")
        let friends = try insert(into: context, hash: "friends-hash", visibility: "friends")

        let mockCK = MockCloudKitDatabase()
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing()
        )

        let result = try await engine.sync()
        #expect(result == .completed(uploaded: 1, skippedVisibility: 2))

        let history = await mockCK.getSavedRecordsHistory()
        #expect(history.count == 1)
        #expect(history.first?.recordID.recordName == friends.id.uuidString)
        #expect(history.first?["visibility"] as? String == "friends")

        #expect(VisibilityFilter.isAllowed(visibility: "private", target: .externalReplication) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "internal", target: .externalReplication) == false)
        #expect(VisibilityFilter.isAllowed(visibility: "public", target: .externalReplication) == true)
        #expect(VisibilityFilter.isAllowed(visibility: "friends", target: .externalReplication) == true)
    }

    @Test("Trial 2: Sync is blocked when celestial configurations are disabled")
    func testSyncDisabled() async throws {
        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing(isSyncEnabled: false)
        )

        await #expect(throws: SyncError.syncDisabled) {
            try await engine.sync()
        }
    }

    @Test("Trial 3: Throttling works gracefully when physical battery is fading")
    func testBatteryLowThrottling() async throws {
        let mockDevice = MockDeviceStateMonitor()
        mockDevice.setBatteryState(.discharging(level: 0.10))

        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: mockDevice,
            syncConfig: .testing(minBatteryLevel: 0.20)
        )

        await #expect(throws: SyncError.batteryTooLow(currentLevel: 0.10)) {
            try await engine.sync()
        }
    }

    @Test("Trial 4: Active charging overrides low battery constraints")
    func testBatteryChargingOverridesLowBattery() async throws {
        let mockDevice = MockDeviceStateMonitor()
        mockDevice.setBatteryState(.charging)

        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: mockDevice,
            syncConfig: .testing(minBatteryLevel: 0.20)
        )

        let result = try await engine.sync()
        #expect(result == .completed(uploaded: 0, skippedVisibility: 0))
        #expect(await engine.lastSyncDate != nil)
    }

    @Test("Trial 5: Wi-Fi restriction holds fast over cellular winds")
    func testWifiRestrictionOnCellular() async throws {
        let mockDevice = MockDeviceStateMonitor()
        mockDevice.setConnectionStatus(.cellular)

        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: mockDevice,
            syncConfig: .testing(syncOnlyOnWifi: true)
        )

        await #expect(throws: SyncError.wifiRequired) {
            try await engine.sync()
        }
    }

    @Test("Trial 6: Stranded in offline darkness throws network disconnected")
    func testOfflineDarkness() async throws {
        let mockDevice = MockDeviceStateMonitor()
        mockDevice.setConnectionStatus(.disconnected)

        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: mockDevice,
            syncConfig: .testing()
        )

        await #expect(throws: SyncError.networkDisconnected) {
            try await engine.sync()
        }
    }

    @Test("Trial 7: Transient CloudKit save failure recovers through retry ritual")
    func testTransientNetworkFailureRecovery() async throws {
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        _ = try insert(into: context, hash: "retry-hash", visibility: "public")

        let mockCK = MockCloudKitDatabase()
        await mockCK.setSaveErrorToThrow(CKError(.networkFailure))
        await mockCK.setSaveFailuresBeforeSuccess(1)

        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing(maxRetryAttempts: 3, retryDelay: 0.01)
        )

        let result = try await engine.sync()
        #expect(result == .completed(uploaded: 1, skippedVisibility: 0))
        #expect(await mockCK.saveAttempts == 2)
        #expect(await engine.lastSyncDate != nil)
        #expect(await engine.isCloudDirty == false)
    }

    @Test("Trial 8: Severe CloudKit storm fails OPEN (no throw; hot store sovereign)")
    func testNetworkFailOpen() async throws {
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        _ = try insert(into: context, hash: "storm-hash", visibility: "public")

        let mockCK = MockCloudKitDatabase()
        await mockCK.setSaveErrorToThrow(CKError(.networkFailure))

        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing(maxRetryAttempts: 2, retryDelay: 0.01)
        )

        let result = try await engine.sync()
        guard case .failedOpen(let attempts, _) = result else {
            Issue.record("Expected fail-open SyncResult, got \(result)")
            return
        }
        #expect(attempts == 2)
        #expect(await engine.isCloudDirty == true)
        #expect(await engine.lastSyncDate == nil)

        let locals = try context.fetch(FetchDescriptor<AnimaEpisodicRecord>())
        #expect(locals.count == 1)
    }

    @Test("Trial 9: Seal verifier fail-closed blocks export")
    func testSealGateFailClosed() async throws {
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        _ = try insert(into: context, hash: "sealed-hash", visibility: "public")

        let mockCK = MockCloudKitDatabase()
        let engine = CloudKitSyncEngine(
            modelContainer: container,
            ckDatabase: mockCK,
            deviceMonitor: MockDeviceStateMonitor(),
            syncConfig: .testing(),
            sealVerifier: { _ in
                .failure(.sealVerificationFailed("ledger link broken in test"))
            }
        )

        await #expect(throws: SyncError.sealVerificationFailed("ledger link broken in test")) {
            try await engine.sync()
        }
        #expect(await mockCK.saveAttempts == 0)
    }

    @Test("Trial 10: Package-home + schema markers + SyncDirection are frozen")
    func testBin22PackageHomeAndSchemaMarkers() {
        #expect(CloudKitSyncEngine.recordType == "AnimaEpisodicRecord")
        #expect(CloudKitSyncEngine.packageHomeMarker == "Packages/MemoryKit")
        #expect(SyncConfig().direction == .localToCloudKitPrivateDB)
        #expect(SyncConfig().expectedPackageHomeMarker == "Packages/MemoryKit")
        #expect(SyncConfig().syncOnlyOnWifi == true)
    }

    @Test("Trial 11: syncOnlyWhileCharging gate")
    func testChargingRequiredGate() async throws {
        let mockDevice = MockDeviceStateMonitor()
        mockDevice.setBatteryState(.discharging(level: 0.90))

        let engine = CloudKitSyncEngine(
            modelContainer: try createTestModelContainer(),
            ckDatabase: MockCloudKitDatabase(),
            deviceMonitor: mockDevice,
            syncConfig: .testing(syncOnlyWhileCharging: true)
        )

        await #expect(throws: SyncError.chargingRequired) {
            try await engine.sync()
        }
    }
}
