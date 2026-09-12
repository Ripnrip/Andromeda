import AndromedaDomain
import AndromedaHTTP
import AndromedaMemory
import AndromedaProjections
import Foundation
import Logging

/// Production adapter that reads the curated control-plane snapshot from the
/// live runtime objects. Lives in AndromedaServer (not AndromedaHTTP) so the
/// HTTP layer stays free of server internals.
public struct ControlPlaneRuntimeState: ControlPlaneStateSourcing {
    private let configuration: AndromedaRuntimeConfiguration
    private let memoryRuntime: MemoryRuntime
    private let projectionRuntime: ProjectionRuntime
    private let logger: Logger

    public init(
        configuration: AndromedaRuntimeConfiguration,
        memoryRuntime: MemoryRuntime,
        projectionRuntime: ProjectionRuntime,
        logger: Logger = Logger(label: "andromeda.control-plane.state")
    ) {
        self.configuration = configuration
        self.memoryRuntime = memoryRuntime
        self.projectionRuntime = projectionRuntime
        self.logger = logger
    }

    public func snapshot() async throws -> ControlPlaneSnapshot {
        // Read-only and honest: a plain count from the operational store —
        // never a journal rebuild (a rebuild wipes the hot store mid-flight;
        // a count must not mutate) — with errors propagated so an unreadable
        // store surfaces as a 500, not a falsely-empty 200. No secrets, no
        // provider brands (capability curtain).
        let memoryCount = try await memoryRuntime.operationalRecordCount()
        let pending = try await backlogCount()

        var surfaces = ["http", "mcp"]
        if ControlPlaneRoute.isEnabled() {
            surfaces.append("control")
        }

        return ControlPlaneSnapshot(
            service: configuration.serviceName,
            version: configuration.version,
            surfaces: surfaces,
            counts: .init(memories: memoryCount, projectionBacklog: pending),
            capturedAt: Date().timeIntervalSince1970
        )
    }

    /// Pending projection retries, read without draining.
    private func backlogCount() async throws -> Int {
        try await projectionRuntime.pendingCount()
    }
}

/// Production dispatcher — the single source of actions. Every surface
/// (HTTP route, CLI, future MCP tools) funnels through `dispatch`; none may
/// hold logic of its own. Each case calls the same runtime method the
/// periodic `serve` loop calls.
public struct ControlPlaneRuntimeActions: ControlActionDispatching {
    private let projectionRuntime: ProjectionRuntime
    private let logger: Logger

    public init(
        projectionRuntime: ProjectionRuntime,
        logger: Logger = Logger(label: "andromeda.control-plane.actions")
    ) {
        self.projectionRuntime = projectionRuntime
        self.logger = logger
    }

    public func dispatch(_ action: ControlAction) async -> ControlActionOutcome {
        switch action {
        case .drainProjections:
            do {
                let outcomes = try await projectionRuntime.retryPending()
                let recovered = outcomes.filter { $0.newReceipt.status == .committed }.count
                logger.info(
                    "🎛️ control drain-projections",
                    metadata: [
                        "attempted": .stringConvertible(outcomes.count),
                        "recovered": .stringConvertible(recovered),
                    ]
                )
                return ControlActionOutcome(
                    action: action.rawValue,
                    status: .ok,
                    detail: "attempted \(outcomes.count), recovered \(recovered)"
                )
            } catch {
                logger.error(
                    "💥 control drain-projections failed",
                    metadata: ["error": .string(String(describing: error))]
                )
                return ControlActionOutcome(
                    action: action.rawValue,
                    status: .error,
                    detail: "drain failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
