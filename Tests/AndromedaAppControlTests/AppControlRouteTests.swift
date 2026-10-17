import AndromedaAppControl
import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import Testing

/// 🧪 Gate proof for the HUD's loopback App Control plane (HAB-838/HAB-866):
/// every route sits behind the triple lock (bearer + Origin/Host allowlist +
/// JSON content-type on mutating routes) and fails closed — the 127.0.0.1
/// bind is placement, not permission. Also proves the curated state contract,
/// typed dispatch rejects unknown actions with the full catalogue, and
/// submit-query demands its payload.
@Suite("AndromedaAppControl.AppControlRoute")
struct AppControlRouteTests {
    /// Fixed token the test guard demands — production mints a random one.
    private static let token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

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

    /// Fixture dispatcher — an actor, so recorded dispatches are
    /// synchronized by construction, never `@unchecked` (review P3).
    private actor FixtureActions: AppControlDispatching {
        private var recorded: [AppControlAction] = []

        func dispatch(_ action: AppControlAction) async -> AppControlOutcome {
            recorded.append(action)
            return AppControlOutcome(action: action.name, status: .ok, detail: "fixture")
        }

        func dispatchedActions() -> [AppControlAction] { recorded }
    }

    /// Fixture screenshotter — PNG magic bytes, no window server required.
    private struct FixtureScreenshots: AppControlScreenshotting {
        static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func pngData() async throws -> Data {
            Self.pngBytes
        }
    }

    /// Headers a same-machine, well-behaved client sends: valid bearer and
    /// a loopback Origin. No `Origin` at all (curl, same-origin tooling) is
    /// equally valid — the router-test client's authority is always
    /// "localhost", which the Host lock accepts.
    private static func authedHeaders(
        origin: String? = nil,
        authorization: String? = "Bearer \(token)"
    ) -> HTTPFields {
        var headers = HTTPFields()
        if let authorization { headers[.authorization] = authorization }
        if let origin { headers[.origin] = origin }
        return headers
    }

    private func makeApp(actions: FixtureActions = FixtureActions()) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        AppControlRoute(
            state: FixtureState(),
            actions: actions,
            screenshotter: FixtureScreenshots(),
            gate: AppControlGuard(bearerToken: Self.token)
        ).register(on: router)
        return Application(router: router)
    }

    // MARK: - HAB-866 negative gates (fail closed)

    @Test("missing bearer is a 401 with a WWW-Authenticate challenge")
    func missingBearerRejected() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/state",
                method: .get,
                headers: Self.authedHeaders(authorization: nil)
            )
            #expect(response.status == .unauthorized)
            #expect(response.headers[.wwwAuthenticate]?.contains("Bearer") == true)
            let text = String(buffer: response.body)
            #expect(text.contains("required"))
        }
    }

    @Test("invalid bearer is a 401 — the token is not a formality")
    func invalidBearerRejected() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/state",
                method: .get,
                headers: Self.authedHeaders(authorization: "Bearer deadbeef")
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test("foreign Origin is a 403 even with a valid bearer — the DNS-rebinding lock")
    func hostileOriginRejected() async throws {
        try await makeApp().test(.router) { client in
            for origin in ["https://evil.example", "http://evil.example:8791", "null"] {
                let response = try await client.execute(
                    uri: "/state",
                    method: .get,
                    headers: Self.authedHeaders(origin: origin)
                )
                #expect(response.status == .forbidden, "Origin '\(origin)' must be rejected")
            }
        }
    }

    @Test("foreign or missing Host authority is a 403 even with a valid bearer")
    func foreignHostRejected() async throws {
        // The Host header surfaces as the request authority (HTTPTypes moves
        // it out of the header fields), so hostile authorities are proven at
        // the guard — the wire equivalent flows through the same check.
        let gate = AppControlGuard(bearerToken: Self.token)
        for authority in [
            "evil.example",
            "127.0.0.1.evil.example",
            "sub.localhost",
            "127.0.0.2:80",
            "",
            nil as String?,
        ] {
            let rejection = gate.authorize(Self.authedHeaders(), authority: authority)
            guard case .hostForbidden = rejection else {
                Issue.record("authority '\(authority ?? "<nil>")' must be hostForbidden, got \(String(describing: rejection))")
                continue
            }
        }
        // Loopback authorities — with ports — clear the lock.
        for authority in ["127.0.0.1", "127.0.0.1:8791", "localhost:4200", "[::1]:8791"] {
            #expect(gate.authorize(Self.authedHeaders(), authority: authority) == nil)
        }
    }

    @Test("text/plain body is a 415 — content type is checked before parsing")
    func textPlainBodyRejected() async throws {
        try await makeApp().test(.router) { client in
            // A perfectly valid JSON payload wearing the wrong content type
            // must never reach the decoder.
            let body = ByteBuffer(data: Data(#"{"action":"hud.focus-search"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: Self.authedHeaders().with(.contentType, "text/plain"),
                body: body
            )
            #expect(response.status == .unsupportedMediaType)
            let text = String(buffer: response.body)
            // JSON-escaping turns "/" into "\/" — assert on the verdict and
            // the offending type, both quote-free.
            #expect(text.contains("unsupported media type"))
            #expect(text.contains("text"))
        }
    }

    @Test("missing content type on POST /action is a 415")
    func missingContentTypeRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"hud.focus-search"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: Self.authedHeaders(),
                body: body
            )
            #expect(response.status == .unsupportedMediaType)
        }
    }

    @Test("loopback origins and hosts pass — same-machine clients are the constituency")
    func loopbackOriginAllowed() async throws {
        try await makeApp().test(.router) { client in
            for origin in ["http://127.0.0.1:8791", "http://localhost:4200", "http://[::1]:8791"] {
                let response = try await client.execute(
                    uri: "/state",
                    method: .get,
                    headers: Self.authedHeaders(origin: origin)
                )
                #expect(response.status == .ok, "Origin '\(origin)' is loopback — allowed")
            }
            // localhost Host with a port is equally fine.
            let response = try await client.execute(
                uri: "/state",
                method: .get,
                headers: Self.authedHeaders(origin: "http://localhost:4200")
            )
            #expect(response.status == .ok)
        }
    }

    // MARK: - Positive paths (all behind the gate)

    @Test("state serves the curated snapshot to a bearer-holding loopback client")
    func stateServed() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/state",
                method: .get,
                headers: Self.authedHeaders()
            )
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
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .ok)
            let outcome = try JSONDecoder().decode(
                AppControlOutcome.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(outcome.action == "hud.focus-search")
            #expect(outcome.status == .ok)
            #expect(await actions.dispatchedActions() == [.focusSearch])
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
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .ok)
            #expect(await actions.dispatchedActions() == [.submitQuery(query: "store a thought")])
        }
    }

    @Test("submit-query without a payload is a 400 naming the requirement")
    func submitQueryMissingPayload() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"hud.submit-query"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .badRequest)
            let text = String(buffer: response.body)
            #expect(text.contains("hud.submit-query"))
            #expect(text.contains("query"))
        }
    }

    @Test("unknown action is a 422 naming the catalogue")
    func unknownActionRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"hud.self-destruct"}"#.utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .unprocessableContent)
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
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .unprocessableContent)
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
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("missing action field is a 400 malformed payload")
    func missingActionRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data("{}".utf8))
            let response = try await client.execute(
                uri: "/action",
                method: .post,
                headers: Self.authedHeaders().with(.contentType, "application/json"),
                body: body
            )
            #expect(response.status == .badRequest)
        }
    }

    @Test("actions catalogue lists every verb — surfaces generate from one list")
    func actionsCatalogue() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/actions",
                method: .get,
                headers: Self.authedHeaders()
            )
            #expect(response.status == .ok)
            let payload = try JSONDecoder().decode([String: [String]].self, from: Data(response.body.readableBytesView))
            #expect(payload["actions"] == AppControlVerb.allCases.map(\.rawValue).sorted())
        }
    }

    @Test("screenshot returns PNG bytes with the image content type")
    func screenshotServed() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/screenshot",
                method: .get,
                headers: Self.authedHeaders()
            )
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

    // MARK: - Token custody (HAB-866)

    @Test("token persists with 0600 and reloads identically")
    func tokenPersistence() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-control-token-test-\(UInt64.random(in: 0..<UInt64.max))")
        defer { try? FileManager.default.removeItem(at: url) }

        let minted = try AppControlToken.loadOrGenerate(at: url)
        #expect(minted.count == 64) // 256-bit hex
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        let reloaded = try AppControlToken.loadOrGenerate(at: url)
        #expect(reloaded == minted)
        // Fresh mints are not the same token twice.
        #expect(AppControlToken.generate() != AppControlToken.generate())
    }

    @Test("guard parsing: host port-stripping and loopback judgement")
    func guardHostParsing() {
        #expect(AppControlGuard.hostWithoutPort("127.0.0.1:8791") == "127.0.0.1")
        #expect(AppControlGuard.hostWithoutPort("localhost") == "localhost")
        #expect(AppControlGuard.hostWithoutPort("[::1]:8791") == "[::1]")
        #expect(AppControlGuard.hostWithoutPort("evil.example") == "evil.example")
        #expect(AppControlGuard.isLoopbackHost("127.0.0.1"))
        #expect(AppControlGuard.isLoopbackHost("LOCALHOST"))
        #expect(AppControlGuard.isLoopbackHost("[::1]"))
        #expect(!AppControlGuard.isLoopbackHost("127.0.0.1.evil.example"))
        #expect(!AppControlGuard.isLoopbackHost("evil.example"))
        #expect(!AppControlGuard.isLoopbackHost("127.0.0.2"))
        #expect(AppControlGuard.constantTimeEquals("same", "same"))
        #expect(!AppControlGuard.constantTimeEquals("same", "different"))
        #expect(!AppControlGuard.constantTimeEquals("same", ""))
    }
}

private extension HTTPFields {
    /// Returns a copy carrying an extra field.
    func with(_ field: HTTPField.Name, _ value: String) -> HTTPFields {
        var copy = self
        copy[field] = value
        return copy
    }
}
