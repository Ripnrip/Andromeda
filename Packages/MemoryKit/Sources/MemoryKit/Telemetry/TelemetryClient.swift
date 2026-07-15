/**
 * 🎭 The TelemetryClient - Lantern Keepers of the Observability Spine
 *
 * "Spans are sparks; events are fireworks; JSONL is the diary we keep when
 * the collector naps. We speak OTLP when the harbor is awake — and OSLog
 * when Console.app is the only audience in the house."
 *
 * - The Cosmic Observability Orchestrator
 */

import Foundation
import OSLog

#if canImport(os)
import os
#endif

// MARK: - Event / Span models

/// 🌟 Kind of telemetry record — events vs span lifecycle.
public enum TelemetryRecordKind: String, Sendable, Codable, Equatable {
    case event
    case spanStart = "span_start"
    case spanEnd = "span_end"
}

/// 🚦 How a span closed — never invent success from silence.
public enum TelemetrySpanStatus: String, Sendable, Codable, Equatable {
    case ok
    case error
    case unset
}

/**
 * 💎 One crystallized telemetry record (JSONL-friendly).
 *
 * Attributes must stay free of vault narratives / PII — counts, statuses, IDs only.
 */
public struct TelemetryEvent: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let kind: TelemetryRecordKind
    public let timestamp: Date
    public let attributes: [String: String]
    public let spanId: String?
    public let parentSpanId: String?
    public let status: TelemetrySpanStatus?
    public let serviceName: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: TelemetryRecordKind = .event,
        timestamp: Date = Date(),
        attributes: [String: String] = [:],
        spanId: String? = nil,
        parentSpanId: String? = nil,
        status: TelemetrySpanStatus? = nil,
        serviceName: String = TelemetryHub.defaultServiceName
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.timestamp = timestamp
        self.attributes = attributes
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.status = status
        self.serviceName = serviceName
    }
}

/// 🔮 Opaque span handle — pass back to `endSpan`.
public struct TelemetrySpanHandle: Sendable, Equatable {
    public let spanId: String
    public let name: String
    public let startedAt: Date
    public let attributes: [String: String]

    public init(
        spanId: String = UUID().uuidString,
        name: String,
        startedAt: Date = Date(),
        attributes: [String: String] = [:]
    ) {
        self.spanId = spanId
        self.name = name
        self.startedAt = startedAt
        self.attributes = attributes
    }
}

// MARK: - Protocol

/// 🌐 The portal every MemoryKit emitter walks through.
public protocol TelemetryClient: Sendable {
    /// ✨ Fire a discrete event (counters, heartbeats, proof ticks).
    func emit(_ event: TelemetryEvent) async

    /// 🌟 Open a span — returns a handle for `endSpan`.
    func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle

    /// 🎉 Close a span with status + optional extra attributes.
    func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async
}

public extension TelemetryClient {
    /// 🎪 Convenience: start → work → end with duration attribute.
    func withSpan<T: Sendable>(
        _ name: String,
        attributes: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let handle = await startSpan(name, attributes: attributes)
        do {
            let result = try await operation()
            let durationMs = Int(Date().timeIntervalSince(handle.startedAt) * 1000)
            await endSpan(
                handle,
                status: .ok,
                attributes: ["duration_ms": String(durationMs)]
            )
            return result
        } catch {
            let durationMs = Int(Date().timeIntervalSince(handle.startedAt) * 1000)
            await endSpan(
                handle,
                status: .error,
                attributes: [
                    "duration_ms": String(durationMs),
                    "error.type": String(describing: type(of: error))
                ]
            )
            throw error
        }
    }
}

// MARK: - Hub (process-wide default)

/// 🏛️ Process-wide lantern rack — HealthSnapshotLoader and registries consult this.
public enum TelemetryHub: Sendable {
    public static let defaultServiceName = "anima-multibrain"

    /// 🌙 Default: silent no-op until an app installs real clients.
    nonisolated(unsafe) private static var _client: (any TelemetryClient)?

    private static let lock = NSLock()

    /// 🎨 Install the active client (multiplex recommended).
    public static func install(_ client: (any TelemetryClient)?) {
        lock.lock()
        defer { lock.unlock() }
        _client = client
    }

    /// 🔮 Current client (nil = no telemetry).
    public static var client: (any TelemetryClient)? {
        lock.lock()
        defer { lock.unlock() }
        return _client
    }

    /// ✨ Best-effort emit — never throws into callers.
    public static func emit(_ event: TelemetryEvent) {
        guard let client = client else { return }
        Task {
            await client.emit(event)
        }
    }

    /// 🌟 Best-effort span start/end around a sync body (loader path).
    public static func emitSpanSync(
        name: String,
        attributes: [String: String],
        status: TelemetrySpanStatus,
        extraAttributes: [String: String] = [:]
    ) {
        guard let client = client else { return }
        Task {
            let handle = await client.startSpan(name, attributes: attributes)
            await client.endSpan(handle, status: status, attributes: extraAttributes)
            await client.emit(
                TelemetryEvent(
                    name: name,
                    kind: .event,
                    attributes: attributes.merging(extraAttributes) { _, new in new }
                        .merging(["span.status": status.rawValue]) { _, new in new }
                )
            )
        }
    }
}

// MARK: - Multiplex

/// 🎪 Fan-out — one emit, many theaters.
public struct MultiplexTelemetryClient: TelemetryClient {
    private let clients: [any TelemetryClient]

    public init(clients: [any TelemetryClient]) {
        self.clients = clients
    }

    public func emit(_ event: TelemetryEvent) async {
        for client in clients {
            await client.emit(event)
        }
    }

    public func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        let handle = TelemetrySpanHandle(name: name, attributes: attributes)
        for client in clients {
            // 🎨 Each backend gets the same span id so JSONL ↔ OTLP correlate.
            _ = await client.startSpan(name, attributes: attributes.merging([
                "span.id": handle.spanId
            ]) { _, new in new })
        }
        return handle
    }

    public func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {
        for client in clients {
            await client.endSpan(handle, status: status, attributes: attributes)
        }
    }
}

// MARK: - No-op

/// 🌙 Peaceful slumber — tests that want silence.
public struct NoOpTelemetryClient: TelemetryClient {
    public init() {}

    public func emit(_ event: TelemetryEvent) async {}

    public func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        TelemetrySpanHandle(name: name, attributes: attributes)
    }

    public func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {}
}

// MARK: - OSLog

/// 📜 Console.app / unified logging sink.
public struct OSLogTelemetryClient: TelemetryClient {
    private let logger: Logger

    public init(subsystem: String = "ai.multibrain.anima", category: String = "telemetry") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func emit(_ event: TelemetryEvent) async {
        let attrs = event.attributes
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        logger.info("✨ event name=\(event.name, privacy: .public) \(attrs, privacy: .public)")
    }

    public func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        let handle = TelemetrySpanHandle(
            spanId: attributes["span.id"] ?? UUID().uuidString,
            name: name,
            attributes: attributes
        )
        logger.debug("🌟 span.start name=\(name, privacy: .public) id=\(handle.spanId, privacy: .public)")
        return handle
    }

    public func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {
        logger.debug(
            "🎉 span.end name=\(handle.name, privacy: .public) status=\(status.rawValue, privacy: .public)"
        )
    }
}

// MARK: - File JSONL

/// 💎 Append-only JSONL under `~/.multibrain/telemetry/` (or custom directory).
///
/// Grafana Agent / Alloy can scrape this directory later. Proven path when OTLP is down.
public final class FileJSONLTelemetryClient: TelemetryClient, @unchecked Sendable {
    public let directory: URL
    private let fileName: String
    private let lock = NSLock()
    private let encoder: JSONEncoder

    /// 🏠 Default: `~/.multibrain/telemetry/anima-events.jsonl`
    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MULTIBRAIN_TELEMETRY_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".multibrain", isDirectory: true)
            .appendingPathComponent("telemetry", isDirectory: true)
    }

    public init(directory: URL = FileJSONLTelemetryClient.defaultDirectory, fileName: String = "anima-events.jsonl") {
        self.directory = directory
        self.fileName = fileName
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public var fileURL: URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    public func emit(_ event: TelemetryEvent) async {
        append(event)
    }

    public func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        let spanId = attributes["span.id"] ?? UUID().uuidString
        let handle = TelemetrySpanHandle(spanId: spanId, name: name, attributes: attributes)
        append(
            TelemetryEvent(
                name: name,
                kind: .spanStart,
                attributes: attributes,
                spanId: spanId
            )
        )
        return handle
    }

    public func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {
        let merged = handle.attributes.merging(attributes) { _, new in new }
        let durationMs = Int(Date().timeIntervalSince(handle.startedAt) * 1000)
        var withDuration = merged
        if withDuration["duration_ms"] == nil {
            withDuration["duration_ms"] = String(durationMs)
        }
        append(
            TelemetryEvent(
                name: handle.name,
                kind: .spanEnd,
                attributes: withDuration,
                spanId: handle.spanId,
                status: status
            )
        )
    }

    /// 🧪 Read all records (tests / proof scripts).
    public func readAllEvents() throws -> [TelemetryEvent] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.isEmpty }
            .map { line in
                guard let data = String(line).data(using: .utf8) else {
                    throw TelemetryIOError.invalidLine
                }
                return try decoder.decode(TelemetryEvent.self, from: data)
            }
    }

    // 🎨 Append one JSON object per line — atomic enough for day-1 single writer.
    private func append(_ event: TelemetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(event)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                try line.write(to: url, atomically: true, encoding: .utf8)
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let bytes = line.data(using: .utf8) {
                    try handle.write(contentsOf: bytes)
                }
            }
        } catch {
            // 🌩️ Telemetry must never sink the show — swallow IO storms.
            #if DEBUG
            fputs("🌩️ FileJSONLTelemetryClient: \(error)\n", stderr)
            #endif
        }
    }
}

public enum TelemetryIOError: Error {
    case invalidLine
}

// MARK: - OTLP HTTP exporter (stub)

/// 🌐 Best-effort OTLP/HTTP JSON traces exporter (day-1 stub — no full OTel SDK).
///
/// Posts a minimal `resourceSpans` payload to `http://127.0.0.1:4318/v1/traces`.
/// Connection failures are swallowed so offline Studio stays quiet.
public final class OTLPHTTPExporter: TelemetryClient, @unchecked Sendable {
    public let endpoint: URL
    private let session: URLSession
    private let serviceName: String
    /// 🧪 Injected POST for unit tests (nil = live URLSession).
    private let postHandler: (@Sendable (URL, Data) async throws -> (Int, Data))?

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:4318/v1/traces")!,
        serviceName: String = TelemetryHub.defaultServiceName,
        session: URLSession = .shared,
        postHandler: (@Sendable (URL, Data) async throws -> (Int, Data))? = nil
    ) {
        self.endpoint = endpoint
        self.serviceName = serviceName
        self.session = session
        self.postHandler = postHandler
    }

    public func emit(_ event: TelemetryEvent) async {
        // 🎨 Events ride as zero-duration spans so a traces-only pipeline still sees them.
        let handle = TelemetrySpanHandle(name: event.name, attributes: event.attributes)
        await endSpan(handle, status: .ok, attributes: event.attributes.merging([
            "telemetry.kind": "event"
        ]) { _, new in new })
    }

    public func startSpan(_ name: String, attributes: [String: String]) async -> TelemetrySpanHandle {
        TelemetrySpanHandle(
            spanId: attributes["span.id"] ?? UUID().uuidString,
            name: name,
            attributes: attributes
        )
    }

    public func endSpan(
        _ handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) async {
        let payload = makeOTLPPayload(handle: handle, status: status, attributes: attributes)
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            if let postHandler {
                _ = try await postHandler(endpoint, data)
                return
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            request.timeoutInterval = 2
            _ = try await session.data(for: request)
        } catch {
            // 🌙 Collector asleep — FileJSONL still holds the diary.
        }
    }

    /// 🔮 Minimal OTLP JSON body (stub — not a full protobuf codec).
    func makeOTLPPayload(
        handle: TelemetrySpanHandle,
        status: TelemetrySpanStatus,
        attributes: [String: String]
    ) -> [String: Any] {
        let startNano = Int64(handle.startedAt.timeIntervalSince1970 * 1_000_000_000)
        let endNano = Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let otlpStatus: Int = {
            switch status {
            case .ok: return 1
            case .error: return 2
            case .unset: return 0
            }
        }()
        let attrList: [[String: Any]] = attributes.map { key, value in
            ["key": key, "value": ["stringValue": value]]
        }
        return [
            "resourceSpans": [
                [
                    "resource": [
                        "attributes": [
                            ["key": "service.name", "value": ["stringValue": serviceName]]
                        ]
                    ],
                    "scopeSpans": [
                        [
                            "scope": ["name": "MemoryKit.Telemetry", "version": "0.1.0"],
                            "spans": [
                                [
                                    "traceId": traceIdHex(from: handle.spanId),
                                    "spanId": spanIdHex(from: handle.spanId),
                                    "name": handle.name,
                                    "kind": 1,
                                    "startTimeUnixNano": String(startNano),
                                    "endTimeUnixNano": String(endNano),
                                    "attributes": attrList,
                                    "status": ["code": otlpStatus]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    // 🎨 OTLP wants hex ids — derive stable hex from UUID string bytes.
    private func spanIdHex(from uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "")
        let prefix = String(compact.prefix(16))
        return prefix.padding(toLength: 16, withPad: "0", startingAt: 0)
    }

    private func traceIdHex(from uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "")
        let padded = compact.padding(toLength: 32, withPad: "0", startingAt: 0)
        return String(padded.prefix(32))
    }
}
