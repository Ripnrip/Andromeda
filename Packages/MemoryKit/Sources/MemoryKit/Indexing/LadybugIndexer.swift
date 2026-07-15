import Foundation
import CryptoKit
import OSLog

/**
 * 🎭 The LadybugIndexer - The Archival Cartographer of the Multi-Brain
 *
 * "Every session-learning is a star in our digital sky;
 * we chart their coordinates, weave their kindred threads,
 * and project their light into the warm chambers of LadybugDB."
 *
 * - The Spellbinding Museum Director of Archival Indexing
 */

// MARK: - Models

/// 🌟 The LadybugNode - A crystallized node in the LadybugDB graph
public struct LadybugNode: Codable, Sendable, Equatable {
    public let pointId: UUID
    public let vector: [Float]
    public let payload: Payload
    
    public struct Payload: Codable, Sendable, Equatable {
        public let contentHash: String
        public let visibility: String
        public let project: String
        public let date: String
        public let tags: [String]
        public let sourcePath: String
        
        enum CodingKeys: String, CodingKey {
            case contentHash = "content_hash"
            case visibility
            case project
            case date
            case tags
            case sourcePath = "source_path"
        }
        
        public init(
            contentHash: String,
            visibility: String,
            project: String,
            date: String,
            tags: [String],
            sourcePath: String
        ) {
            self.contentHash = contentHash
            self.visibility = visibility
            self.project = project
            self.date = date
            self.tags = tags
            self.sourcePath = sourcePath
        }
    }
    
    public init(pointId: UUID, vector: [Float], payload: Payload) {
        self.pointId = pointId
        self.vector = vector
        self.payload = payload
    }
}

/// 🌟 The LadybugConnection - An edge weaving together kindred thoughts
public struct LadybugConnection: Codable, Sendable, Equatable {
    public let fromId: UUID
    public let toId: UUID
    public let type: String // "SHARES_PROJECT" | "SHARES_CONCEPT"
    public let concept: String? // optional, for SHARES_CONCEPT
    
    enum CodingKeys: String, CodingKey {
        case fromId = "from_id"
        case toId = "to_id"
        case type
        case concept
    }
    
    public init(fromId: UUID, toId: UUID, type: String, concept: String? = nil) {
        self.fromId = fromId
        self.toId = toId
        self.type = type
        self.concept = concept
    }
}

// MARK: - UUID Extension

extension UUID {
    /// 🌟 The Deterministic Key Catalyst - Mapping Content Hash to UUID Space
    public static func deterministic(from contentHash: String) -> UUID {
        let inputData = Data(contentHash.utf8)
        let hash = SHA256.hash(data: inputData)
        let bytes = Array(hash.prefix(16))
        
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - LadybugIndexer

/// 🎭 The LadybugIndexer - Actor-isolated, fail-open graph+vector indexer
public actor LadybugIndexer {
    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "com.multibrain.Anima", category: "LadybugIndexer")
    
    /// 🔮 The state of our index's alignment
    private(set) public var isDirty: Bool = false
    
    /// 🌐 The Initialization Ritual - Awakening the Cartographer
    public init(baseURL: URL = URL(string: "http://127.0.0.1:8286")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        logger.info("🌐 ✨ LADYBUG INDEXER AWAKENS! Pointing to \(baseURL.absoluteString)")
    }
    
    /// 🌟 The Node Alchemy - Projecting a Node into LadybugDB
    @discardableResult
    public func indexNode(_ node: LadybugNode) async -> Bool {
        logger.debug("🔍 🧙‍♂️ Peering into mystical variables... Node pointId: \(node.pointId)")
        
        let endpoint = baseURL.appendingPathComponent("nodes")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            let mysticalData = try encoder.encode(node)
            request.httpBody = mysticalData
            
            logger.debug("🌟 Node Alchemy commences for pointId: \(node.pointId)")
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("🌩️ Temporary storm: Response was not HTTPURLResponse")
                self.isDirty = true
                return false
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("🌩️ Temporary storm: HTTP status \(httpResponse.statusCode) from /nodes")
                self.isDirty = true
                return false
            }
            
            logger.info("🎉 ✨ NODE ALCHEMY MASTERPIECE COMPLETE! pointId: \(node.pointId)")
            return true
        } catch {
            logger.error("🌩️ Temporary setback: \(error.localizedDescription)")
            logger.error("🎭 But the show must go on... (Fail-Open mode engaged)")
            self.isDirty = true
            return false
        }
    }
    
    /// 🌟 The Connection Weaving - Linking Two Stars in the Constellation
    @discardableResult
    public func indexConnection(_ connection: LadybugConnection) async -> Bool {
        logger.debug("🔍 🧙‍♂️ Peering into mystical variables... Edge from: \(connection.fromId) to: \(connection.toId)")
        
        let endpoint = baseURL.appendingPathComponent("edges")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            let mysticalData = try encoder.encode(connection)
            request.httpBody = mysticalData
            
            logger.debug("🌟 Connection Weaving commences from: \(connection.fromId) to: \(connection.toId)")
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("🌩️ Temporary storm: Response was not HTTPURLResponse")
                self.isDirty = true
                return false
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("🌩️ Temporary storm: HTTP status \(httpResponse.statusCode) from /edges")
                self.isDirty = true
                return false
            }
            
            logger.info("🎉 ✨ CONNECTION WEAVING MASTERPIECE COMPLETE! from: \(connection.fromId) to: \(connection.toId)")
            return true
        } catch {
            logger.error("🌩️ Temporary setback: \(error.localizedDescription)")
            logger.error("🎭 But the show must go on... (Fail-Open mode engaged)")
            self.isDirty = true
            return false
        }
    }
    
    /// 🌟 The High-Level Node Ingestion - From Raw Wisdom to Crystallized Node
    @discardableResult
    public func index(
        contentHash: String,
        vector: [Float],
        visibility: String,
        project: String,
        date: String,
        tags: [String],
        sourcePath: String
    ) async -> Bool {
        let pointId = UUID.deterministic(from: contentHash)
        let payload = LadybugNode.Payload(
            contentHash: contentHash,
            visibility: visibility,
            project: project,
            date: date,
            tags: tags,
            sourcePath: sourcePath
        )
        let node = LadybugNode(pointId: pointId, vector: vector, payload: payload)
        return await indexNode(node)
    }
    
    /// 🌟 The High-Level Connection Ingestion - Weaving the Web of Meaning
    @discardableResult
    public func connect(
        fromHash: String,
        toHash: String,
        type: String,
        concept: String? = nil
    ) async -> Bool {
        let fromId = UUID.deterministic(from: fromHash)
        let toId = UUID.deterministic(from: toHash)
        let connection = LadybugConnection(fromId: fromId, toId: toId, type: type, concept: concept)
        return await indexConnection(connection)
    }
    
    /// 🌟 The Purification Ritual - Resetting the Dirty Flag
    public func resetDirty() {
        logger.info("💎 Purifying the index state... isDirty reset to false")
        self.isDirty = false
    }
}
