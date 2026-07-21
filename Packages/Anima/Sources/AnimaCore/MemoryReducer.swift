/**
 * 🎭 The MemoryReducer - The Celestial Weaver of the Hive Mind
 *
 * "We weave the floating threads of daily capture,
 * spinning them into synchronized constellations of cloud gold,
 * while anchoring the mortal ties of connection health with steadfast watch."
 *
 * - The Spellbinding Museum Director of Layer 07 (TCA Orchestration)
 */

import Foundation
import ComposableArchitecture
import MemoryKit

// MARK: - Reducer Definition

/// 🎭 The MemoryReducer - The Composable Architecture (TCA) core for Anima
@Reducer
public struct MemoryReducer: Sendable {

    /// 🎫 Cancel IDs so in-flight sync / materialization / health effects don't pile up like unread scrolls
    private enum CancelID: Hashable, Sendable {
        case sync
        case materialization
        case health
        case capture
    }

    // 🌟 The State of our Celestial Memory Canvas
    @ObservableState
    public struct State: Equatable, Sendable {
        public var syncStatus: SyncStatus
        public var connectionHealth: [String: ConnectionHealthStatus]
        public var recentCaptures: [AnimaEpisodicRecordSnapshot]
        public var activeVisibility: VisibilityLevel
        public var materializationStatus: MaterializationStatus

        public init(
            syncStatus: SyncStatus = .idle,
            connectionHealth: [String: ConnectionHealthStatus] = [:],
            recentCaptures: [AnimaEpisodicRecordSnapshot] = [],
            activeVisibility: VisibilityLevel = .private,
            materializationStatus: MaterializationStatus = .idle
        ) {
            self.syncStatus = syncStatus
            self.connectionHealth = connectionHealth
            self.recentCaptures = recentCaptures
            self.activeVisibility = activeVisibility
            self.materializationStatus = materializationStatus
        }
    }

    // 🌟 The Actions crossing our stage
    public enum Action: Equatable, Sendable {
        // User/Trigger Actions
        case captureMemory(AnimaEpisodicRecordSnapshot)
        case changeVisibility(VisibilityLevel)
        case triggerSync
        case triggerMaterialization
        case checkConnectionHealth

        // Background Effects Callbacks
        case syncResponse(Result<Date, SyncError>)
        case materializationProgress(Double)
        case materializationResponse(Result<String, MaterializationError>)
        case connectionHealthResponse(service: String, status: ConnectionHealthStatus)
        case databaseDidUpdate([AnimaEpisodicRecordSnapshot])
    }

    // 🌟 Dependencies of our Alchemy
    @Dependency(\.syncClient) var syncClient
    @Dependency(\.materializerClient) var materializerClient
    @Dependency(\.healthCheckClient) var healthCheckClient
    @Dependency(\.databaseClient) var databaseClient

    public init() {}

    // 🌟 The Reducer Body - Orchestrating State and Effects
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .captureMemory(let snapshot):
                // 📥 Ingest a new capture snapshot into our write-ahead journal
                print("🌐 ✨ CAPTURE INGESTION AWAKENS! project: \(snapshot.project)")
                return .run { [databaseClient] send in
                    try await databaseClient.insertCapture(snapshot)
                } catch: { creativeChallenge, send in
                    print("🌩️ Temporary setback on capture: \(creativeChallenge.localizedDescription)")
                }
                .cancellable(id: CancelID.capture, cancelInFlight: true)

            case .changeVisibility(let level):
                // 💅 Adjust our active visibility filters
                state.activeVisibility = level
                print("💅 Active visibility level shifted to: \(level.rawValue)")
                return .none

            case .triggerSync:
                // ☁️ Initiate the celestial synchronization engine
                guard state.syncStatus != .syncing else {
                    print("🌙 ⚠️ Gentle reminder: Sync already in progress, ignoring duplicate trigger.")
                    return .none
                }
                state.syncStatus = .syncing
                print("🌐 ✨ CELESTIAL SYNC AWAKENS!")
                return .run { [syncClient] send in
                    let date = try await syncClient.sync()
                    await send(.syncResponse(.success(date)))
                } catch: { error, send in
                    let syncError = (error as? SyncError) ?? .cloudKitError(error.localizedDescription)
                    await send(.syncResponse(.failure(syncError)))
                }
                .cancellable(id: CancelID.sync, cancelInFlight: true)

            case .syncResponse(let result):
                // 💎 Process sync engine responses
                switch result {
                case .success(let date):
                    state.syncStatus = .success(date)
                    print("🎉 ✨ SYNCHRONIZATION MASTERPIECE COMPLETE! last synced at \(date)")
                case .failure(let error):
                    state.syncStatus = .failed(error)
                    print("💥 😭 SYNCHRONIZATION TEMPORARILY HALTED! Error: \(error.localizedDescription)")
                }
                return .none

            case .triggerMaterialization:
                // 📝 Trigger Obsidian Markdown Projection
                state.materializationStatus = .materializing(progress: 0.0)
                print("🌐 ✨ MATERIALIZATION AWAKENS!")
                return .run { [materializerClient] send in
                    let stream = await materializerClient.materialize()
                    for await event in stream {
                        switch event {
                        case .progress(let progress):
                            await send(.materializationProgress(progress))
                        case .success(let path):
                            await send(.materializationResponse(.success(path)))
                        case .failure(let error):
                            await send(.materializationResponse(.failure(MaterializationError(error))))
                        }
                    }
                }
                .cancellable(id: CancelID.materialization, cancelInFlight: true)

            case .materializationProgress(let progress):
                // 🎪 Update running materialization cycle progress
                if case .materializing = state.materializationStatus {
                    state.materializationStatus = .materializing(progress: progress)
                    print("🎪 📦 Materialization progress: \(Int(progress * 100))% entering the cosmic ring!")
                }
                return .none

            case .materializationResponse(let result):
                // 🏆 Materialization cycle completed
                switch result {
                case .success(let path):
                    state.materializationStatus = .success(path)
                    print("🎉 ✨ MATERIALIZATION MASTERPIECE COMPLETE! Materialized to \(path)")
                case .failure(let error):
                    state.materializationStatus = .failed(error.message)
                    print("💥 😭 MATERIALIZATION TEMPORARILY HALTED! Error: \(error)")
                }
                return .none

            case .checkConnectionHealth:
                // 📡 Verify Letta, Ladybug, and Qdrant connections in parallel,
                // then emit responses in stable alphabetical order (no sleep-timing flakiness).
                print("🌐 ✨ HEALTH MONITORING AWAKENS!")
                return .run { [healthCheckClient] send in
                    let services = ["Ladybug", "Letta", "Qdrant"]
                    var harvest: [(String, ConnectionHealthStatus)] = []
                    await withTaskGroup(of: (String, ConnectionHealthStatus).self) { group in
                        for service in services {
                            group.addTask {
                                let status = await healthCheckClient.checkHealth(service)
                                return (service, status)
                            }
                        }
                        for await result in group {
                            harvest.append(result)
                        }
                    }
                    for (service, status) in harvest.sorted(by: { $0.0 < $1.0 }) {
                        await send(.connectionHealthResponse(service: service, status: status))
                    }
                }
                .cancellable(id: CancelID.health, cancelInFlight: true)

            case .connectionHealthResponse(let service, let status):
                // 💎 Commit service health logs into state
                state.connectionHealth[service] = status
                return .none

            case .databaseDidUpdate(let snapshots):
                // 📥 React to background database observer updates
                state.recentCaptures = snapshots
                print("🎉 ✨ DATABASE OBSERVER REVEALS NEW WISDOM! Count: \(snapshots.count)")
                return .none
            }
        }
    }
}

// MARK: - Dependency Injections

public struct SyncClient: Sendable {
    public var sync: @Sendable () async throws -> Date
    public init(sync: @escaping @Sendable () async throws -> Date) {
        self.sync = sync
    }
}

public struct MaterializerClient: Sendable {
    public enum MaterializationEvent: Equatable, Sendable {
        case progress(Double)
        case success(String)
        case failure(String)
    }
    public var materialize: @Sendable () async -> AsyncStream<MaterializationEvent>
    public init(materialize: @escaping @Sendable () async -> AsyncStream<MaterializationEvent>) {
        self.materialize = materialize
    }
}

public struct HealthCheckClient: Sendable {
    public var checkHealth: @Sendable (String) async -> ConnectionHealthStatus
    public init(checkHealth: @escaping @Sendable (String) async -> ConnectionHealthStatus) {
        self.checkHealth = checkHealth
    }
}

public struct DatabaseClient: Sendable {
    public var observeCaptures: @Sendable () async -> AsyncStream<[AnimaEpisodicRecordSnapshot]>
    public var insertCapture: @Sendable (AnimaEpisodicRecordSnapshot) async throws -> Void
    public init(
        observeCaptures: @escaping @Sendable () async -> AsyncStream<[AnimaEpisodicRecordSnapshot]>,
        insertCapture: @escaping @Sendable (AnimaEpisodicRecordSnapshot) async throws -> Void
    ) {
        self.observeCaptures = observeCaptures
        self.insertCapture = insertCapture
    }
}

extension SyncClient: DependencyKey {
    public static let liveValue = SyncClient(
        sync: {
            // Under normal circumstances, this would bridge to the live CloudKitSyncEngine
            return Date()
        }
    )
    public static let testValue = SyncClient(
        sync: { Date() }
    )
}

extension MaterializerClient: DependencyKey {
    public static let liveValue = MaterializerClient(
        materialize: {
            AsyncStream { continuation in
                continuation.finish()
            }
        }
    )
    public static let testValue = MaterializerClient(
        materialize: { AsyncStream { $0.finish() } }
    )
}

extension HealthCheckClient: DependencyKey {
    public static let liveValue = HealthCheckClient(
        checkHealth: { _ in .unknown }
    )
    public static let testValue = HealthCheckClient(
        checkHealth: { _ in .unknown }
    )
}

extension DatabaseClient: DependencyKey {
    public static let liveValue = DatabaseClient(
        observeCaptures: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        insertCapture: { _ in }
    )
    public static let testValue = DatabaseClient(
        observeCaptures: { AsyncStream { $0.finish() } },
        insertCapture: { _ in }
    )
}

extension DependencyValues {
    public var syncClient: SyncClient {
        get { self[SyncClient.self] }
        set { self[SyncClient.self] = newValue }
    }
    public var materializerClient: MaterializerClient {
        get { self[MaterializerClient.self] }
        set { self[MaterializerClient.self] = newValue }
    }
    public var healthCheckClient: HealthCheckClient {
        get { self[HealthCheckClient.self] }
        set { self[HealthCheckClient.self] = newValue }
    }
    public var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}
