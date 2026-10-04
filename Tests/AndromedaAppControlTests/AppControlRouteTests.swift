import AndromedaAppControl
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

/// 🧪 Gate proof for the HUD's loopback App Control plane (HAB-838): routes
/// exist ungated-by-design (the moat is the 127.0.0.1 bind), the curated
/// state contract is stable, typed dispatch rejects unknown actions with the
/// full catalogue, and submit-query demands its payload.
@Suite("AndromedaAppControl.AppControlRoute")
struct AppControlRouteTests {
    /// Fixture state source — a fixed snapshot plus capture counting.
    private struct FixtureState: AppControlStateSourcing {
        func snapshot() async throws -> AppControlSnapshot {
            AppControlSnapshot(
                service: "AndromedaHUD",
                version: AppControlSnapshot.contractVersion,
                isReady: true,
                query: "recall fleet",
                outcome: .init(kind: "recalled", summary: "Recalled 2 memory hits", hits: 2),
                recentQueries: ["recall fleet", "project.state"],
                fleetPulse: .init(status: "yellow", attentionCount: 3, detail: "2 hosts degraded"),
                showsResultsPanel: true,
                capturedAt: 1_757_600_000
            )
        }
    }

    /// Fixture dispatcher — records typed actions, returns ok outcomes.
    private final class FixtureActions: AppControlDispatching, @unchecked Sendable {
        private(set) var dispatched: [AppControlAction] = []

        func dispatch(_ action: AppControlAction) async -> AppControlOutcome {
            dispatched.append(action)
            return AppControlOutcome(action: action.name, status: .ok, detail: "fixture")
        }
    }

    /// Fixture screenshotter — PNG magic bytes, no window server required.
    private struct FixtureScreenshots: AppControlScreenshotting {
        static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func pngData() async throws -> Data {
            Self.pngBytes
        }
    }

    private func makeApp(actions: FixtureActions = FixtureActions()) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        AppControlRoute(
            state: FixtureState(),
            actions: actions,
            screenshotter: FixtureScreenshots()
        ).register(on: router)
        return Application(router: router)
    }

    @Test("state serves the curated snapshot ungated — the bind address is the moat")
    func stateServed() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(uri: "/state", method: .get)
            #expect(response.status == .ok)
            let snapshot = try JSONDecoder().decode(
                AppControlSnapshot.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(snapshot.service == "AndromedaHUD")
            #expect(snapshot.version == AppControlSnapshot.contractVersion)
            #expect(snapshot.isReady == true)
            #expect(snapshot.query == "recall fleet")
            #expect(snapshot.outcome.kind == "recalled")
            #expect(snapshot.outcome.hits == 2)
            #expect(snapshot.recentQueries == ["recall fleet", "project.state"])
            #expect(snapshot.fleetPulse.status == "yellow")
            #expect(snapshot.fleetPulse.attentionCount == 3)
            #expect(snapshot.showsResultsPanel == true)
        }
    }

    @Test("action dispatches typed enum and reports outcome")
    func actionDispatch() async throws {
        let actions = FixtureActions()
        try await makeApp(actions: actions).test(.router) { client in
            let body = try ByteBuffer(
                data: JSONEncoder().encode(AppControlActionRequest(action: "hud.focus-search"))
            )
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .ok)
            let outcome = try JSONDecoder().decode(
                AppControlOutcome.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(outcome.action == "hud.focus-search")
            #expect(outcome.status == .ok)
            #expect(actions.dispatched == [.focusSearch])
        }
    }

    @Test("submit-query carries its payload into the typed action")
    func submitQueryPayload() async throws {
        let actions = FixtureActions()
        try await makeApp(actions: actions).test(.router) { client in
            let body = try ByteBuffer(
                data: JSONEncoder().encode(AppControlActionRequest(action: "hud.submit-query", query: "store a thought"))
            )
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .ok)
            #expect(actions.dispatched == [.submitQuery(query: "store a thought")])
        }
    }

    @Test("submit-query without a payload is a 400 naming the requirement")
    func submitQueryMissingPayload() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"hud.submit-query"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .badRequest)
            let text = String(buffer: response.body)
            #expect(text.contains("hud.submit-query"))
            #expect(text.contains("query"))
        }
    }

    @Test("unknown action is a 400 naming the catalogue")
    func unknownActionRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"hud.self-destruct"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .badRequest)
            let text = String(buffer: response.body)
            #expect(text.contains("unknown action 'hud.self-destruct'"))
            // The whole catalogue, sorted — the caller never guesses.
            for verb in AppControlVerb.allCases {
                #expect(text.contains(verb.rawValue))
            }
        }
    }

    @Test("error envelope stays valid JSON for hostile action names (encoder, not string escape)")
    func hostileActionNameProducesValidJSON() async throws {
        // Regression law from the control plane: error bodies are built by
        // JSONEncoder — never interpolated — so hostile names cannot corrupt
        // the envelope.
        try await makeApp().test(.router) { client in
            let hostile = "bad\\q \"quote\"\nnewline"
            let body = ByteBuffer(data: try JSONEncoder().encode(AppControlActionRequest(action: hostile)))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .badRequest)
            let decoded = try JSONDecoder().decode([String: String].self, from: Data(response.body.readableBytesView))
            #expect(decoded["error"]?.contains(hostile) == true)
        }
    }

    @Test("garbage body is a 400, not a crash")
    func garbageBodyRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data("not json at all".utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("actions catalogue lists every verb — surfaces generate from one list")
    func actionsCatalogue() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(uri: "/actions", method: .get)
            #expect(response.status == .ok)
            let payload = try JSONDecoder().decode([String: [String]].self, from: Data(response.body.readableBytesView))
            #expect(payload["actions"] == AppControlVerb.allCases.map(\.rawValue).sorted())
        }
    }

    @Test("screenshot returns PNG bytes with the image content type")
    func screenshotServed() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(uri: "/screenshot", method: .get)
            #expect(response.status == .ok)
            #expect(response.headers[.contentType] == "image/png")
            let data = Data(response.body.readableBytesView)
            #expect(data == FixtureScreenshots.pngBytes)
        }
    }

    @Test("env gate arms only on ANDROMEDA_APP_CONTROL=1")
    func envGate() {
        #expect(!AppControlServer.isEnabled(environment: [:]))
        #expect(!AppControlServer.isEnabled(environment: ["ANDROMEDA_APP_CONTROL": "0"]))
        #expect(!AppControlServer.isEnabled(environment: ["ANDROMEDA_APP_CONTROL": "true"]))
        #expect(AppControlServer.isEnabled(environment: ["ANDROMEDA_APP_CONTROL": "1"]))
    }

    @Test("port honors the override and defaults to the App Control port")
    func portSelection() {
        #expect(AppControlServer.port(environment: [:]) == AppControlServer.defaultPort)
        #expect(AppControlServer.port(environment: ["ANDROMEDA_APP_CONTROL_PORT": "8799"]) == 8799)
        // Nonsense falls back rather than crashes.
        #expect(AppControlServer.port(environment: ["ANDROMEDA_APP_CONTROL_PORT": "not-a-port"]) == AppControlServer.defaultPort)
    }

    @Test("every verb maps to exactly one typed action name — parity")
    func verbActionParity() {
        let actions: [AppControlAction] = [
            .submitQuery(query: "q"),
            .focusSearch,
            .dismissResults,
            .refreshFleetPulse,
        ]
        #expect(actions.map(\.name).sorted() == AppControlVerb.allCases.map(\.rawValue).sorted())
        for verb in AppControlVerb.allCases {
            #expect(AppControlVerb(rawValue: verb.rawValue) == verb)
        }
    }
}
