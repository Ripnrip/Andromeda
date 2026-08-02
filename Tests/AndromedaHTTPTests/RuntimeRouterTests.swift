import AndromedaDomain
import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@Suite("AndromedaHTTP.RuntimeRouter")
struct RuntimeRouterTests {
    @Test("remember and recall round-trip through HTTP")
    func rememberAndRecallRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        let journal = try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl"))
        let store = try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memories.sqlite3"))
        let runtime = MemoryRuntime(
            journal: journal,
            operationalStore: store,
            clock: FixedClock(date: Date(timeIntervalSince1970: 1_722_000_000)),
            uuidProvider: DeterministicUUIDProvider(
                values: [
                    UUID(uuidString: "77777777-7777-7777-7777-777777777771")!,
                    UUID(uuidString: "77777777-7777-7777-7777-777777777772")!,
                    UUID(uuidString: "77777777-7777-7777-7777-777777777773")!,
                ]
            )
        )
        let app = Application(
            router: RuntimeRouter(
                healthProvider: StaticHealthProvider(
                    status: RuntimeHealthStatus(
                        status: "healthy",
                        service: "Andromeda Runtime",
                        version: "0.3.0-runtime-v2-m2",
                        journal: "jsonl"
                    )
                ),
                memoryRuntime: runtime
            ).build()
        )

        let remember = RememberIntent(
            scope: EventScope(
                projectID: ProjectID(rawValue: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!),
                sessionID: SessionID(rawValue: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!)
            ),
            source: MemorySource(subsystem: "tests", actor: "http", label: "route"),
            content: "Memory recall should round-trip through the HTTP layer.",
            kind: .workflow,
            privacyLevel: .project,
            tags: ["HTTP", "Memory"],
            metadata: ["route": "remember"],
            idempotencyKey: "http-remember-1"
        )

        try await app.test(.router) { client in
            let rememberData = try JSONEncoder().encode(remember)
            try await client.execute(
                uri: "/v1/memory/remember",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: rememberData)
            ) { response in
                #expect(response.status == .ok)
                let payload = try JSONDecoder().decode(
                    MemoryRememberResponse.self,
                    from: Data(response.body.readableBytesView)
                )
                #expect(payload.retryStatus == .none)
                #expect(payload.sinkReceipts.contains(where: { $0.sinkID == "memory.operational.sqlite" }))
            }

            let recall = RecallRequest(
                query: "round-trip HTTP memory",
                scope: EventScope(projectID: remember.scope.projectID),
                privacyCeiling: .project,
                resultLimit: 5
            )
            let recallData = try JSONEncoder().encode(recall)
            try await client.execute(
                uri: "/v1/memory/recall",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: recallData)
            ) { response in
                #expect(response.status == .ok)
                let payload = try JSONDecoder().decode(
                    MemoryRecallResponse.self,
                    from: Data(response.body.readableBytesView)
                )
                #expect(payload.records.count == 1)
                #expect(payload.records.first?.record.summary.contains("Memory recall should round-trip") == true)
            }
        }
    }

    @Test("invalid remember content returns a typed bad request")
    func invalidRememberReturnsBadRequest() async throws {
        let directory = try makeTemporaryDirectory()
        let journal = try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl"))
        let store = try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memories.sqlite3"))
        let runtime = MemoryRuntime(journal: journal, operationalStore: store)
        let app = Application(
            router: RuntimeRouter(
                healthProvider: StaticHealthProvider(
                    status: RuntimeHealthStatus(
                        status: "healthy",
                        service: "Andromeda Runtime",
                        version: "0.3.0-runtime-v2-m2",
                        journal: "jsonl"
                    )
                ),
                memoryRuntime: runtime
            ).build()
        )

        let request = RememberIntent(
            scope: EventScope(projectID: ProjectID(rawValue: UUID(uuidString: "10101010-1010-1010-1010-101010101010")!)),
            source: MemorySource(subsystem: "tests", actor: "http", label: "invalid"),
            content: "   ",
            kind: .note,
            privacyLevel: .project,
            idempotencyKey: "bad-request"
        )

        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(request)
            try await client.execute(
                uri: "/v1/memory/remember",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: body)
            ) { response in
                #expect(response.status == .badRequest)
                let payload = String(buffer: response.body)
                #expect(payload.contains("Memory content must not be empty"))
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StaticHealthProvider: HealthStatusProviding {
    let status: RuntimeHealthStatus

    func healthStatus() async -> RuntimeHealthStatus {
        status
    }
}
