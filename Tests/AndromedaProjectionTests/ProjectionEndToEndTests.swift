import AndromedaDomain
import AndromedaJournal
import AndromedaMemory
import Foundation
import Testing

@testable import AndromedaProjections

@Suite("AndromedaProjections.EndToEnd")
struct ProjectionEndToEndTests {
    @Test("remember writes Markdown and Qdrant receipts")
    func rememberProducesMarkdownAndQdrantReceipts() async throws {
        let directory = try makeTemporaryDirectory()
        let journal = try JSONLineEventJournal(fileURL: directory.appendingPathComponent("journal.jsonl"))
        let store = try SQLiteMemoryOperationalStore(databaseURL: directory.appendingPathComponent("memories.sqlite3"))
        let vaultURL = directory.appendingPathComponent("vault")
        let markdownSink = MarkdownVaultProjection(vaultDirectoryURL: vaultURL)

        let qdrantBaseURL = projectionTestQdrantBaseURL
        let qdrantSink = QdrantProjection(
            baseURL: qdrantBaseURL,
            embeddingProvider: HashBagOfWordsEmbeddingProvider()
        )
        let projectionRuntime = ProjectionRuntime(
            sinks: [markdownSink, qdrantSink],
            queue: DurableRetryQueue(fileURL: directory.appendingPathComponent("retry.jsonl"))
        )

        let qdrantReachable = await isQdrantReachable(baseURL: qdrantBaseURL)
        let runtime = MemoryRuntime(
            journal: journal,
            operationalStore: store,
            projectionSinks: [markdownSink, qdrantSink],
            retryQueue: projectionRuntime,
            clock: FixedClock(date: Date(timeIntervalSince1970: 1_722_000_000)),
            uuidProvider: DeterministicUUIDProvider(
                values: [
                    UUID(uuidString: "77777777-7777-7777-7777-777777777771")!,
                    UUID(uuidString: "77777777-7777-7777-7777-777777777772")!,
                    UUID(uuidString: "77777777-7777-7777-7777-777777777773")!,
                ]
            )
        )

        let projectID = ProjectID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let response = try await runtime.remember(
            RememberIntent(
                scope: EventScope(
                    projectID: projectID,
                    sessionID: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
                ),
                source: MemorySource(subsystem: "tests", actor: "e2e", label: "projection"),
                content: "End-to-end memory projects to Markdown and Qdrant.",
                kind: .decision,
                privacyLevel: .project,
                tags: ["e2e", "projection"],
                idempotencyKey: "e2e-projection-1"
            )
        )

        let markdownReceipt = response.sinkReceipts.first { $0.sinkID == markdownSink.sinkID }
        #expect(markdownReceipt?.status == .committed)

        let fileURL = vaultURL.appendingPathComponent("\(response.memoryID.description).md")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        if qdrantReachable {
            let qdrantReceipt = response.sinkReceipts.first { $0.sinkID == qdrantSink.sinkID }
            #expect(qdrantReceipt?.status == .committed)
            try? await deleteQdrantCollection(
                baseURL: qdrantBaseURL,
                name: "andromeda-memories-\(projectID.description)"
            )
        } else {
            let qdrantReceipt = response.sinkReceipts.first { $0.sinkID == qdrantSink.sinkID }
            #expect(qdrantReceipt?.status == .retryableFailure)
            #expect(response.retryStatus == .pending)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private let projectionTestQdrantBaseURL: URL = {
    let value = ProcessInfo.processInfo.environment["ANDROMEDA_TEST_QDRANT_URL"]
        ?? "http://localhost:6333"
    return URL(string: value)!
}()

private func isQdrantReachable(baseURL: URL) async -> Bool {
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
