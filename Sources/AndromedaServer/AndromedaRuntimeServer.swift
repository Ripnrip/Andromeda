import AndromedaDomain
import AndromedaHTTP
import AndromedaJournal
import AndromedaMemory
import AndromedaProjections
import AndromedaSecrets
import Foundation
import Hummingbird
import Logging

/// Launch configuration for the additive Andromeda Runtime v2 server surface.
public struct AndromedaRuntimeConfiguration: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let serviceName: String
    public let version: String

    public init(
        host: String = "0.0.0.0",
        port: Int = 8788,
        serviceName: String = "Andromeda Runtime",
        version: String = "0.3.0-runtime-v2-m2"
    ) {
        self.host = host
        self.port = port
        self.serviceName = serviceName
        self.version = version
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

    public init(
        configuration: AndromedaRuntimeConfiguration,
        journal: any EventJournal,
        memoryRuntime: MemoryRuntime,
        projectionRuntime: ProjectionRuntime,
        secretsBroker: SecretsBroker,
        clock: any ClockProviding,
        uuidProvider: any UUIDProviding,
        logger: Logger = Logger(label: "andromeda.runtime")
    ) {
        self.configuration = configuration
        self.journal = journal
        self.memoryRuntime = memoryRuntime
        self.projectionRuntime = projectionRuntime
        self.secretsBroker = secretsBroker
        self.clock = clock
        self.uuidProvider = uuidProvider
        self.logger = logger
    }

    public init(
        configuration: AndromedaRuntimeConfiguration = .init(),
        journalFileURL: URL,
        operationalStoreURL: URL? = nil,
        logger: Logger = Logger(label: "andromeda.runtime")
    ) throws {
        let journal = try JSONLineEventJournal(fileURL: journalFileURL)
        let storeURL = operationalStoreURL ?? journalFileURL.deletingPathExtension().appendingPathExtension("sqlite3")
        let operationalStore = try SQLiteMemoryOperationalStore(databaseURL: storeURL)
        self.init(
            configuration: configuration,
            journal: journal,
            memoryRuntime: MemoryRuntime(journal: journal, operationalStore: operationalStore),
            projectionRuntime: ProjectionRuntime(),
            secretsBroker: SecretsBroker(),
            clock: LiveClock(),
            uuidProvider: LiveUUIDProvider(),
            logger: logger
        )
    }

    public func makeApplication() -> Application<RouterResponder<BasicRequestContext>> {
        let app = Application(
            router: RuntimeRouter(
                healthProvider: RuntimeHealthService(server: self),
                memoryRuntime: memoryRuntime
            ).build(),
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
        try await makeApplication().runService()
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
