import AndromedaDomain
import AndromedaMemory
import Foundation

/// Projects memories into a Qdrant vector collection over HTTP.
///
/// Each project receives its own collection named `andromeda-memories-<projectID>`.
/// Private memories are rejected. Network or Qdrant errors are thrown so the
/// caller can emit a `retryableFailure` receipt and retry later.
public actor QdrantProjection: MemoryProjectionSink {
    public nonisolated let sinkID = "memory.projection.qdrant"
    public nonisolated let schemaVersion = "memory.projection.qdrant.v1"

    private let baseURL: URL
    private let embeddingProvider: any EmbeddingProvider
    private let urlSession: URLSession

    public init(
        baseURL: URL,
        embeddingProvider: any EmbeddingProvider,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.embeddingProvider = embeddingProvider
        self.urlSession = urlSession
    }

    public nonisolated func accepts(_ record: MemoryRecord) -> Bool {
        record.privacyLevel != .private
    }

    public func write(record: MemoryRecord) async throws -> MemoryWriteReceipt {
        guard let projectID = record.scope.projectID else {
            return MemoryWriteReceipt(
                memoryID: record.memoryID,
                sinkID: sinkID,
                schemaVersion: schemaVersion,
                checksum: record.checksum,
                status: .skipped,
                verification: .unsupported
            )
        }

        let collectionName = "andromeda-memories-\(projectID.description)"
        try await ensureCollectionExists(name: collectionName)

        try await upsert(record: record, into: collectionName)

        return MemoryWriteReceipt(
            memoryID: record.memoryID,
            sinkID: sinkID,
            schemaVersion: schemaVersion,
            checksum: record.checksum,
            status: .committed,
            verification: .pending
        )
    }

    private func ensureCollectionExists(name: String) async throws {
        let request = try makeRequest(path: "/collections/\(name)", method: "PUT", body: [
            "vectors": [
                "size": embeddingProvider.dimension,
                "distance": "Cosine",
            ],
        ])
        let (_, response) = try await urlSession.data(for: request)
        // 409 Conflict means the collection already exists, which is fine for
        // idempotent writes.
        try checkResponse(
            response,
            context: "create collection \(name)",
            acceptableStatusCodes: 200..<300, [409]
        )
    }

    private func upsert(record: MemoryRecord, into collectionName: String) async throws {
        let vector = embeddingProvider.embedding(for: record.content)
        let payload: [String: Any] = [
            "memory_id": record.memoryID.description,
            "kind": record.kind.rawValue,
            "privacy": record.privacyLevel.rawValue,
            "summary": record.summary,
            "content": record.content,
            "tags": record.tags,
            "checksum": record.checksum,
            "created_at": ISO8601DateFormatter().string(from: record.createdAt),
        ]

        let point: [String: Any] = [
            "id": record.memoryID.description,
            "vector": vector,
            "payload": payload,
        ]

        let request = try makeRequest(
            path: "/collections/\(collectionName)/points",
            method: "PUT",
            body: ["points": [point]]
        )
        let (_, response) = try await urlSession.data(for: request)
        try checkResponse(response, context: "upsert point \(record.memoryID.description)")
    }

    private func makeRequest(path: String, method: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw QdrantProjectionError.invalidURL("Could not construct URL for \(path) relative to \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func checkResponse(
        _ response: URLResponse,
        context: String,
        acceptableStatusCodes: Range<Int> = 200..<300,
        _ additionalStatusCodes: [Int] = []
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QdrantProjectionError.networkFailure("Non-HTTP response for \(context)")
        }
        guard acceptableStatusCodes.contains(httpResponse.statusCode)
            || additionalStatusCodes.contains(httpResponse.statusCode)
        else {
            throw QdrantProjectionError.qdrantFailure(context, statusCode: httpResponse.statusCode)
        }
    }
}

public enum QdrantProjectionError: Error, Sendable {
    case invalidURL(String)
    case networkFailure(String)
    case qdrantFailure(String, statusCode: Int)
}
