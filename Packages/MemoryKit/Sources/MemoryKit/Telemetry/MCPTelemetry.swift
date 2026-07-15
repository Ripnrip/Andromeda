/**
 * 🎭 The MCPTelemetry - Day-One Observability for MCP Sprawl
 *
 * "From the first scan, every duplicate sings into OSLog —
 * and an optional span hook waits for the observability agent
 * to wire OTLP or a file journal without rewriting the registry."
 *
 * - The Enchanted Observability Virtuoso of MemoryKit
 */

import Foundation
import OSLog

// MARK: - Events

/// 🌟 Structured MCP registry telemetry events (day-1 contract).
public enum MCPTelemetryEvent: Sendable, Equatable {
    /// Full registry scan completed.
    case registryScan(processCount: Int, uniqueGroups: Int, sprawlGroups: Int)
    /// A duplicate group exceeded one live instance.
    case duplicateDetected(group: String, count: Int)
    /// Raw live MCP-related process count from the enumerator.
    case processCount(Int)

    /// 🎨 Stable event name for logs / OTLP.
    public var name: String {
        switch self {
        case .registryScan: return "registry.scan"
        case .duplicateDetected: return "mcp.duplicate_detected"
        case .processCount: return "mcp.process_count"
        }
    }

    /// 💎 Structured payload suitable for JSON / span attributes.
    public var attributes: [String: String] {
        switch self {
        case let .registryScan(processCount, uniqueGroups, sprawlGroups):
            return [
                "process_count": String(processCount),
                "unique_groups": String(uniqueGroups),
                "sprawl_groups": String(sprawlGroups),
            ]
        case let .duplicateDetected(group, count):
            return [
                "duplicate_group": group,
                "count": String(count),
            ]
        case let .processCount(count):
            return ["count": String(count)]
        }
    }
}

// MARK: - Span hook (OTLP / file)

/// 🌟 Optional observability sink — OTLP exporter or file journal implements this.
/// Registry never depends on a concrete OpenTelemetry SDK.
public protocol MCPTelemetrySpanHooking: Sendable {
    /// Record one structured span/event. Implementations must be non-blocking-ish.
    func record(event: MCPTelemetryEvent, recordedAt: Date)
}

/// 🌙 No-op hook — default when observability agent has not wired OTLP yet.
public struct NullMCPTelemetrySpanHook: MCPTelemetrySpanHooking {
    public init() {}

    public func record(event: MCPTelemetryEvent, recordedAt: Date) {
        _ = event
        _ = recordedAt
    }
}

/// 🧪 Recording hook for tests — captures events without OSLog noise requirements.
public final class RecordingMCPTelemetrySpanHook: MCPTelemetrySpanHooking, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(MCPTelemetryEvent, Date)] = []

    public init() {}

    public func record(event: MCPTelemetryEvent, recordedAt: Date) {
        lock.lock()
        _events.append((event, recordedAt))
        lock.unlock()
    }

    public var events: [MCPTelemetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events.map(\.0)
    }

    public func reset() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
    }
}

/// 📜 Optional file append hook — one JSON line per event (observability agent friendly).
public struct FileMCPTelemetrySpanHook: MCPTelemetrySpanHooking {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func record(event: MCPTelemetryEvent, recordedAt: Date) {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "event": event.name,
            "recorded_at": formatter.string(from: recordedAt),
        ]
        for (key, value) in event.attributes {
            payload[key] = value
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        guard let lineData = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: lineData)
            }
        } else {
            try? lineData.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Emitting protocol

/// 🌟 Telemetry façade injectable into the registry.
public protocol MCPTelemetryEmitting: Sendable {
    func emit(_ event: MCPTelemetryEvent, recordedAt: Date)
}

public extension MCPTelemetryEmitting {
    func emit(_ event: MCPTelemetryEvent) {
        emit(event, recordedAt: Date())
    }
}

// MARK: - Concrete emitter

/**
 * 📡 MCPTelemetry — OSLog always-on + optional span hook for OTLP/file.
 *
 * Event names locked for day-1:
 * - `registry.scan`
 * - `mcp.duplicate_detected`
 * - `mcp.process_count`
 */
public struct MCPTelemetry: MCPTelemetryEmitting {
    public static let shared = MCPTelemetry()

    private let logger: Logger
    private let spanHook: any MCPTelemetrySpanHooking

    public init(
        subsystem: String = "com.multibrain.memorykit",
        category: String = "mcp.registry",
        spanHook: any MCPTelemetrySpanHooking = NullMCPTelemetrySpanHook()
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.spanHook = spanHook
    }

    /// 🌐 Emit to OSLog + optional observability hook.
    public func emit(_ event: MCPTelemetryEvent, recordedAt: Date = Date()) {
        let attrSummary = event.attributes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        switch event {
        case .registryScan:
            logger.info("🌐 ✨ \(event.name, privacy: .public) \(attrSummary, privacy: .public)")
        case .duplicateDetected:
            logger.warning("🌊 ⚠️ \(event.name, privacy: .public) \(attrSummary, privacy: .public)")
        case .processCount:
            logger.info("📊 ✨ \(event.name, privacy: .public) \(attrSummary, privacy: .public)")
        }

        spanHook.record(event: event, recordedAt: recordedAt)
    }
}

/// 🧪 Telemetry that only records into a hook (quiet tests).
public struct RecordingMCPTelemetry: MCPTelemetryEmitting {
    public let hook: RecordingMCPTelemetrySpanHook

    public init(hook: RecordingMCPTelemetrySpanHook = RecordingMCPTelemetrySpanHook()) {
        self.hook = hook
    }

    public func emit(_ event: MCPTelemetryEvent, recordedAt: Date = Date()) {
        hook.record(event: event, recordedAt: recordedAt)
    }
}
