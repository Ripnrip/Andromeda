import Foundation

// MARK: - One hosted server's runtime

/// Runtime state for one configured server: supervisor + connection set.
final class HostedServer: @unchecked Sendable {
    let supervisor: UpstreamSupervisor
    let config: HubServerConfig

    /// Connection key → writable side back to that shim.
    private let lock = NSLock()
    private var connections: [String: FileHandle] = [:]
    private var counter: UInt64 = 0

    init(config: HubServerConfig, host: UpstreamProcessHosting, telemetry: HubTelemetry) {
        self.config = config
        supervisor = UpstreamSupervisor(
            config: config, host: host, telemetry: telemetry
        )
    }

    func nextConnectionKey() -> RelayConnectionKey {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return RelayConnectionKey.make(counter)
    }

    func addConnection(_ handle: FileHandle, key: RelayConnectionKey) {
        lock.lock(); defer { lock.unlock() }
        connections[key.value] = handle
    }

    func removeConnection(_ key: RelayConnectionKey) {
        lock.lock(); defer { lock.unlock() }
        connections[key.value] = nil
    }

    func deliver(_ data: Data, to key: String) {
        lock.lock(); defer { lock.unlock() }
        guard let handle = connections[key] else { return }
        var line = data
        line.append(0x0A)
        try? handle.write(contentsOf: line)
    }

    func broadcast(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        var line = data
        line.append(0x0A)
        for handle in connections.values {
            try? handle.write(contentsOf: line)
        }
    }

    var connectionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return connections.count
    }
}

// MARK: - Hub

/// The hub daemon core. Owns one `HostedServer` per config entry, listens
/// on one unix socket per server, relays per the mux design.
public final class MCPHub: @unchecked Sendable {
    private let configuration: MCPHubConfiguration
    private let telemetry: HubTelemetry
    private let processHost: UpstreamProcessHosting
    private var hosted: [String: HostedServer] = [:]
    private var fileHandles: [FileHandle] = []
    private var listeners: [Int32] = []

    public init(
        configuration: MCPHubConfiguration,
        processHost: UpstreamProcessHosting = ProcessUpstreamHost(),
        telemetry: HubTelemetry? = nil
    ) {
        self.configuration = configuration
        self.processHost = processHost
        // Cursor style review: honor the injected telemetry (DI law) —
        // only the default path derives its JSONL location from config.
        self.telemetry = telemetry ?? HubTelemetry(
            jsonlPath: configuration.telemetryLogPath
        )
    }

    public var hostedServerIDs: [String] {
        hosted.keys.sorted()
    }

    // MARK: Lifecycle

    /// Create the socket directory, spawn upstreams, bind one listening
    /// socket per server. Throws on unusable configuration.
    public func start() throws {
        _ = try configuration.validated()
        let dir = (configuration.socketDirectory as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for server in configuration.servers {
            let hostedServer = HostedServer(
                config: server, host: processHost, telemetry: telemetry
            )
            hosted[server.id] = hostedServer

            guard hostedServer.supervisor.ensureRunning() != nil else {
                throw MCPHubError.upstreamSpawnFailed(server.id)
            }

            let path = configuration.socketPath(for: server.id)
            try? FileManager.default.removeItem(atPath: path) // stale socket
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }

            let fd = try Self.bindAndListen(path: path)
            listeners.append(fd)
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            fileHandles.append(handle)
            beginAccepting(on: handle, server: hostedServer)
        }

        telemetry.event(.hubStarted(
            socketDirectory: configuration.socketDirectory,
            servers: configuration.servers.count
        ))
    }

    /// Stop accepting; upstreams keep running (the hub did not decide to
    /// kill them — they belong to the roster).
    public func stop() {
        for handle in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()
        listeners.removeAll()
    }

    public enum MCPHubError: Error, Equatable {
        case upstreamSpawnFailed(String)
        case acceptFailed(String)
    }

    // MARK: Accept loop

    private func beginAccepting(on handle: FileHandle, server: HostedServer) {
        handle.readabilityHandler = { [weak self] listening in
            guard let self else {
                listening.readabilityHandler = nil
                return
            }
            let clientFD = accept(listening.fileDescriptor, nil, nil)
            guard clientFD >= 0 else { return }
            let client = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)
            handleClient(client, server: server)
        }
    }

    private func handleClient(_ client: FileHandle, server: HostedServer) {
        let key = server.nextConnectionKey()
        server.addConnection(client, key: key)
        telemetry.event(.shimConnected(serverID: server.config.id, connection: key.value))

        guard let pipes = server.supervisor.ensureRunning() else {
            // Hub without upstream: reply a JSON-RPC error so the agent
            // host surfaces the gap instead of hanging. Typed frame — the
            // wire bytes are byte-equal to the hand-written literal this
            // replaced (test-asserted).
            server.deliver(
                HubJSONRPCError.upstreamUnavailable.encoded(), to: key.value
            )
            telemetry.event(.upstreamUnavailableReply(
                serverID: server.config.id, connection: key.value
            ))
            server.removeConnection(key)
            try? client.close()
            return
        }

        let upstreamStdin = pipes.stdin
        // Codex P1: stream reads can split frames mid-line — each connection
        // owns an assembler that buffers incomplete tails until the next read.
        let assembler = LineAssembler()

        client.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                // Shim disconnected.
                handle.readabilityHandler = nil
                server.removeConnection(key)
                self?.telemetry.event(
                    .shimDisconnected(serverID: server.config.id, connection: key.value)
                )
                try? handle.close()
                return
            }

            for line in assembler.append(data) {
                // One typed policy verdict per frame (Cursor security
                // review): malformed hijack vectors and JSON-RPC batch
                // arrays are rejected with -32600; client roots
                // notifications are dropped — the hub, not any client,
                // owns the sandbox allowlist.
                switch JSONRPCRelay.dispositionForClientFrame(line) {
                case let .reject(reason):
                    let error: HubJSONRPCError
                    var out: Data
                    switch reason {
                    case .duplicateMemberID:
                        error = .malformedFrame(duplicate: HubJSONRPCError.duplicateMemberID)
                        out = error.encoded()
                    case .topLevelArray:
                        error = .batchFrameRejected
                        out = error.encoded()
                    }
                    out.append(0x0A)
                    try? handle.write(contentsOf: out)
                    self?.telemetry.event(.frameRejected(
                        serverID: server.config.id, connection: key.value, reason: reason.rawValue
                    ))
                    continue

                case .dropRootsNotification:
                    // Silently dropped on purpose: the client believes it
                    // notified; the upstream never sees it, so its
                    // spawn-time sandbox stays authoritative.
                    self?.telemetry.event(.rootsNotificationDropped(
                        serverID: server.config.id, connection: key.value
                    ))
                    continue

                case .forward:
                    break
                }
                let relayed = JSONRPCRelay.relayClientMessage(line, connection: key)
                // One decision point per rewrite kind (canon: emoji at
                // every logged decision) — id namespacing (🏷️) and the
                // cancelled-notification rewrite (✂️) log separately.
                if relayed.namespacedID {
                    self?.telemetry.event(.idNamespaced(
                        serverID: server.config.id, connection: key.value
                    ))
                }
                if relayed.namespacedCancelledRequestID {
                    self?.telemetry.event(.cancelledRequestIDRewritten(
                        serverID: server.config.id, connection: key.value
                    ))
                }
                var out = relayed.frame
                out.append(0x0A)
                try? upstreamStdin.write(contentsOf: out)
            }
        }

        // Upstream stdout reader — attached per live pipe instance so a
        // respawned upstream gets fresh readers (Codex P1: the old set-based
        // guard refused reattachment after a restart).
        attachUpstreamReaders(pipes: pipes, server: server)
    }

    /// One stdout+stderr reader pair per live upstream pipe instance.
    /// The stdout handler signals exit, which clears the hosted server's
    /// reader binding — the next `ensureRunning` respawns and reattaches.
    private func attachUpstreamReaders(pipes: UpstreamPipes, server: HostedServer) {
        let stdoutAssembler = LineAssembler()

        pipes.stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                server.supervisor.upstreamExited()
                return
            }
            self?.relayUpstreamLines(stdoutAssembler.append(data), server: server)
        }

        // Codex P2: an undrained stderr pipe fills its buffer and the child
        // blocks on its next diagnostic write — drain continuously.
        let stderrTally = ByteTally()
        pipes.stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stderrTally.add(data.count)
            // 🧹 diagnostics drained — the decision point that keeps the
            // child un-blocked; logged so a silent upstream is auditable.
            self?.telemetry.event(.stderrDrained(
                serverID: server.config.id, bytes: data.count
            ))
        }
    }

    private func relayUpstreamLines(_ lines: [Data], server: HostedServer) {
        for payload in lines {
            // Server-initiated `roots/*` requests are answered by the hub
            // itself — EMPTY roots, echoing the upstream's request id — and
            // never broadcast to shims (Cursor security review: official
            // server-filesystem replaces its process-global allowlist from
            // whatever roots a client answers with; the hub's spawn-time
            // sandbox is the only authority).
            if JSONRPCRelay.isUpstreamRootsRequest(payload) {
                if let reply = Self.hubOwnedRootsReply(to: payload) {
                    server.supervisor.writeUpstream(reply)
                }
                telemetry.event(.rootsRequestAnsweredByHub(
                    serverID: server.config.id
                ))
                continue
            }
            if let routed = JSONRPCRelay.routeUpstreamMessage(payload) {
                server.deliver(routed.original, to: routed.key)
                telemetry.event(.upstreamResponseRouted(
                    serverID: server.config.id, connection: routed.key
                ))
            } else {
                server.broadcast(payload)
                telemetry.event(.upstreamNotificationBroadcast(
                    serverID: server.config.id, receivers: server.connectionCount
                ))
            }
        }
    }

    /// The hub's reply to an upstream `roots/list` request: an EMPTY-roots
    /// success result echoing the request id (canonical writer, byte-stable).
    private static func hubOwnedRootsReply(to payload: Data) -> Data? {
        let bytes = [UInt8](payload)
        guard let span = JSONIDRewriter.topLevelIDSpan(in: bytes) else { return nil }
        let raw = Array(bytes[span.start ..< span.end])
        let id: JSONRPCRequestID
        if raw.first == UInt8(ascii: "\"") {
            let inner = String(decoding: raw[1 ..< (raw.count - 1)], as: UTF8.self)
            id = .string(inner)
        } else if let number = Int(String(decoding: raw, as: UTF8.self)) {
            id = .number(number)
        } else {
            return nil
        }
        var out = (try? HubJSONRPCError.emptyRootsResult(id: id)) ?? nil
        out?.append(0x0A)
        return out
    }

    // MARK: Socket plumbing (Darwin)

    static func bindAndListen(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPHubError.acceptFailed("socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw MCPHubError.acceptFailed("socket path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            _ = pathBytes.withUnsafeBufferPointer { src in
                memcpy(dest.baseAddress!, src.baseAddress!, pathBytes.count)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw MCPHubError.acceptFailed("bind(\(path)) failed: errno \(errno)")
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw MCPHubError.acceptFailed("listen(\(path)) failed")
        }
        return fd
    }
}
