import AndromedaDomain
import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

/**
 * 🧪 The DashboardRoute Tests — Contract Pins for the Human Console
 *
 * "If someone renames the remember portal or strips the wordmark,
 *  these rites fail loudly before a guest VM agent ever notices."
 *
 * - The Theatrical Quality Assurance Virtuoso of Runtime Projections
 */
@Suite("AndromedaHTTP.DashboardRoute")
struct DashboardRouteTests {
    /// 🌟 GET / must serve the embedded console with the Andromeda wordmark.
    @Test("GET / returns 200 text/html containing Andromeda wordmark")
    func dashboardHTMLServesWordmark() async throws {
        let runtime = try makeMemoryRuntime()
        let router = Router(context: BasicRequestContext.self)
        DashboardRoute(memoryRuntime: runtime).register(on: router)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .ok)
                let contentType = response.headers[.contentType] ?? ""
                #expect(contentType.contains("text/html"))
                let body = String(buffer: response.body)
                // Design system wordmark: Instrument Serif "Andromeda." with teal dot
                #expect(body.contains("Andromeda"))
                // Verify design system CSS tokens are present
                #expect(body.contains("--teal"))
                #expect(body.contains("--bg"))
            }
        }
    }

    /// 📌 Contract pins: the page's JS must still target the real memory HTTP paths.
    /// A future refactor that renames routes without updating the dashboard fails here.
    @Test("dashboard HTML JS contains remember and recall API path contracts")
    func dashboardHTMLPinsMemoryAPIPaths() async throws {
        let runtime = try makeMemoryRuntime()
        let router = Router(context: BasicRequestContext.self)
        DashboardRoute(memoryRuntime: runtime).register(on: router)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                // 🎭 These strings are the UI↔API handshake — do not soft-match.
                #expect(body.contains("/v1/memory/remember"))
                #expect(body.contains("/v1/memory/recall"))
            }
        }
    }

    /// 📜 List proxy should accept projectID + limit and return JSON.
    @Test("GET /v1/memories proxies recall for a project scope")
    func memoriesListProxiesRecall() async throws {
        let directory = try makeTemporaryDirectory()
        let journal = try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl"))
        let store = try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memories.sqlite3"))
        let runtime = MemoryRuntime(journal: journal, operationalStore: store)

        let projectID = DashboardRoute.demoProjectID
        _ = try await runtime.remember(
            RememberIntent(
                scope: EventScope(projectID: projectID),
                source: MemorySource(subsystem: "tests", actor: "dashboard", label: "seed"),
                content: "Dashboard list proxy should surface this memory.",
                kind: .note,
                privacyLevel: .project,
                tags: ["dashboard"],
                idempotencyKey: "dashboard-list-seed-1"
            )
        )

        let router = Router(context: BasicRequestContext.self)
        DashboardRoute(memoryRuntime: runtime).register(on: router)
        let app = Application(router: router)

        let uri = "/v1/memories?projectID=\(projectID.rawValue.uuidString)&limit=10"
        try await app.test(.router) { client in
            try await client.execute(uri: uri, method: .get) { response in
                #expect(response.status == .ok)
                let payload = try JSONDecoder().decode(
                    MemoryRecallResponse.self,
                    from: Data(response.body.readableBytesView)
                )
                #expect(payload.records.count >= 1)
                #expect(
                    payload.records.contains(where: {
                        $0.record.summary.contains("Dashboard list proxy")
                    })
                )
            }
        }
    }

    // 🏗️ Spin a disposable memory runtime for pure HTML route checks.
    private func makeMemoryRuntime() throws -> MemoryRuntime {
        let directory = try makeTemporaryDirectory()
        let journal = try JSONLineEventJournal(fileURL: directory.appending(path: "journal.jsonl"))
        let store = try SQLiteMemoryOperationalStore(databaseURL: directory.appending(path: "memories.sqlite3"))
        return MemoryRuntime(journal: journal, operationalStore: store)
    }

    // 🗂️ Ephemeral sandboxes — no cosmic litter left behind.
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
