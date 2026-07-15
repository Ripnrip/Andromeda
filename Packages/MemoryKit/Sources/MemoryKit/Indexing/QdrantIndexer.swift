import Foundation
import CryptoKit
import OSLog

/**
 * 🎭 The QdrantIndexer - The Spatial Cartographer of the Deep Brain
 *
 * "Through the dark, silent corridors of local space,
 * we map each memory to a precise coordinate in the cosmic field.
 * With deterministic anchors and fail-open resilience,
 * the index stands, a shining, rebuildable mirror of the Mind."
 *
 * - The Spellbinding Museum Director of Vector Navigation
 *
 * Contract: docs/DATA-CONTRACTS.md §13
 * - Point ID = UUIDv5(secondBrainNamespace, content_hash)
 * - Thin payload only (no full body / narrative / document text)
 * - Fail-open: never throw across the index boundary; mark dirty instead
 */

// MARK: - Models

/// 🌟 The QdrantVector - A flexible container for unnamed or named coordinates
/// Capable of handling simple float arrays or named vector dictionaries with equal grace.
public enum QdrantVector: Codable, Sendable, Equatable {
    case flat([Float])
    case named([String: [Float]])

    // 🌟 The Decoding Alchemy
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flat = try? container.decode([Float].self) {
            self = .flat(flat)
        } else if let named = try? container.decode([String: [Float]].self) {
            self = .named(named)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The coordinate structure does not match our mathematical schemas. 🗺️"
            )
        }
    }

    // 🌟 The Encoding Alchemy
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .flat(let array):
            try container.encode(array)
        case .named(let dict):
            try container.encode(dict)
        }
    }
}

/// 🌟 The QdrantPayload - The thin, metadata-light scroll of record
/// We keep the payload whisper-thin, storing only references and indices, never heavy content.
/// Forbidden: body, narrative, text, document, content (full prose). Join back via `source_path`.
public struct QdrantPayload: Codable, Sendable, Equatable {
    /// 📜 Contract keys from DATA-CONTRACTS §13 — nothing else may ride the upsert.
    public static let allowedKeys: Set<String> = [
        "content_hash", "visibility", "project", "date", "tags", "source_path"
    ]

    /// 🚫 Keys that would smuggle the full body into a rebuildable cache (never encode these).
    public static let forbiddenKeys: Set<String> = [
        "body", "text", "narrative", "document", "content", "raw", "markdown", "full_text"
    ]

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

    // 🌟 Gathering the metadata elements into a thin record
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

    /// 🔍 Decode only the six contract keys; refuse full-body smuggling attempts.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        visibility = try container.decode(String.self, forKey: .visibility)
        project = try container.decode(String.self, forKey: .project)
        date = try container.decode(String.self, forKey: .date)
        tags = try container.decode([String].self, forKey: .tags)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
    }

    /// ✨ Encode exactly the thin schema — no opportunistic extra fields.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(project, forKey: .project)
        try container.encode(date, forKey: .date)
        try container.encode(tags, forKey: .tags)
        try container.encode(sourcePath, forKey: .sourcePath)
    }

    /// 🧪 Verify a decoded JSON object adheres to the thin-payload contract.
    public static func isThinPayloadJSON(_ object: [String: Any]) -> Bool {
        let keys = Set(object.keys)
        guard keys.isSubset(of: allowedKeys) else { return false }
        guard keys.isDisjoint(with: forbiddenKeys) else { return false }
        return true
    }
}

/// 🌟 The QdrantPoint - A fully defined point in Qdrant's vector space
public struct QdrantPoint: Codable, Sendable, Equatable {
    public let id: UUID
    public let vector: QdrantVector
    public let payload: QdrantPayload

    // 🌟 Binding the coordinates, deterministic ID, and thin metadata together
    public init(id: UUID, vector: QdrantVector, payload: QdrantPayload) {
        self.id = id
        self.vector = vector
        self.payload = payload
    }

    /// 🧭 Encode point id as a lowercase UUID string (Qdrant REST wire format).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(vector, forKey: .vector)
        try container.encode(payload, forKey: .payload)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let parsed = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Point id is not a valid UUID string. 🔮"
            )
        }
        id = parsed
        vector = try container.decode(QdrantVector.self, forKey: .vector)
        payload = try container.decode(QdrantPayload.self, forKey: .payload)
    }

    private enum CodingKeys: String, CodingKey {
        case id, vector, payload
    }
}

/// 🌟 The QdrantUpsertRequest - The batch payload container for point insertion
public struct QdrantUpsertRequest: Codable, Sendable {
    public let points: [QdrantPoint]

    // 🌟 Wrapping our points into an atomic transmission package
    public init(points: [QdrantPoint]) {
        self.points = points
    }
}

// MARK: - UUID Extension

extension UUID {
    /// 🌟 The Deterministic UUIDv5 Catalyst - Mapping Namespace and Name to UUIDv5 Space
    /// Implements RFC 4122 Section 4.3 with the secure, time-honored SHA-1 hash.
    public static func uuidv5(namespace: UUID, name: String) -> UUID {
        var namespaceBytes = namespace.uuid
        var data = Data(bytes: &namespaceBytes, count: 16)
        data.append(Data(name.utf8))

        let hash = Insecure.SHA1.hash(data: data)
        var bytes = Array(hash)

        // 🔮 Applying version 5 (0101) to byte 6
        bytes[6] = (bytes[6] & 0x0F) | 0x50

        // 🔮 Applying variant RFC 4122 (10) to byte 8
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// 🌟 The Second Brain Namespace - A sacred anchor in the infinite cosmos of UUIDs
    public static let secondBrainNamespace = UUID(uuidString: "28e21975-d144-42eb-8eb8-fb0e5bfb0c80")!

    /// 🌟 The Deterministic Vector Point ID - Transforming a Content Hash into a stable star in Qdrant
    /// Guaranteeing absolute idempotency across our index rebuilds (DATA-CONTRACTS §13).
    public static func deterministicV5(from contentHash: String) -> UUID {
        return uuidv5(namespace: secondBrainNamespace, name: contentHash)
    }
}

// MARK: - QdrantIndexer

/// 🎭 The QdrantIndexer - Actor-isolated, fail-open vector indexer
public actor QdrantIndexer {
    private let baseURL: URL
    private let collectionName: String
    private let vectorName: String?
    private let session: URLSession
    private let logger = Logger(subsystem: "com.multibrain.Anima", category: "QdrantIndexer")

    /// 🔮 The state of our index's alignment (marked dirty if connection fails)
    private(set) public var isDirty: Bool = false

    /// 🌐 The Initialization Ritual - Awakening the Vector Scribe
    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:6333")!,
        collectionName: String = "secondbrain_learnings",
        vectorName: String? = "fast-all-minilm-l6-v2",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.collectionName = collectionName
        self.vectorName = vectorName
        self.session = session
        logger.info("🌐 ✨ QDRANT INDEXER AWAKENS! Pointing to \(baseURL.absoluteString), collection: \(collectionName)")
    }

    /// 🏗️ Build a §13-compliant point: deterministic UUIDv5 + thin payload + optional named vector.
    /// Never accepts a full body — only the join pointer `sourcePath`.
    public func makePoint(
        contentHash: String,
        vector: [Float],
        visibility: String,
        project: String,
        date: String,
        tags: [String],
        sourcePath: String
    ) -> QdrantPoint {
        let pointId = UUID.deterministicV5(from: contentHash)

        let qdrantVector: QdrantVector
        if let vectorName = self.vectorName {
            qdrantVector = .named([vectorName: vector])
        } else {
            qdrantVector = .flat(vector)
        }

        let payload = QdrantPayload(
            contentHash: contentHash,
            visibility: visibility,
            project: project,
            date: date,
            tags: tags,
            sourcePath: sourcePath
        )

        return QdrantPoint(id: pointId, vector: qdrantVector, payload: payload)
    }

    /// 🌟 The Point Alchemy - Projecting a single Point into Qdrant space
    /// Fail-open: returns `false` and sets `isDirty` on any network/HTTP storm; never throws.
    @discardableResult
    public func indexPoint(_ point: QdrantPoint) async -> Bool {
        logger.debug("🔍 🧙‍♂️ Peering into mystical variables... Point ID: \(point.id)")

        let endpoint = baseURL
            .appendingPathComponent("collections")
            .appendingPathComponent(collectionName)
            .appendingPathComponent("points")

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "wait", value: "true")]

        guard let url = components?.url else {
            logger.error("💥 😭 QDRANT PORTAL CONSTRUCTION TEMPORARILY HALTED! Invalid query URL components.")
            self.isDirty = true
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            let upsertRequest = QdrantUpsertRequest(points: [point])
            let mysticalData = try encoder.encode(upsertRequest)
            request.httpBody = mysticalData

            logger.debug("🌐 ✨ TRANSMITTING VECTOR WAVE TO QDRANT PORTAL... Point: \(point.id)")
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("🌩️ Temporary storm: Response was not HTTPURLResponse")
                self.isDirty = true
                return false
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("🌩️ Temporary storm: HTTP status \(httpResponse.statusCode) from Qdrant REST API")
                self.isDirty = true
                return false
            }

            logger.info("🎉 ✨ VECTOR ALCHEMY MASTERPIECE COMPLETE! pointId: \(point.id)")
            return true
        } catch {
            // 🎭 Fail-open: never rethrow — the Dream loop keeps dancing.
            logger.error("🌩️ Temporary setback: \(error.localizedDescription)")
            logger.error("🎭 But the show must go on... Fail-Open recovery activated! No interruption to the stream.")
            self.isDirty = true
            return false
        }
    }

    /// 🌟 The High-Level Point Ingestion - From Raw Wisdom to Spatial Point
    /// Builds a thin §13 point (no full body) and upserts fail-open.
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
        let point = makePoint(
            contentHash: contentHash,
            vector: vector,
            visibility: visibility,
            project: project,
            date: date,
            tags: tags,
            sourcePath: sourcePath
        )
        return await indexPoint(point)
    }

    /// 🌟 The Purification Ritual - Resetting the Dirty Flag
    public func resetDirty() {
        logger.info("💎 Purifying the Qdrant index state... isDirty reset to false")
        self.isDirty = false
    }
}
