import Foundation
import HTTPTypes
import Hummingbird
import Logging

/**
 * 🎭 The App Control Route - The Stage Door Behind Three Locks
 *
 * "Bearer, content, origin — every knock is named, and twice-checked.
 *  Loopback is where the door stands, not who may open it."
 *
 * - The Spellbinding Museum Director of App Control
 */

/// `/state`, `/actions`, `/action`, `/screenshot` routes for the HUD process's
/// App Control plane (HAB-838, pillar 3 applied to the glass).
///
/// ## Fail-closed posture (HAB-866)
///
/// Every route clears ``AppControlGuard``'s triple lock before doing any
/// work: a valid **bearer token**, an acceptable **Origin/Host** pair, and —
/// for `POST /action` — an `application/json` **Content-Type** checked
/// before the body is ever parsed. The 127.0.0.1 bind is a placement
/// constraint, not an authentication boundary; the guard is the boundary.
public struct AppControlRoute: Sendable {
    private let state: any AppControlStateSourcing
    private let actions: any AppControlDispatching
    private let screenshotter: any AppControlScreenshotting
    private let gate: AppControlGuard
    private let logger: Logger

    public init(
        state: any AppControlStateSourcing,
        actions: any AppControlDispatching,
        screenshotter: any AppControlScreenshotting,
        gate: AppControlGuard,
        logger: Logger = Logger(label: "andromeda.app-control")
    ) {
        self.state = state
        self.actions = actions
        self.screenshotter = screenshotter
        self.gate = gate
        self.logger = logger
    }

    public func register(on router: Router<some RequestContext>) {
        let state = state
        let actions = actions
        let screenshotter = screenshotter
        let gate = gate
        let logger = logger

        // GET /state — the curated snapshot of the glass.
        router.get("/state") { request, _ -> Response in
            if let rejection = gate.authorize(request.headers, authority: request.head.authority) {
                return Self.reject(rejection, logger: logger)
            }
            do {
                let snapshot = try await state.snapshot()
                return try Self.encodeJSON(snapshot)
            } catch {
                logger.error(
                    "💥 app-control snapshot failed",
                    metadata: ["error": .string(String(describing: error))]
                )
                return Self.internalError()
            }
        }

        // POST /action — typed dispatch, one switch, no strings.
        // The triple lock plus a content-type demand, all before parsing.
        router.post("/action") { request, _ -> Response in
            if let rejection = gate.authorize(request.headers, authority: request.head.authority, requireJSON: true) {
                return Self.reject(rejection, logger: logger)
            }
            let decoded = await Self.decodeAction(from: request)
            let action: AppControlAction
            switch decoded {
            case let .valid(typed):
                action = typed
            case .unparseable:
                return Self.badRequest("expected {\"action\": \"<name>\", \"query\": \"…\"} JSON body")
            case let .missingPayload(verb):
                return Self.badRequest("action '\(verb.rawValue)' requires a non-empty \"query\" payload")
            case let .unknown(name):
                return Self.unprocessableContent(Self.unknownActionMessage(name))
            }
            let outcome = await actions.dispatch(action)
            Self.logOutcome(outcome, action: action, logger: logger)
            let status: HTTPResponse.Status = outcome.status == .ok ? .ok : .internalServerError
            return Self.encodeRaw(Self.jsonData(outcome), status: status)
        }

        // GET /actions — the catalogue, generated from the one true list.
        router.get("/actions") { request, _ -> Response in
            if let rejection = gate.authorize(request.headers, authority: request.head.authority) {
                return Self.reject(rejection, logger: logger)
            }
            let catalogue: [String: [String]] = [
                "actions": AppControlVerb.allCases.map(\.rawValue).sorted(),
            ]
            return Self.encodeRaw(Self.jsonData(catalogue), status: .ok)
        }

        // GET /screenshot — the glass as PNG bytes, rendered by ImageRenderer
        // from the app's own view tree. Never `screencapture` (TCC + strangers).
        router.get("/screenshot") { request, _ -> Response in
            if let rejection = gate.authorize(request.headers, authority: request.head.authority) {
                return Self.reject(rejection, logger: logger)
            }
            do {
                let png = try await screenshotter.pngData()
                var headers = HTTPFields()
                headers[.contentType] = "image/png"
                return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(data: png)))
            } catch {
                logger.error(
                    "💥 app-control screenshot failed",
                    metadata: ["error": .string(String(describing: error))]
                )
                return Self.internalError()
            }
        }
    }

    /// 422 body naming the full catalogue — the caller should never have to
    /// guess what exists.
    private static func unknownActionMessage(_ name: String) -> String {
        let known = AppControlVerb.allCases.map(\.rawValue).sorted().joined(separator: ", ")
        return "unknown action '\(name)' — known: \(known)"
    }

    /// Rejection → response. The offending value rides the envelope for the
    /// operator's log; the expected token never does.
    private static func reject(_ rejection: AppControlGuard.Rejection, logger: Logger) -> Response {
        let message: String
        let status: HTTPResponse.Status
        var headers = HTTPFields()
        switch rejection {
        case .bearerRequired:
            message = "unauthorized: Authorization: Bearer <token> is required (token file: ~/.andromeda/app-control-token, 0600)"
            status = .unauthorized
            headers[.wwwAuthenticate] = #"Bearer realm="andromeda-app-control""#
        case .bearerInvalid:
            message = "unauthorized: bearer token did not match"
            status = .unauthorized
            headers[.wwwAuthenticate] = #"Bearer realm="andromeda-app-control", error="invalid_token""#
        case let .originForbidden(origin):
            message = "forbidden: Origin '\(origin)' is not a loopback origin"
            status = .forbidden
        case let .hostForbidden(host):
            message = "forbidden: Host '\(host)' must be a loopback literal (127.0.0.1 or localhost, optional port)"
            status = .forbidden
        case let .mediaTypeUnsupported(presented):
            message = "unsupported media type: Content-Type must be application/json (got '\(presented)')"
            status = .unsupportedMediaType
        }
        logger.warning(
            "🚫 app-control request rejected",
            metadata: ["reason": .string(message)]
        )
        return errorResponse(message, status: status, headers: headers)
    }

    /// Decoded action from a request body: `.valid` carries the typed case,
    /// `.unparseable`/`.missingPayload` stay malformed-payload 400s;
    /// `.unknown` is syntactically valid but semantically unprocessable (422).
    /// `submit-query` without a non-empty `query` is a payload error, not an
    /// unknown action. Only reached after the guard confirmed
    /// `application/json` — the content type is checked before this runs.
    private enum DecodedAction {
        case valid(AppControlAction)
        case unparseable
        case unknown(String)
        case missingPayload(AppControlVerb)
    }

    private static func decodeAction(from request: Request) async -> DecodedAction {
        guard
            let collected = try? await request.body.collect(upTo: 1_048_576),
            let payload = try? JSONDecoder().decode(AppControlActionRequest.self, from: Data(collected.readableBytesView))
        else {
            return .unparseable
        }
        guard let verb = AppControlVerb(rawValue: payload.action) else {
            return .unknown(payload.action)
        }
        switch verb {
        case .submitQuery:
            guard let query = payload.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                return .missingPayload(verb)
            }
            return .valid(.submitQuery(query: query))
        case .focusSearch:
            return .valid(.focusSearch)
        case .dismissResults:
            return .valid(.dismissResults)
        case .refreshFleetPulse:
            return .valid(.refreshFleetPulse)
        }
    }

    /// Emoji observability at the decision point (canon law).
    private static func logOutcome(_ outcome: AppControlOutcome, action: AppControlAction, logger: Logger) {
        if outcome.status == .ok {
            logger.info("🎛️ app-control action ok", metadata: ["action": .string(action.name)])
        } else {
            logger.error(
                "💥 app-control action failed",
                metadata: ["action": .string(action.name), "detail": .string(outcome.detail)]
            )
        }
    }

    // MARK: - Responses

    /// Error envelope built with `JSONEncoder` — never string interpolation,
    /// which corrupts JSON when the message carries quotes, newlines, or
    /// backslash sequences.
    private static func errorResponse(
        _ message: String,
        status: HTTPResponse.Status,
        headers extra: HTTPFields = HTTPFields()
    ) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        for field in extra {
            headers.append(field)
        }
        let data = (try? JSONEncoder().encode(["error": message])) ?? Data("{}".utf8)
        return Response(status: status, headers: headers, body: .init(byteBuffer: .init(data: data)))
    }

    private static func badRequest(_ message: String) -> Response {
        errorResponse(message, status: .badRequest)
    }

    private static func unprocessableContent(_ message: String) -> Response {
        errorResponse(message, status: .unprocessableContent)
    }

    private static func internalError() -> Response {
        errorResponse("internal error", status: .internalServerError)
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
}
