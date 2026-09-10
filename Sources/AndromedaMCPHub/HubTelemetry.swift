import Foundation

#if canImport(OSLog)
    import os
#endif

// MARK: - Events

/// Typed hub events — enum, not stringly logging (canon: emoji logging at
/// decision points; each case carries its scan-friendly glyph).
public enum HubEvent: Sendable {
    case hubStarted(socketDirectory: String, servers: Int)
    case upstreamSpawned(serverID: String, command: String, attempt: Int)
    case upstreamSpawnFailed(serverID: String, attempt: Int)
    case upstreamExited(serverID: String, restarts: Int)
    case upstreamRestartScheduled(serverID: String, restarts: Int, backoffSeconds: Double)
    case upstreamExhausted(serverID: String, restarts: Int)
    case shimConnected(serverID: String, connection: String)
    case shimDisconnected(serverID: String, connection: String)
    case upstreamResponseRouted(serverID: String, connection: String)
    case upstreamNotificationBroadcast(serverID: String, receivers: Int)
    /// A client frame was rejected before forwarding (duplicate id members
    /// are a routing-hijack vector — Cursor security review).
    case malformedFrameRejected(serverID: String, connection: String)
    /// The hub answered a shim itself because no upstream is available
    /// (spawn failed or the restart budget is exhausted).
    case upstreamUnavailableReply(serverID: String, connection: String)
    /// A client request id was rewritten into the connection-namespaced form.
    case idNamespaced(serverID: String, connection: String)
    /// A `notifications/cancelled` `params.requestId` was rewritten into
    /// the connection-namespaced form.
    case cancelledRequestIDRewritten(serverID: String, connection: String)
    /// Upstream stderr diagnostics were drained (keeps the child un-blocked).
    case stderrDrained(serverID: String, bytes: Int)

    /// Emoji glyph per decision point (canon logging law).
    var glyph: String {
        switch self {
        case .hubStarted: "🚀"
        case .upstreamSpawned: "🐣"
        case .upstreamSpawnFailed: "💥"
        case .upstreamExited: "👋"
        case .upstreamRestartScheduled: "🔁"
        case .upstreamExhausted: "🛑"
        case .shimConnected: "🔌"
        case .shimDisconnected: "🔌"
        case .upstreamResponseRouted: "📬"
        case .upstreamNotificationBroadcast: "📡"
        case .malformedFrameRejected: "🚫"
        case .upstreamUnavailableReply: "⚠️"
        case .idNamespaced: "🏷️"
        case .cancelledRequestIDRewritten: "✂️"
        case .stderrDrained: "🧹"
        }
    }

    var kind: String {
        switch self {
        case .hubStarted: "hub.started"
        case .upstreamSpawned: "upstream.spawned"
        case .upstreamSpawnFailed: "upstream.spawn_failed"
        case .upstreamExited: "upstream.exited"
        case .upstreamRestartScheduled: "upstream.restart_scheduled"
        case .upstreamExhausted: "upstream.exhausted"
        case .shimConnected: "shim.connected"
        case .shimDisconnected: "shim.disconnected"
        case .upstreamResponseRouted: "upstream.response_routed"
        case .upstreamNotificationBroadcast: "upstream.notification_broadcast"
        case .malformedFrameRejected: "frame.malformed_rejected"
        case .upstreamUnavailableReply: "hub.upstream_unavailable_reply"
        case .idNamespaced: "frame.id_namespaced"
        case .cancelledRequestIDRewritten: "frame.cancelled_request_id_rewritten"
        case .stderrDrained: "upstream.stderr_drained"
        }
    }

    var fields: [String: String] {
        switch self {
        case let .hubStarted(socketDirectory, servers):
            ["socket_directory": socketDirectory, "servers": String(servers)]
        case let .upstreamSpawned(serverID, command, attempt):
            ["server": serverID, "command": command, "attempt": String(attempt)]
        case let .upstreamSpawnFailed(serverID, attempt):
            ["server": serverID, "attempt": String(attempt)]
        case let .upstreamExited(serverID, restarts):
            ["server": serverID, "restarts": String(restarts)]
        case let .upstreamRestartScheduled(serverID, restarts, backoffSeconds):
            [
                "server": serverID,
                "restarts": String(restarts),
                "backoff_seconds": String(format: "%.1f", backoffSeconds),
            ]
        case let .upstreamExhausted(serverID, restarts):
            ["server": serverID, "restarts": String(restarts)]
        case let .shimConnected(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .shimDisconnected(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .upstreamResponseRouted(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .upstreamNotificationBroadcast(serverID, receivers):
            ["server": serverID, "receivers": String(receivers)]
        case let .malformedFrameRejected(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .upstreamUnavailableReply(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .idNamespaced(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .cancelledRequestIDRewritten(serverID, connection):
            ["server": serverID, "connection": connection]
        case let .stderrDrained(serverID, bytes):
            ["server": serverID, "bytes": String(bytes)]
        }
    }

    var summary: String {
        let rendered = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(kind) \(rendered)"
    }
}

// MARK: - Sink

/// Where events go: os.Logger today, JSONL append alongside.
public struct HubTelemetry: Sendable {
    public static let shared = HubTelemetry()

    private let logger = Logger(subsystem: "ai.andromeda.mcp-hub", category: "hub")
    private let jsonlQueue = DispatchQueue(label: "ai.andromeda.mcp-hub.jsonl")
    private let jsonlPath: String

    public init(jsonlPath: String = "~/.andromeda/logs/mcp-hub.jsonl") {
        self.jsonlPath = (jsonlPath as NSString).expandingTildeInPath
    }

    public func event(_ event: HubEvent) {
        logger.info("\(event.glyph) \(event.summary, privacy: .public)")

        let line = Self.encode(event: event)
        jsonlQueue.async { [jsonlPath] in
            let url = URL(fileURLWithPath: jsonlPath)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if let data = (line + "\n").data(using: .utf8) {
                if !FileManager.default.fileExists(atPath: jsonlPath) {
                    FileManager.default.createFile(atPath: jsonlPath, contents: nil)
                }
                if let handle = FileHandle(forWritingAtPath: jsonlPath) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }

    /// Stable JSONL encoding: {"ts": ..., "kind": ..., "fields": {...}}.
    static func encode(event: HubEvent, at date: Date = Date()) -> String {
        let ts = ISO8601DateFormatter().string(from: date)
        var object: [String: Any] = ["ts": ts, "kind": event.kind]
        for (key, value) in event.fields {
            object["f_\(key)"] = value
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]
        ), let line = String(data: data, encoding: .utf8) else {
            return "{\"ts\":\"\(ts)\",\"kind\":\"\(event.kind)\"}"
        }
        return line
    }
}
