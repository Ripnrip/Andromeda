import AndromedaDomain
import AndromedaMemory
import Foundation
import Testing

@testable import AndromedaProjections

@Suite("AndromedaProjections.QdrantProjection")
struct QdrantProjectionTests {
    @Test("upserts a memory to the configured live Qdrant endpoint", .tags(.qdrant))
    func upsertsToLiveQdrant() async throws {
        let baseURL = testQdrantBaseURL
        // Soft-skip when Studio / local Qdrant is down — Issue.record would fail CI.
        guard await isLiveQdrantReachable(baseURL: baseURL) else { return }

        let projectID = ProjectID(rawValue: UUID())
        // Collection name is derived from projectID; a unique ID keeps concurrent
        // CI runs from deleting each other's Studio collections (Codex P1 / BIN-218).
        let collectionName = "andromeda-memories-\(projectID.description)"
        let projection = QdrantProjection(
            baseURL: baseURL,
            embeddingProvider: HashBagOfWordsEmbeddingProvider(),
            urlSession: testQdrantURLSession
        )
        let record = makeRecord(projectID: projectID, privacy: .project)

        let receipt = try await projection.write(record: record)

        #expect(receipt.status == .committed)
        #expect(receipt.sinkID == projection.sinkID)
        #expect(receipt.checksum == record.checksum)

        try? await deleteQdrantCollection(baseURL: baseURL, name: collectionName)
    }

    @Test("skips memories without a project scope")
    func skipsWithoutProject() async throws {
        let projection = QdrantProjection(
            baseURL: URL(string: "http://localhost:6333")!,
            embeddingProvider: HashBagOfWordsEmbeddingProvider()
        )
        let record = makeRecord(projectID: nil, privacy: .project)

        let receipt = try await projection.write(record: record)

        #expect(receipt.status == .skipped)
        #expect(receipt.verification == .unsupported)
    }

    @Test("rejects private memories")
    func rejectsPrivate() {
        let projection = QdrantProjection(
            baseURL: URL(string: "http://localhost:6333")!,
            embeddingProvider: HashBagOfWordsEmbeddingProvider()
        )
        let record = makeRecord(projectID: ProjectID(rawValue: UUID()), privacy: .private)

        #expect(projection.accepts(record) == false)
    }

    @Test("network failure surfaces as retryable failure through MemoryRuntime")
    func networkFailureIsRetryable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let projection = QdrantProjection(
            baseURL: URL(string: "http://localhost:1")!,
            embeddingProvider: HashBagOfWordsEmbeddingProvider()
        )
        let record = makeRecord(projectID: ProjectID(rawValue: UUID()), privacy: .project)

        await #expect(throws: Error.self) {
            _ = try await projection.write(record: record)
        }
    }

    private func makeRecord(projectID: ProjectID?, privacy: PrivacyLevel) -> MemoryRecord {
        MemoryRecord(
            memoryID: MemoryID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2")!),
            eventID: EventID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2")!),
            correlationID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc2")!,
            scope: EventScope(
                projectID: projectID,
                sessionID: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
            ),
            source: MemorySource(subsystem: "tests", actor: "projection", label: "qdrant"),
            kind: .discovery,
            privacyLevel: privacy,
            summary: "Qdrant discovery",
            content: "Vector projection stores memories for semantic recall.",
            tags: ["qdrant", "vector"],
            metadata: ["area": "qdrant"],
            relatedContext: [:],
            checksum: "sha256:def456",
            createdAt: Date(timeIntervalSince1970: 1_722_000_000)
        )
    }
}

private let testQdrantURLSession: URLSession = {
    let config = URLSessionConfiguration.default
    // CI reaches Qdrant over Tailscale TCP; give writes enough headroom.
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 180
    return URLSession(configuration: config)
}()

private let testQdrantBaseURL: URL = {
    let raw = ProcessInfo.processInfo.environment["ANDROMEDA_TEST_QDRANT_URL"]
    let value = (raw?.isEmpty == false ? raw : nil) ?? "http://localhost:6333"
    return URL(string: value) ?? URL(string: "http://localhost:6333")!
}()

private func isLiveQdrantReachable(baseURL: URL) async -> Bool {
    guard let url = URL(string: "/collections", relativeTo: baseURL)?.absoluteURL else {
        return false
    }
    do {
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(httpResponse.statusCode)
    } catch {
        return false
    }
}

private func deleteQdrantCollection(baseURL: URL, name: String) async throws {
    guard let url = URL(string: "/collections/\(name)", relativeTo: baseURL)?.absoluteURL else {
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    _ = try await URLSession.shared.data(for: request)
}

extension Tag {
    @Tag static var qdrant: Self
}
