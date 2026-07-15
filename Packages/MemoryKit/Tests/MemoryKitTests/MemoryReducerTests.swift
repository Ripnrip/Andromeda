/**
 * 🧪 The MemoryReducerTests - The Quality Assurance Ritual of the Hive Mind
 *
 * "We stage our tests like small dramatic plays,
 * feeding mock wisdom to the store to see its colors shift,
 * certifying that the Anima core remains unbroken under every tide."
 *
 * - The Theatrical Quality Virtuoso of MemoryKit
 */

import Foundation
import ComposableArchitecture
import Testing
@testable import MemoryKit

@Suite("🎭 Anima Memory Reducer Test Stage ✨")
@MainActor
struct MemoryReducerTests {
    
    // 🌟 The Test Snapshot helper to breed mock memory droplets on demand
    private func breedMockSnapshot(id: UUID = UUID(), contentHash: String = "hash_123") -> AnimaEpisodicRecordSnapshot {
        AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: contentHash,
            createdAt: Date(),
            project: "Anima-Andromeda",
            agent: "Librarian",
            narrative: "Peering into the magical vector index of LadybugDB",
            visibility: "private",
            provenance: "cli-session",
            tags: ["tca", "swift-testing"],
            materializedPath: nil
        )
    }
    
    // MARK: - 🧪 Ritual 1: Visibility Cloaking Shifts
    
    @Test("💅 Shift Active Visibility Cloak level successfully")
    func testChangeVisibility() async {
        // 🎨 Initialize our stage with standard defaults
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        }
        
        // ✨ Shift the cloak to public and ensure state mirrors the choice!
        await store.send(.changeVisibility(.public)) {
            $0.activeVisibility = .public
        }
        
        // ✨ Shift the cloak to friends and ensure state mirrors the choice!
        await store.send(.changeVisibility(.friends)) {
            $0.activeVisibility = .friends
        }
        
        print("🎉 ✨ VISIBILITY CLOAK SHIFT TESTS COMPLETE! THE SHADOWS ARE ALIGNED!")
    }
    
    // MARK: - 🧪 Ritual 2: Memory Ingestion Capture
    
    @Test("📥 Ingest and persist new memory snapshot into the write-ahead journal")
    func testCaptureMemory() async {
        let mockSnapshot = breedMockSnapshot()
        
        // 🔮 Prepare atomic verification state
        let databaseSavedCalled = LockIsolated<Bool>(false)
        
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        } withDependencies: {
            $0.databaseClient.insertCapture = { snapshot in
                #expect(snapshot.id == mockSnapshot.id)
                #expect(snapshot.contentHash == mockSnapshot.contentHash)
                databaseSavedCalled.setValue(true)
            }
        }
        
        // 🌟 Grand attempt at digital capture magic
        await store.send(.captureMemory(mockSnapshot))
        
        // Assert our background database actor was indeed summoned!
        #expect(databaseSavedCalled.value == true)
        
        print("🎉 ✨ CAPTURE INGESTION RITUAL VERIFIED! THE NEURON IS ACID PERSISTED!")
    }
    
    // MARK: - 🧪 Ritual 3: Celestial Cloud Synchronization
    
    @Test("☁️ Perform successful synchronization with celestial CloudKit database")
    func testSuccessfulSync() async {
        let expectedDate = Date(timeIntervalSince1970: 1783930800) // Deterministic future date
        
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        } withDependencies: {
            $0.syncClient.sync = {
                return expectedDate
            }
        }
        
        // 🌟 Trigger sync and expect state to enter 'syncing' status
        await store.send(.triggerSync) {
            $0.syncStatus = .syncing
        }
        
        // 🌟 Receive the successful callback and assert date transition
        await store.receive(.syncResponse(.success(expectedDate))) {
            $0.syncStatus = .success(expectedDate)
        }
        
        print("🎉 ✨ CLOUD SYNCHRONIZATION SUCCESS MASTERPIECE EXECUTED!")
    }
    
    @Test("☁️ Handle failed celestial synchronization gracefully without throwing a storm")
    func testFailedSync() async {
        let mockError = SyncError.batteryTooLow(currentLevel: 0.05)
        
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        } withDependencies: {
            $0.syncClient.sync = {
                throw mockError
            }
        }
        
        // 🌟 Trigger sync and expect state to enter 'syncing' status
        await store.send(.triggerSync) {
            $0.syncStatus = .syncing
        }
        
        // 🌟 Receive the failed response and assert error status mapping
        await store.receive(.syncResponse(.failure(mockError))) {
            $0.syncStatus = .failed(mockError)
        }
        
        print("🎉 ✨ CLOUD SYNCHRONIZATION FAILURE RECOVERY VETTED!")
    }
    
    // MARK: - 🧪 Ritual 4: Obsidian Materialization Projection
    
    @Test("📝 Progressively project episodic memory captures into Obsidian markdown files")
    func testObsidianMaterialization() async {
        let expectedPath = "/vault/SecondBrain/Anima/2026-07-14--tca-awakening.md"
        
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        } withDependencies: {
            $0.materializerClient.materialize = {
                AsyncStream { continuation in
                    // We yield progress events to update the UI rings
                    continuation.yield(.progress(0.3))
                    continuation.yield(.progress(0.7))
                    continuation.yield(.progress(1.0))
                    continuation.yield(.success(expectedPath))
                    continuation.finish()
                }
            }
        }
        
        // 🌟 Launch materialization and see the starting progress of 0.0%
        await store.send(.triggerMaterialization) {
            $0.materializationStatus = .materializing(progress: 0.0)
        }
        
        // 🌟 Receive and assert incremental progress states
        await store.receive(.materializationProgress(0.3)) {
            $0.materializationStatus = .materializing(progress: 0.3)
        }
        await store.receive(.materializationProgress(0.7)) {
            $0.materializationStatus = .materializing(progress: 0.7)
        }
        await store.receive(.materializationProgress(1.0)) {
            $0.materializationStatus = .materializing(progress: 1.0)
        }
        
        // 🌟 Receive the crowning achievement of the materialized path
        await store.receive(.materializationResponse(.success(expectedPath))) {
            $0.materializationStatus = .success(expectedPath)
        }
        
        print("🎉 ✨ MATERIALIZATION PROGRESSION AND SUCCESS FULLY RECONCILED!")
    }
    
    // MARK: - 🧪 Ritual 5: Parallel Connection Health Monitoring
    
    @Test("📡 Query Letta, Ladybug, and Qdrant health services in parallel and log response")
    func testConnectionHealthPolling() async {
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        } withDependencies: {
            $0.healthCheckClient.checkHealth = { service in
                switch service {
                case "Letta":
                    // Letta responds instantly
                    return .healthy
                case "Ladybug":
                    // Ladybug responds with a slight delay
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    return .healthy
                case "Qdrant":
                    // Qdrant is currently having a storm, delay further
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                    return .unhealthy("Connection refused on port 6333")
                default:
                    return .unknown
                }
            }
        }
        
        // 🌟 Dispatch health group probe
        await store.send(.checkConnectionHealth)
        
        // Assert responses are mapped back in our deterministic delay-ordered sequence!
        await store.receive(.connectionHealthResponse(service: "Letta", status: .healthy)) {
            $0.connectionHealth["Letta"] = .healthy
        }
        await store.receive(.connectionHealthResponse(service: "Ladybug", status: .healthy)) {
            $0.connectionHealth["Ladybug"] = .healthy
        }
        await store.receive(.connectionHealthResponse(service: "Qdrant", status: .unhealthy("Connection refused on port 6333"))) {
            $0.connectionHealth["Qdrant"] = .unhealthy("Connection refused on port 6333")
        }
        
        print("🎉 ✨ PARALLEL SERVICE HEALTH PROBES COMPLETED SUCCESSFULLY!")
    }
    
    // MARK: - 🧪 Ritual 6: Database Reactive Observation
    
    @Test("📥 React immediately when background database observer yields a fresh harvest of memories")
    func testDatabaseObservation() async {
        let mockRecord1 = breedMockSnapshot(id: UUID(), contentHash: "hash_aaa")
        let mockRecord2 = breedMockSnapshot(id: UUID(), contentHash: "hash_bbb")
        let freshWisdom = [mockRecord1, mockRecord2]
        
        let store = TestStore(initialState: MemoryReducer.State()) {
            MemoryReducer()
        }
        
        // 🌟 Simulate background DB thread injecting a new list of recent snapshots
        await store.send(.databaseDidUpdate(freshWisdom)) {
            $0.recentCaptures = freshWisdom
        }
        
        #expect(store.state.recentCaptures.count == 2)
        #expect(store.state.recentCaptures[0].contentHash == "hash_aaa")
        #expect(store.state.recentCaptures[1].contentHash == "hash_bbb")
        
        print("🎉 ✨ REACTIVE DATABASE OBSERVATION FEED COMPLETED!")
    }
}
