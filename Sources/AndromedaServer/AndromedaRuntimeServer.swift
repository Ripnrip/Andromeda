import AndromedaDomain
import AndromedaHostOps
import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import AndromedaPowerKit
import AndromedaProjections
import AndromedaSecrets
import AndromedaTools
import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// Opt-in tools/MCP broker configuration. When present, the server exposes
/// POST /mcp (bearer-gated) backed by the curated tools broker.
public struct MCPConfiguration: Sendable, Equatable {
    /// Token VM agents present as `Authorization: Bearer <token>`. This is the
    /// VM↔Andromeda credential — upstream tokens never leave the host.
    public let bearerToken: String
    public let tools: ToolsBrokerConfiguration

    public init(bearerToken: String, tools: ToolsBrokerConfiguration) {
        self.bearerToken = bearerToken
        self.tools = tools
    }
}

/// Launch configuration for the additive Andromeda Runtime v2 server surface.
public struct AndromedaRuntimeConfiguration: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let serviceName: String
    public let version: String
    public let mcp: MCPConfiguration?

    public init(
        host: String = "0.0.0.0",
        port: Int = 8788,
        serviceName: String = "Andromeda Runtime",
        version: String = "0.3.0-runtime-v2-m3",
        mcp: MCPConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.serviceName = serviceName
        self.version = version
        self.mcp = mcp
    }
}

/// Composition root that wires the new runtime modules with explicit initializer injection.
public struct AndromedaRuntimeServer: Sendable {
    public let configuration: AndromedaRuntimeConfiguration
    public let journal: any EventJournal
    public let memoryRuntime: MemoryRuntime
    public let projectionRuntime: ProjectionRuntime
    public let secretsBroker: SecretsBroker
    public let clock: any ClockProviding
    public let uuidProvider: any UUIDProviding
    public let logger: Logger
    public let powerCoordinator: PowerLeaseCoordinator

    /// Interval between periodic projection retry drains while serving.
    private static let retryDrainInterval: Duration = .seconds(60)

    public init(
        configuration: AndromedaRuntimeConfiguration,
        journal: any EventJournal,
        memoryRuntime: MemoryRuntime,
        projectionRuntime: ProjectionRuntime,
        secretsBroker: SecretsBroker,
        clock: any ClockProviding,
        uuidProvider: any UUIDProviding,
        powerCoordinator: PowerLeaseCoordinator = PowerLeaseCoordinator(),
        logger: Logger = Logger(label: "andromeda.runtime")
    ) {
        self.configuration = configuration
        self.journal = journal
        self.memoryRuntime = memoryRuntime
        self.projectionRuntime = projectionRuntime
        self.secretsBroker = secretsBroker
        self.clock = clock
        self.uuidProvider = uuidProvider
        self.powerCoordinator = powerCoordinator
        self.logger = logger
    }

    public init(
        configuration: AndromedaRuntimeConfiguration = .init(),
        journalFileURL: URL,
        operationalStoreURL: URL? = nil,
        vaultDirectoryURL: URL? = nil,
        qdrantBaseURL: URL = URL(string: "http://localhost:6333")!,
        logger: Logger = Logger(label: "andromeda.runtime")
    ) throws {
        let journal = try JSONLineEventJournal(fileURL: journalFileURL)
        let storeURL = operationalStoreURL ?? journalFileURL.deletingPathExtension().appendingPathExtension("sqlite3")
        let operationalStore = try SQLiteMemoryOperationalStore(databaseURL: storeURL)
        let vaultURL = vaultDirectoryURL ?? journalFileURL.deletingLastPathComponent().appendingPathComponent("vault")
        let markdownSink = MarkdownVaultProjection(vaultDirectoryURL: vaultURL)
        let qdrantSink = QdrantProjection(
            baseURL: qdrantBaseURL,
            embeddingProvider: HashBagOfWordsEmbeddingProvider()
        )
        let projectionRuntime = ProjectionRuntime(
            sinks: [markdownSink, qdrantSink],
            queue: DurableRetryQueue(
                fileURL: journalFileURL.deletingPathExtension().appendingPathExtension("retry.jsonl")
            )
        )
        self.init(
            configuration: configuration,
            journal: journal,
            memoryRuntime: MemoryRuntime(
                journal: journal,
                operationalStore: operationalStore,
                projectionSinks: [markdownSink, qdrantSink],
                retryQueue: projectionRuntime
            ),
            projectionRuntime: projectionRuntime,
            secretsBroker: SecretsBroker(),
            clock: LiveClock(),
            uuidProvider: LiveUUIDProvider(),
            powerCoordinator: PowerLeaseCoordinator(),
            logger: logger
        )
    }

    public func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let router = RuntimeRouter(
            healthProvider: RuntimeHealthService(server: self),
            memoryRuntime: memoryRuntime
        ).build()
        DashboardRoute(memoryRuntime: memoryRuntime).register(on: router)
        // Power lease status endpoint — returns current lease state as JSON.
        // P1 security: when MCP bearer token is configured, gate the detailed
        // view behind it. Unauthenticated requests get a redacted aggregate
        // (counts + sleep flags only — no owner names, reasons, or UUIDs).
        let coordinator = powerCoordinator
        let bearerToken = configuration.mcp?.bearerToken
        router.get("/power") { request, _ -> Response in
            let status = await coordinator.status()

            // Check bearer: if token configured, require it for full details.
            let authenticated: Bool
            if let bearerToken {
                let header = request.headers[.authorization] ?? ""
                authenticated = header == "Bearer \(bearerToken)"
            } else {
                // No token configured — return aggregate only (safe for local dev).
                authenticated = false
            }

            let body: [String: Any]
            if authenticated {
                body = [
                    "activeLeaseCount": status.activeLeases.count,
                    "preventSystemSleep": status.preventSystemSleep,
                    "preventDisplaySleep": status.preventDisplaySleep,
                    "leases": status.activeLeases.map { lease -> [String: String] in
                        [
                            "id": lease.id.uuidString,
                            "owner": lease.owner,
                            "reason": lease.reason,
                            "acquiredAt": ISO8601DateFormatter().string(from: lease.acquiredAt),
                        ]
                    },
                ]
            } else {
                // Redacted: counts and flags only — no operator-identifying data.
                body = [
                    "activeLeaseCount": status.activeLeases.count,
                    "preventSystemSleep": status.preventSystemSleep,
                    "preventDisplaySleep": status.preventDisplaySleep,
                ]
            }
            let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(data: data)))
        }
        if let mcp = configuration.mcp {
            let broker = CuratedToolBroker(
                configuration: mcp.tools,
                secrets: MacOSKeychainSecretProvider(),
                http: URLSessionUpstreamHTTP()
            )
            let universalTools = CompositeMCPToolServer(servers: [
                MemoryMCPToolServer(runtime: memoryRuntime),
                broker,
            ])
            MCPRoute(
                broker: universalTools,
                auth: MCPBearerAuth(token: mcp.bearerToken),
                serverVersion: configuration.version
            ).register(on: router)
        }
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: configuration.serviceName
            ),
            logger: logger
        )
        return app
    }

    public func run() async throws {
        logger.info(
            "Starting Andromeda Runtime server",
            metadata: [
                "host": .string(configuration.host),
                "port": .stringConvertible(configuration.port),
                "service": .string(configuration.serviceName),
                "version": .string(configuration.version),
            ]
        )
        _ = try await memoryRuntime.rebuildOperationalStoreFromJournal()
        // Drain any projection retries that survived a previous run.
        await drainProjectionRetries(reason: "startup")
        // Write initial power status snapshot so `andromeda doctor` sees us.
        await powerCoordinator.writeStatusSnapshot()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.makeApplication().runService()
            }
            group.addTask {
                try await self.projectionRetryLoop()
            }
            group.addTask {
                try await self.powerSnapshotLoop()
            }
            try await group.next()
            // Cancel remaining tasks and wait for them to drain before cleanup.
            group.cancelAll()
        }
        // Awaited cleanup: release all leases and write final snapshot
        // before run() returns so the process can't exit with active leases.
        await powerCoordinator.releaseAll()
        await powerCoordinator.writeStatusSnapshot()
    }

    /// Interval between periodic power status snapshot writes.
    private static let powerSnapshotInterval: Duration = .seconds(30)

    /// Periodically writes power lease status to the snapshot file so
    /// `andromeda doctor` and HUD consumers see current state.
    private func powerSnapshotLoop() async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: Self.powerSnapshotInterval)
            if Task.isCancelled { break }
            await powerCoordinator.writeStatusSnapshot()
        }
    }

    /// Periodically re-drives failed projection writes from the durable retry
    /// queue for as long as the server is running.
    private func projectionRetryLoop() async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: Self.retryDrainInterval)
            if Task.isCancelled { break }
            await drainProjectionRetries(reason: "periodic")
        }
    }

    private func drainProjectionRetries(reason: String) async {
        do {
            let outcomes = try await projectionRuntime.retryPending()
            if !outcomes.isEmpty {
                let recovered = outcomes.filter { $0.newReceipt.status == .committed }.count
                logger.info(
                    "Drained projection retry queue",
                    metadata: [
                        "reason": .string(reason),
                        "attempted": .stringConvertible(outcomes.count),
                        "recovered": .stringConvertible(recovered),
                    ]
                )
            }
        } catch {
            logger.warning(
                "Projection retry drain failed",
                metadata: [
                    "reason": .string(reason),
                    "error": .string(error.localizedDescription),
                ]
            )
        }
    }
}

private struct RuntimeHealthService: HealthStatusProviding {
    let server: AndromedaRuntimeServer

    func healthStatus() async -> RuntimeHealthStatus {
        let journalLabel: String
        if server.journal is JSONLineEventJournal {
            journalLabel = "jsonl"
        } else {
            journalLabel = "memory"
        }

        return RuntimeHealthStatus(
            status: "healthy",
            service: server.configuration.serviceName,
            version: server.configuration.version,
            journal: journalLabel
        )
    }
}
