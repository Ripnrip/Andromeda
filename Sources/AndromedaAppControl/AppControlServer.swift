import AndromedaHUDCore
import Foundation
import Hummingbird
import Logging

/**
 * 🎭 The App Control Server - The Loopback Drawbridge, Triple-Locked
 *
 * "One env-var key turns the lock; one bind address draws the moat;
 *  and a bearer only the same hands may read opens the door."
 *
 * - The Spellbinding Museum Director of App Control
 */

/// Construction of the HUD process's App Control listener (HAB-838).
///
/// Naming law: this is **App Control** (`ANDROMEDA_APP_CONTROL=1`, binds
/// 127.0.0.1 only, triple-locked per HAB-866: bearer token + Origin/Host
/// allowlist + JSON content-type on mutating routes) — a different door
/// from the runtime **Control Plane** (`ANDROMEDA_CONTROL_PLANE=1`, binds
/// 0.0.0.0 on the tailnet, MCP bearer required per request). Both doors
/// now demand a key; the bind address is placement, not permission.
public enum AppControlServer {
    /// Environment variable that arms App Control. Off unless `1`.
    public static let gateVariable = "ANDROMEDA_APP_CONTROL"
    /// Environment variable overriding the listen port (tests, parallel runs).
    public static let portVariable = "ANDROMEDA_APP_CONTROL_PORT"
    /// Default port — distinct from the runtime's 8788 listener.
    public static let defaultPort = 8791
    /// The moat: App Control never leaves this machine.
    public static let loopbackHost = "127.0.0.1"

    /// Whether App Control should be armed, given the launch environment.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[gateVariable] == "1"
    }

    /// Listen port from the environment, defaulting to `defaultPort`.
    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        environment[portVariable].flatMap { Int($0) } ?? defaultPort
    }

    /// Builds the loopback application around the live HUD model: state,
    /// dispatch, and screenshot all observe the *same* instance the glass
    /// renders, and every route runs behind the HAB-866 triple lock.
    ///
    /// The bearer token is loaded-or-minted from
    /// `~/.andromeda/app-control-token` (0600). If the file is unavailable,
    /// an ephemeral token is minted instead — undiscoverable by clients,
    /// which fails closed rather than shipping an open door.
    ///
    /// - Parameter onServerRunning: Called once the listener has bound —
    ///   the only moment "armed" may be published (HAB-866 review P2).
    public static func makeApplication(
        model: HUDModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: Logger = Logger(label: "andromeda.app-control"),
        onServerRunning: @escaping @Sendable () async -> Void = {}
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        let gate = AppControlGuard(bearerToken: mintToken(logger: logger))
        AppControlRoute(
            state: HUDModelAppControlSource(model: model),
            actions: HUDModelAppControlDispatcher(model: model),
            screenshotter: HUDViewAppControlScreenshotter(model: model),
            gate: gate,
            logger: logger
        ).register(on: router)
        return Application(
            router: router,
            configuration: .init(
                address: .hostname(loopbackHost, port: port(environment: environment)),
                serverName: "AndromedaHUD-AppControl"
            ),
            onServerRunning: { _ in await onServerRunning() },
            logger: logger
        )
    }

    /// Token custody: persisted when possible, ephemeral (fail-closed) when not.
    private static func mintToken(logger: Logger) -> String {
        do {
            let token = try AppControlToken.loadOrGenerate()
            logger.info(
                "🔑 app-control bearer token loaded from ~/.andromeda/app-control-token (0600) — same-user clients read the file out-of-band"
            )
            return token
        } catch {
            let token = AppControlToken.generate()
            logger.error(
                "💥 app-control token file unavailable — minted ephemeral token; no client can discover it (fail closed)",
                metadata: [
                    "path": .string(AppControlToken.defaultURL.path),
                    "error": .string(String(describing: error)),
                ]
            )
            return token
        }
    }
}

/// Exactly-once bind signal shared between the service task and `arm()`:
/// remembers success/failure even if it arrives before anyone is waiting,
/// so the gate can never hang or double-resume.
private actor BindGate {
    private enum State {
        case waiting
        case succeeded
        case failed(String)
    }

    private var state: State = .waiting
    private var continuation: CheckedContinuation<Void, Error>?

    func awaitBind() async throws {
        switch state {
        case .succeeded:
            return
        case let .failed(message):
            throw BindError(message: message)
        case .waiting:
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func succeed() {
        guard case .waiting = state else { return }
        state = .succeeded
        continuation?.resume()
        continuation = nil
    }

    func fail(_ error: Error) {
        guard case .waiting = state else { return }
        state = .failed(String(describing: error))
        continuation?.resume(throwing: BindError(message: String(describing: error)))
        continuation = nil
    }

    struct BindError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}

/// Lifetime owner for the armed App Control listener inside the HUD process.
/// A no-op unless `ANDROMEDA_APP_CONTROL=1` — the resting HUD never opens the
/// door. Retains the application and its service task for the process
/// lifetime (same posture as the HUD window itself).
@MainActor
public final class AppControlService {
    private var application: Application<RouterResponder<BasicRequestContext>>?
    private var runTask: Task<Void, Never>?
    private var isArming = false

    public init() {}

    /// Whether the listener is live behind the triple lock. True only after
    /// a successful bind — never optimistically (HAB-866 review P2).
    public var isArmed: Bool { application != nil }

    /// Arms the loopback listener if (and only if) the env gate is set.
    /// Async: awaits the bind before publishing armed state. A failed bind
    /// (port in use, and so on) is logged and swallowed here — `application`
    /// stays `nil`, so a later `arm()` genuinely retries instead of
    /// no-op'ing. Idempotent while armed.
    public func arm(
        model: HUDModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: Logger = Logger(label: "andromeda.app-control")
    ) async {
        guard !isArming, application == nil else { return }
        guard AppControlServer.isEnabled(environment: environment) else {
            logger.info("🌙 app control off (set ANDROMEDA_APP_CONTROL=1 to arm)")
            return
        }
        isArming = true
        defer { isArming = false }

        let boundPort = AppControlServer.port(environment: environment)
        let bindGate = BindGate()
        let app = AppControlServer.makeApplication(
            model: model,
            environment: environment,
            logger: logger,
            onServerRunning: { await bindGate.succeed() }
        )
        let serviceTask = Task.detached(priority: .background) {
            do {
                // No signal handling of our own: the HUD process owns its
                // lifetime; cancellation drives graceful shutdown.
                try await app.runService(gracefulShutdownSignals: [])
            } catch {
                logger.error(
                    "💥 app control service ended with error",
                    metadata: ["error": .string(String(describing: error))]
                )
                await bindGate.fail(error)
            }
        }
        runTask = serviceTask

        do {
            try await bindGate.awaitBind()
            application = app
            logger.info(
                "🎛️ app control armed — loopback, bearer-gated",
                metadata: [
                    "host": .string(AppControlServer.loopbackHost),
                    "port": .stringConvertible(boundPort),
                ]
            )
        } catch {
            // Bind failed: recover to the disarmed state so retry is real.
            serviceTask.cancel()
            runTask = nil
            logger.error(
                "💥 app control failed to bind — not armed; arm() may be retried",
                metadata: [
                    "host": .string(AppControlServer.loopbackHost),
                    "port": .stringConvertible(boundPort),
                    "error": .string(String(describing: error)),
                ]
            )
        }
    }

    /// Graceful stop: cancels the service task (ServiceGroup shuts the
    /// listener down) and clears armed state. A subsequent `arm()` re-arms.
    public func disarm() {
        runTask?.cancel()
        runTask = nil
        application = nil
    }
}
