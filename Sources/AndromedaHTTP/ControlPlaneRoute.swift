import AndromedaDomain
import AndromedaMemory
import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// Curated control-plane snapshot — the `/control/state` contract.
///
/// Pillar 3 of the programmatic-app-control pattern: state is what the plane
/// *names*, never a raw object dump. Fields are additive; renames or removals
/// are breaking and need a version bump.
public struct ControlPlaneSnapshot: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public let memories: Int
        public let projectionBacklog: Int

        public init(memories: Int, projectionBacklog: Int) {
            self.memories = memories
            self.projectionBacklog = projectionBacklog
        }
    }

    /// Server identity — matches `GET /health`.
    public let service: String
    public let version: String

    /// Loopback surfaces wired into this process.
    public let surfaces: [String]

    /// Domain counts behind the capability curtain.
    public let counts: Counts

    /// Epoch seconds of capture; lets callers detect staleness.
    public let capturedAt: Double

    public init(service: String, version: String, surfaces: [String], counts: Counts, capturedAt: Double) {
        self.service = service
        self.version = version
        self.surfaces = surfaces
        self.counts = counts
        self.capturedAt = capturedAt
    }
}

/// Typed control-plane actions — one enum, not a string switch (canon:
/// rich enums over stringly-typed dispatch).
///
/// `actionNames` is the single list every surface (HTTP, CLI, future MCP)
/// generates from, so no two callers can drift.
public enum ControlAction: String, Sendable, CaseIterable, Codable {
    /// Re-drive pending projection retries now, instead of waiting for the
    /// periodic loop. Same code path `andromeda-runtime serve` runs.
    case drainProjections = "drain-projections"

    public static func named(_ raw: String) -> ControlAction? {
        ControlAction(rawValue: raw)
    }
}

/// Outcome envelope for `POST /control/action`.
public struct ControlActionOutcome: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case ok
        case error
    }

    public let action: String
    public let status: Status
    /// Human-readable result detail; safe to print (no secrets).
    public let detail: String

    public init(action: String, status: Status, detail: String) {
        self.action = action
        self.status = status
        self.detail = detail
    }
}

/// Anything that can produce the curated snapshot. Production wires the real
/// runtime; tests inject fixtures. Keeps `ControlPlaneRoute` free of server
/// internals (AndromedaHTTP must not depend on AndromedaServer).
public protocol ControlPlaneStateSourcing: Sendable {
    func snapshot() async throws -> ControlPlaneSnapshot
}

/// Anything that can execute typed control actions. The single source of
/// actions — every access surface funnels through `dispatch`, none may hold
/// logic of its own.
public protocol ControlActionDispatching: Sendable {
    func dispatch(_ action: ControlAction) async -> ControlActionOutcome
}

/// Wire format for `POST /control/action` — `{"action": "drain-projections"}`.
public struct ControlActionRequest: Codable, Sendable, Equatable {
    public let action: String

    public init(action: String) {
        self.action = action
    }
}

/// `/control/*` routes on the existing runtime router — the loopback control
/// plane (pillar 3) reusing the single Hummingbird listener instead of a
/// second host.
///
/// ## Gating
///
/// Opt-in AND authenticated. The runtime historically binds `0.0.0.0` (the
/// tailnet serves it), so a bare env gate would expose a mutation route to
/// every tailnet peer. The route therefore requires **both**:
///
/// 1. `ANDROMEDA_CONTROL_PLANE=1` at serve time (off by default), and
/// 2. `Authorization: Bearer <ANDROMEDA_MCP_BEARER_TOKEN>` per request.
///
/// The MCP bearer is deliberately reused: one credential per door, and this
/// door is already the VM/agent credential — not a new secret to mint.
public struct ControlPlaneRoute: Sendable {
    /// Environment variable that arms the control plane. Off unless `1`.
    public static let gateVariable = "ANDROMEDA_CONTROL_PLANE"

    private let state: any ControlPlaneStateSourcing
    private let actions: any ControlActionDispatching
    private let bearerToken: String?
    private let logger: Logger

    public init(
        state: any ControlPlaneStateSourcing,
        actions: any ControlActionDispatching,
        bearerToken: String?,
        logger: Logger = Logger(label: "andromeda.control-plane")
    ) {
        self.state = state
        self.actions = actions
        self.bearerToken = bearerToken
        self.logger = logger
    }

    /// Whether the control plane should be registered, given the serve-time
    /// environment. Public so `serve` can log the surface state honestly.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[gateVariable] == "1"
    }

    private func isAuthorized(_ request: Request) -> Bool {
        guard let bearerToken, !bearerToken.isEmpty else { return false }
        return request.headers[.authorization] == "Bearer \(bearerToken)"
    }

    public func register(on router: Router<some RequestContext>) {
        let state = state
        let actions = actions
        let logger = logger

        // GET /control/state — the curated contract.
        router.get("/control/state") { [self] request, _ -> Response in
            guard isAuthorized(request) else {
                logger.warning("🛑 control-plane state denied — bearer required")
                return Self.unauthorized()
            }
            do {
                let snapshot = try await state.snapshot()
                return try Self.encodeJSON(snapshot)
            } catch {
                logger.error(
                    "💥 control-plane snapshot failed",
                    metadata: ["error": .string(String(describing: error))]
                )
                return Self.internalError()
            }
        }

        // POST /control/action — typed dispatch, one switch, no strings.
        router.post("/control/action") { [self] request, _ -> Response in
            guard isAuthorized(request) else {
                logger.warning("🛑 control-plane action denied — bearer required")
                return Self.unauthorized()
            }
            let decoded = try await Self.decodeAction(from: request)
            let action: ControlAction
            switch decoded {
            case let .valid(typed):
                action = typed
            case .unparseable:
                return Self.badRequest("expected {\"action\": \"<name>\"} JSON body")
            case let .unknown(name):
                return Self.badRequest(Self.unknownActionMessage(name))
            }
            let outcome = await actions.dispatch(action)
            Self.logOutcome(outcome, action: action, logger: logger)
            let status: HTTPResponse.Status = outcome.status == .ok ? .ok : .internalServerError
            return Self.encodeRaw(Self.jsonData(outcome), status: status)
        }

        // GET /control/actions — the action catalogue, so surfaces can be
        // generated from one list instead of drifting hand-written copies.
        router.get("/control/actions") { [self] request, _ -> Response in
            guard isAuthorized(request) else {
                return Self.unauthorized()
            }
            let catalogue: [String: [String]] = [
                "actions": ControlAction.allCases.map(\.rawValue).sorted(),
            ]
            return Self.encodeRaw(Self.jsonData(catalogue), status: .ok)
        }
    }

    /// 400 body naming the full catalogue — the caller should never have to
    /// guess what exists.
    private static func unknownActionMessage(_ name: String) -> String {
        let known = ControlAction.allCases.map(\.rawValue).sorted().joined(separator: ", ")
        return "unknown action '\(name)' — known: \(known)"
    }

    /// Decoded action from a request body: `.valid` carries the typed case,
    /// `.unparseable`/`.unknown` carry the offending raw name for the 400.
    private enum DecodedAction {
        case valid(ControlAction)
        case unparseable
        case unknown(String)
    }

    private static func decodeAction(from request: Request) async throws -> DecodedAction {
        guard
            let collected = try? await request.body.collect(upTo: 1_048_576),
            let payload = try? JSONDecoder().decode(ControlActionRequest.self, from: Data(collected.readableBytesView))
        else {
            return .unparseable
        }
        guard let action = ControlAction.named(payload.action) else {
            return .unknown(payload.action)
        }
        return .valid(action)
    }

    /// Emoji observability at the decision point (canon law).
    private static func logOutcome(_ outcome: ControlActionOutcome, action: ControlAction, logger: Logger) {
        if outcome.status == .ok {
            logger.info("🎛️ control action ok", metadata: ["action": .string(action.rawValue)])
        } else {
            logger.error(
                "💥 control action failed",
                metadata: ["action": .string(action.rawValue), "detail": .string(outcome.detail)]
            )
        }
    }

    // MARK: - Responses

    private static func unauthorized() -> Response {
        encodeJSONString(#"{"error":"unauthorized: bearer token required"}"#, status: .unauthorized)
    }

    private static func badRequest(_ message: String) -> Response {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        return encodeJSONString(#"{"error":"\#(escaped)"}"#, status: .badRequest)
    }

    private static func internalError() -> Response {
        encodeJSONString(#"{"error":"internal error"}"#, status: .internalServerError)
    }

    private static func jsonData(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
    }

    private static func encodeJSON(_ value: some Encodable) throws -> Response {
        try encodeRaw(JSONEncoder().encode(value), status: .ok)
    }

    private static func encodeRaw(_ data: Data, status: HTTPResponse.Status) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: .init(data: data)))
    }

    private static func encodeJSONString(_ json: String, status: HTTPResponse.Status) -> Response {
        encodeRaw(Data(json.utf8), status: status)
    }
}
