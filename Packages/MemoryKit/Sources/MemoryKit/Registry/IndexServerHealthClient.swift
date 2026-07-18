/**
 * 🎭 The IndexServerHealthClient - Ladybug Pulse Probe
 *
 * "launchd may swear the index-server lives while :8286 sleeps.
 * We knock the glass ourselves — short timeout, fail-open detail,
 * satellite hosts skip the knock entirely."
 *
 * - The Spellbinding Museum Director of Fleet Observability
 */

import Foundation

/// 🌟 Result of a direct GET to Ladybug index-server `/health`.
public struct IndexServerHealthResult: Sendable, Equatable {
    public let ok: Bool
    public let statusCode: Int?
    public let detail: String
    public let latencyMs: Int
    /// 🛰️ True when this host role skipped the probe (satellite / isolated).
    public let skipped: Bool

    public init(
        ok: Bool,
        statusCode: Int? = nil,
        detail: String,
        latencyMs: Int = 0,
        skipped: Bool = false
    ) {
        self.ok = ok
        self.statusCode = statusCode
        self.detail = detail
        self.latencyMs = latencyMs
        self.skipped = skipped
    }

    public static func skipped(reason: String) -> IndexServerHealthResult {
        IndexServerHealthResult(ok: true, detail: reason, skipped: true)
    }
}

/// 🌟 Injectable probe — tests mock without touching the network.
public protocol IndexServerHealthProbing: Sendable {
    func probe() -> IndexServerHealthResult
}

/// 🧪 Deterministic mock for Swift Testing.
public struct MockIndexServerHealthProbe: IndexServerHealthProbing {
    private let result: IndexServerHealthResult

    public init(result: IndexServerHealthResult) {
        self.result = result
    }

    public func probe() -> IndexServerHealthResult { result }
}

/**
 * 🩺 Live GET `http://127.0.0.1:8286/health` with a hard timeout.
 *
 * Synchronous on purpose so MainActor Observe refresh stays one pulse.
 * Never throws — always returns a structured result (fail-open detail).
 */
public struct IndexServerHealthClient: IndexServerHealthProbing {
    public let url: URL
    public let timeout: TimeInterval
    public let observingHostRole: HostRole

    public init(
        url: URL = URL(string: "http://127.0.0.1:8286/health")!,
        timeout: TimeInterval = 1.5,
        observingHostRole: HostRole = .hub
    ) {
        self.url = url
        self.timeout = timeout
        self.observingHostRole = observingHostRole
    }

    public func probe() -> IndexServerHealthResult {
        // 🛰️ Hub-only — Book / Mini never fake Ladybug red.
        guard observingHostRole == .hub else {
            return .skipped(reason: "n/a (satellite — no LadybugDB hub)")
        }

        let started = Date()
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        let box = ProbeBox()
        let sem = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            sem.signal()
        }
        task.resume()
        let wait = sem.wait(timeout: .now() + timeout + 0.25)
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)

        if wait == .timedOut {
            task.cancel()
            return IndexServerHealthResult(
                ok: false,
                detail: "index-server /health timed out after \(Int(timeout))s",
                latencyMs: latencyMs
            )
        }

        if let error = box.error {
            return IndexServerHealthResult(
                ok: false,
                detail: "index-server down: \(error.localizedDescription)",
                latencyMs: latencyMs
            )
        }

        let statusCode = (box.response as? HTTPURLResponse)?.statusCode
        guard let statusCode else {
            return IndexServerHealthResult(
                ok: false,
                detail: "index-server /health — no HTTP response",
                latencyMs: latencyMs
            )
        }

        let ok = (200..<300).contains(statusCode)
        let bodyHint: String = {
            guard let data = box.data, let text = String(data: data, encoding: .utf8) else {
                return ""
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            return " · \(trimmed.prefix(80))"
        }()

        return IndexServerHealthResult(
            ok: ok,
            statusCode: statusCode,
            detail: ok
                ? "HTTP \(statusCode) from \(url.absoluteString)\(bodyHint)"
                : "HTTP \(statusCode) from \(url.absoluteString)\(bodyHint)",
            latencyMs: latencyMs
        )
    }
}

/// 🔒 Tiny mutable box for URLSession completion → sync bridge (Observe-only).
private final class ProbeBox: @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
}
