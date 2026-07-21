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
 *
 * Contract: docs/DATA-CONTRACTS.md §13 — rebuildable cache, content_hash point IDs,
 * thin metadata, async-at-materialization, fail-open. Default portal `:8286`.
 */

// MARK: - Models

/// 🌟 The LadybugNode - A crystallized node in the LadybugDB graph
/// Encodes as §13 upsert shape: `point_id` + `vector` + thin `payload` (never raw narrative).
public struct LadybugNode: Codable, Sendable, Equatable {
    public let pointId: UUID
    public let vector: [Float]
    public let payload: Payload

    enum CodingKeys: String, CodingKey {
        case pointId = "point_id"
        case vector
        case payload
    }

    /// 🌟 Thin metadata scroll — filter + join pointer only (no body / narrative).
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

        // 🌟 Gathering the whisper-thin metadata for the Ladybug vault
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

    // 🌟 Binding deterministic point ID, embedding, and thin payload into one node
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

    // 🌟 Spinning a typed thread between two content-hash stars
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
    /// Truncated SHA-256 → 16 bytes (DATA-CONTRACTS §13 idempotency key).
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

/// 🎭 The LadybugIndexer - Actor-isolated, fail-open graph+vector upsert client for `:8286`
public actor LadybugIndexer {
    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "com.multibrain.Anima", category: "LadybugIndexer")

    /// 🔮 Dirty when an upsert failed — background repair should rebuild the cache
    private(set) public var isDirty: Bool = false

    /// 🌐 The Initialization Ritual - Awakening the Cartographer (default Ladybug `:8286`)
    public init(baseURL: URL = URL(string: "http://127.0.0.1:8286")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        logger.info("🌐 ✨ LADYBUG INDEXER AWAKENS! Pointing to \(baseURL.absoluteString)")
    }

    /// 🌟 The Node Upsert Alchemy - PUT `/nodes` (idempotent by `point_id` = content_hash UUID)
    /// Fail-open: never throws; returns `false` and sets `isDirty` on network/HTTP storms.
    @discardableResult
    public func indexNode(_ node: LadybugNode) async -> Bool {
        logger.debug("🔍 🧙‍♂️ Peering into mystical variables... Node pointId: \(node.pointId)")

        let endpoint = baseURL.appendingPathComponent("nodes")
        var request = URLRequest(url: endpoint)
        // 🎨 PUT = upsert: same content_hash → same point_id → no duplicate stars
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            let mysticalData = try encoder.encode(node)
            request.httpBody = mysticalData

            logger.debug("🌟 Node Upsert Alchemy commences for pointId: \(node.pointId)")
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

            logger.info("🎉 ✨ NODE UPSERT MASTERPIECE COMPLETE! pointId: \(node.pointId)")
            return true
        } catch {
            // 🎭 Fail-open: index is a rebuildable cache — never halt the materialization ballet
            logger.error("🌩️ Temporary setback: \(error.localizedDescription)")
            logger.error("🎭 But the show must go on... (Fail-Open mode engaged)")
            self.isDirty = true
            return false
        }
    }

    /// 🌟 The Connection Upsert Weaving - PUT `/edges` between deterministic content-hash IDs
    /// Fail-open: never throws; returns `false` and sets `isDirty` on storms.
    @discardableResult
    public func indexConnection(_ connection: LadybugConnection) async -> Bool {
        logger.debug("🔍 🧙‍♂️ Peering into mystical variables... Edge from: \(connection.fromId) to: \(connection.toId)")

        let endpoint = baseURL.appendingPathComponent("edges")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            let mysticalData = try encoder.encode(connection)
            request.httpBody = mysticalData

            logger.debug("🌟 Connection Upsert Weaving commences from: \(connection.fromId) to: \(connection.toId)")
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

            logger.info("🎉 ✨ CONNECTION UPSERT MASTERPIECE COMPLETE! from: \(connection.fromId) to: \(connection.toId)")
            return true
        } catch {
            logger.error("🌩️ Temporary setback: \(error.localizedDescription)")
            logger.error("🎭 But the show must go on... (Fail-Open mode engaged)")
            self.isDirty = true
            return false
        }
    }

    /// 🌟 The High-Level Node Ingestion - content_hash → deterministic point_id + thin payload
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

    /// 🌟 The Purification Ritual - Resetting the Dirty Flag after a successful rebuild
    public func resetDirty() {
        logger.info("💎 Purifying the index state... isDirty reset to false")
        self.isDirty = false
    }
}
