import AndromedaHUDCore
import Foundation
import Hummingbird
import Logging

/**
 * 🎭 The App Control Server - The Loopback Drawbridge
 *
 * "One env-var key turns the lock; one bind address draws the moat.
 *  127.0.0.1 — the stage door that opens onto no street."
 *
 * - The Spellbinding Museum Director of App Control
 */

/// Construction of the HUD process's App Control listener (HAB-838).
///
/// Naming law: this is **App Control** (`ANDROMEDA_APP_CONTROL=1`, binds
/// 127.0.0.1 only, no bearer — the moat is the bind address) — a different
/// door from the runtime **Control Plane** (`ANDROMEDA_CONTROL_PLANE=1`,
/// binds 0.0.0.0 on the tailnet, MCP bearer required per request). If this
/// posture ever broadens beyond loopback, a bearer becomes mandatory before
/// merge.
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
    /// renders.
    public static func makeApplication(
        model: HUDModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: Logger = Logger(label: "andromeda.app-control")
    ) -> Application<RouterResponder<BasicRequestContext>> {
        let router = Router(context: BasicRequestContext.self)
        AppControlRoute(
            state: HUDModelAppControlSource(model: model),
            actions: HUDModelAppControlDispatcher(model: model),
            screenshotter: HUDViewAppControlScreenshotter(model: model),
            logger: logger
        ).register(on: router)
        return Application(
            router: router,
            configuration: .init(
                address: .hostname(loopbackHost, port: port(environment: environment)),
                serverName: "AndromedaHUD-AppControl"
            ),
            logger: logger
        )
    }
}

/// Lifetime owner for the armed App Control listener inside the HUD process.
/// A no-op unless `ANDROMEDA_APP_CONTROL=1` — the resting HUD never opens the
/// door. Retains the application and its service task for the process
/// lifetime (same posture as the HUD window itself).
@MainActor
public final class AppControlService {
    private var application: Application<RouterResponder<BasicRequestContext>>?
    private var runTask: Task<Void, Error>?

    public init() {}

    /// Arms the loopback listener if (and only if) the env gate is set.
    /// Idempotent — a second call while armed is a no-op.
    public func arm(
        model: HUDModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        logger: Logger = Logger(label: "andromeda.app-control")
    ) {
        guard application == nil else { return }
        guard AppControlServer.isEnabled(environment: environment) else {
            logger.info("🌙 app control off (set ANDROMEDA_APP_CONTROL=1 to arm)")
            return
        }
        let app = AppControlServer.makeApplication(model: model, environment: environment, logger: logger)
        let boundPort = AppControlServer.port(environment: environment)
        application = app
        runTask = Task.detached(priority: .background) {
            try await app.runService()
        }
        logger.info(
            "🎛️ app control armed — loopback only",
            metadata: [
                "host": .string(AppControlServer.loopbackHost),
                "port": .stringConvertible(boundPort),
            ]
        )
    }
}
