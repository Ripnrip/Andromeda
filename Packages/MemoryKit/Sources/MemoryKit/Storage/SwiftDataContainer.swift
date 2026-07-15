/**
 * 🎭 The SwiftDataContainer - The Enchanted Memory Vault
 *
 * "Isolated from the mortal threads of the main actor, this background wizard
 * coordinates all transactional incantations against our SwiftData hot store,
 * ensuring ACID consistency with sub-millisecond precision."
 *
 * - The Cosmic Process Orchestrator of Anima Storage
 */

import Foundation
import SwiftData

/// 🌩️ Storage errors modeled for our memory theater
public enum AnimaStorageError: Error, LocalizedError, Sendable {
    case recordNotFound
    case duplicateContentHash
    case fetchFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recordNotFound:
            return "🌩️ The sought memory neuron was not found in the vault."
        case .duplicateContentHash:
            return "🌩️ A memory with this content hash already exists."
        case .fetchFailed(let details):
            return "🌩️ Failed to retrieve memories from the vault: \(details)"
        case .saveFailed(let details):
            return "🌩️ Failed to persist memories into the vault: \(details)"
        }
    }
}

/// 🌟 SwiftDataContainer - An actor-isolated container that runs on a background thread/actor,
/// managing database initializations, ACID transactions, and queries under strict Swift 6 concurrency.
@available(macOS 14.0, iOS 17.0, *)
public actor SwiftDataContainer: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    // 🌟 The Grand Initialization Ceremony
    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false // 🔮 No automatic sorcery! Explicit ACID commits only.
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    /// 💎 Create an in-memory database vault - perfect for transient testing rites
    public static func createInMemory() throws -> SwiftDataContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AnimaEpisodicRecord.self, configurations: configuration)
        return SwiftDataContainer(modelContainer: container)
    }

    /// 💎 Create an on-disk database vault - for enduring memories on the persistent stage
    public static func createOnDisk(at url: URL? = nil) throws -> SwiftDataContainer {
        let configuration: ModelConfiguration
        if let url = url {
            configuration = ModelConfiguration(url: url)
        } else {
            configuration = ModelConfiguration()
        }
        let container = try ModelContainer(for: AnimaEpisodicRecord.self, configurations: configuration)
        return SwiftDataContainer(modelContainer: container)
    }

    // MARK: - Transactional Rites (CRUD)

    /// 📥 Insert a new episodic snapshot into our persistent neuron array.
    /// Since the contentHash unique constraint behaves like an upsert under default SwiftData configs,
    /// we can check for duplicate contentHash beforehand if strict "throw on duplicate" is needed.
    public func insert(_ snapshot: AnimaEpisodicRecordSnapshot, checkUniqueHash: Bool = false) throws {
        let context = modelContext
        if checkUniqueHash {
            let hash = snapshot.contentHash
            let descriptor = FetchDescriptor<AnimaEpisodicRecord>(
                predicate: #Predicate<AnimaEpisodicRecord> { $0.contentHash == hash }
            )
            let existingCount = try context.fetchCount(descriptor)
            if existingCount > 0 {
                throw AnimaStorageError.duplicateContentHash
            }
        }
        let record = AnimaEpisodicRecord(snapshot: snapshot)
        context.insert(record)
        do {
            try context.save()
            print("🎉 ✨ MEMORY PERSISTED IN THE VAULT! Content Hash: \(snapshot.contentHash)")
        } catch {
            throw AnimaStorageError.saveFailed(error.localizedDescription)
        }
    }

    /// 🔍 Fetch a specific episodic snapshot by its unique UUID
    public func fetch(id: UUID) throws -> AnimaEpisodicRecordSnapshot? {
        let context = modelContext
        var descriptor = FetchDescriptor<AnimaEpisodicRecord>(
            predicate: #Predicate<AnimaEpisodicRecord> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            let records = try context.fetch(descriptor)
            return records.first?.toSnapshot
        } catch {
            throw AnimaStorageError.fetchFailed(error.localizedDescription)
        }
    }

    /// 🔍 Fetch a specific episodic snapshot by its unique content hash
    public func fetchByContentHash(_ hash: String) throws -> AnimaEpisodicRecordSnapshot? {
        let context = modelContext
        var descriptor = FetchDescriptor<AnimaEpisodicRecord>(
            predicate: #Predicate<AnimaEpisodicRecord> { $0.contentHash == hash }
        )
        descriptor.fetchLimit = 1
        do {
            let records = try context.fetch(descriptor)
            return records.first?.toSnapshot
        } catch {
            throw AnimaStorageError.fetchFailed(error.localizedDescription)
        }
    }

    /// 🌐 Fetch all memories residing in the vault
    public func fetchAll() throws -> [AnimaEpisodicRecordSnapshot] {
        let context = modelContext
        let descriptor = FetchDescriptor<AnimaEpisodicRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            let records = try context.fetch(descriptor)
            return records.map { $0.toSnapshot }
        } catch {
            throw AnimaStorageError.fetchFailed(error.localizedDescription)
        }
    }

    /// 🎨 Filter memories by project, agent, and/or visibility
    public func fetchWithFilters(
        project: String? = nil,
        agent: String? = nil,
        visibility: String? = nil
    ) throws -> [AnimaEpisodicRecordSnapshot] {
        // SwiftData Predicates require fully static resolution.
        // We fetch all (since count is small on capture) and filter on actor.
        let all = try fetchAll()
        return all.filter { record in
            if let project = project, record.project != project { return false }
            if let agent = agent, record.agent != agent { return false }
            if let visibility = visibility, record.visibility != visibility { return false }
            return true
        }
    }

    /// 💅 Update an existing record in the vault
    public func update(_ snapshot: AnimaEpisodicRecordSnapshot) throws {
        let context = modelContext
        let id = snapshot.id
        let descriptor = FetchDescriptor<AnimaEpisodicRecord>(
            predicate: #Predicate<AnimaEpisodicRecord> { $0.id == id }
        )
        do {
            if let record = try context.fetch(descriptor).first {
                record.contentHash = snapshot.contentHash
                record.createdAt = snapshot.createdAt
                record.project = snapshot.project
                record.agent = snapshot.agent
                record.narrative = snapshot.narrative
                record.visibility = snapshot.visibility
                record.provenance = snapshot.provenance
                record.tags = snapshot.tags
                record.materializedPath = snapshot.materializedPath
                try context.save()
                print("🎉 ✨ MEMORY RE-ALCHEMIZED! ID: \(id)")
            } else {
                throw AnimaStorageError.recordNotFound
            }
        } catch let error as AnimaStorageError {
            throw error
        } catch {
            throw AnimaStorageError.saveFailed(error.localizedDescription)
        }
    }

    /// 🩹 Delete a specific memory neuron from the vault
    public func delete(id: UUID) throws {
        let context = modelContext
        let descriptor = FetchDescriptor<AnimaEpisodicRecord>(
            predicate: #Predicate<AnimaEpisodicRecord> { $0.id == id }
        )
        do {
            if let record = try context.fetch(descriptor).first {
                context.delete(record)
                try context.save()
                print("🎉 ✨ MEMORY ERASED FROM EXISTENCE! ID: \(id)")
            } else {
                throw AnimaStorageError.recordNotFound
            }
        } catch let error as AnimaStorageError {
            throw error
        } catch {
            throw AnimaStorageError.saveFailed(error.localizedDescription)
        }
    }

    /// 🧹 Cleanse the entire temple - erase all stored memories
    public func clearAll() throws {
        let context = modelContext
        let descriptor = FetchDescriptor<AnimaEpisodicRecord>()
        do {
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
            print("🧹 ✨ TEMPLE CLEANSED! ALL MEMORIES HAVE EVAPORATED!")
        } catch {
            throw AnimaStorageError.saveFailed(error.localizedDescription)
        }
    }

    /// 🧮 Count the total number of memories currently lingering
    public func count() throws -> Int {
        let context = modelContext
        let descriptor = FetchDescriptor<AnimaEpisodicRecord>()
        do {
            return try context.fetchCount(descriptor)
        } catch {
            throw AnimaStorageError.fetchFailed(error.localizedDescription)
        }
    }
}
