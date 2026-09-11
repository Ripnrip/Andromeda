import AndromedaHTTP
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

/// Gate-2 proof for the loopback control plane (pillar 3): the routes exist,
/// the bearer gate holds, the curated state contract is stable, and typed
/// dispatch rejects unknown actions with the full catalogue in the error.
@Suite("AndromedaHTTP.ControlPlaneRoute")
struct ControlPlaneRouteTests {
    private static let bearer = "control-plane-test-bearer"

    /// Fixture state source — a fixed snapshot plus capture counting.
    private struct FixtureState: ControlPlaneStateSourcing {
        func snapshot() async throws -> ControlPlaneSnapshot {
            ControlPlaneSnapshot(
                service: "Andromeda Runtime",
                version: "0.3.0-test",
                surfaces: ["http", "mcp", "control"],
                counts: .init(memories: 7, projectionBacklog: 2),
                capturedAt: 1_757_600_000
            )
        }
    }

    /// Fixture dispatcher — records dispatched actions, returns ok outcomes.
    private final class FixtureActions: ControlActionDispatching, @unchecked Sendable {
        private(set) var dispatched: [ControlAction] = []

        func dispatch(_ action: ControlAction) async -> ControlActionOutcome {
            dispatched.append(action)
            return ControlActionOutcome(action: action.rawValue, status: .ok, detail: "fixture")
        }
    }

    private func makeApp(actions: FixtureActions = FixtureActions()) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        ControlPlaneRoute(
            state: FixtureState(),
            actions: actions,
            bearerToken: Self.bearer
        ).register(on: router)
        return Application(router: router)
    }

    @Test("state requires bearer — 401 without, snapshot with")
    func stateBearerGate() async throws {
        try await makeApp().test(.router) { client in
            let denied = try await client.execute(uri: "/control/state", method: .get)
            #expect(denied.status == .unauthorized)

            let allowed = try await client.execute(
                uri: "/control/state",
                method: .get,
                headers: [.authorization: "Bearer \(Self.bearer)"]
            )
            #expect(allowed.status == .ok)

            let snapshot = try JSONDecoder().decode(
                ControlPlaneSnapshot.self,
                from: Data(allowed.body.readableBytesView)
            )
            #expect(snapshot.service == "Andromeda Runtime")
            #expect(snapshot.surfaces.contains("control"))
            #expect(snapshot.counts.memories == 7)
            #expect(snapshot.counts.projectionBacklog == 2)
        }
    }

    @Test("wrong bearer is still 401")
    func wrongBearerRejected() async throws {
        try await makeApp().test(.router) { client in
            let denied = try await client.execute(
                uri: "/control/state",
                method: .get,
                headers: [.authorization: "Bearer wrong-token"]
            )
            #expect(denied.status == .unauthorized)
        }
    }

    @Test("action dispatches typed enum and reports outcome")
    func actionDispatch() async throws {
        let actions = FixtureActions()
        try await makeApp(actions: actions).test(.router) { client in
            let body = try ByteBuffer(data: JSONEncoder().encode(ControlActionRequest(action: "drain-projections")))
            let response = try await client.execute(
                uri: "/control/action",
                method: .post,
                headers: [
                    .authorization: "Bearer \(Self.bearer)",
                    .contentType: "application/json",
                ],
                body: body
            )
            #expect(response.status == .ok)
            let outcome = try JSONDecoder().decode(
                ControlActionOutcome.self,
                from: Data(response.body.readableBytesView)
            )
            #expect(outcome.action == "drain-projections")
            #expect(outcome.status == .ok)
            #expect(actions.dispatched == [.drainProjections])
        }
    }

    @Test("unknown action is a 400 naming the catalogue")
    func unknownActionRejected() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"delete-everything"}"#.utf8))
            let response = try await client.execute(
                uri: "/control/action",
                method: .post,
                headers: [
                    .authorization: "Bearer \(Self.bearer)",
                    .contentType: "application/json",
                ],
                body: body
            )
            #expect(response.status == .badRequest)
            let text = String(buffer: response.body)
            #expect(text.contains("unknown action 'delete-everything'"))
            #expect(text.contains("drain-projections"))
        }
    }

    @Test("action without bearer is 401")
    func actionBearerGate() async throws {
        try await makeApp().test(.router) { client in
            let body = ByteBuffer(data: Data(#"{"action":"drain-projections"}"#.utf8))
            let response = try await client.execute(
                uri: "/control/action",
                method: .post,
                headers: [.contentType: "application/json"],
                body: body
            )
            #expect(response.status == .unauthorized)
        }
    }

    @Test("actions catalogue lists every case — surfaces generate from one list")
    func actionsCatalogue() async throws {
        try await makeApp().test(.router) { client in
            let response = try await client.execute(
                uri: "/control/actions",
                method: .get,
                headers: [.authorization: "Bearer \(Self.bearer)"]
            )
            #expect(response.status == .ok)
            let payload = try JSONDecoder().decode([String: [String]].self, from: Data(response.body.readableBytesView))
            #expect(payload["actions"] == ControlAction.allCases.map(\.rawValue).sorted())
        }
    }

    @Test("env gate arms only on ANDROMEDA_CONTROL_PLANE=1")
    func envGate() {
        #expect(!ControlPlaneRoute.isEnabled(environment: [:]))
        #expect(!ControlPlaneRoute.isEnabled(environment: ["ANDROMEDA_CONTROL_PLANE": "0"]))
        #expect(!ControlPlaneRoute.isEnabled(environment: ["ANDROMEDA_CONTROL_PLANE": "true"]))
        #expect(ControlPlaneRoute.isEnabled(environment: ["ANDROMEDA_CONTROL_PLANE": "1"]))
    }
}
