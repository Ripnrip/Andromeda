import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Probe protocol

/// Injectable probe interface so tests can simulate HTTP outcomes without
/// real network calls.
public protocol WitnessProbing: Sendable {
    /// Probe a single target and return a typed result.
    func probe(target: WitnessTarget) async -> WitnessProbeResult
}

// MARK: - URLSession probe

/// Production probe using `URLSession`. Correctly distinguishes:
/// - **Success** (2xx within configured range)
/// - **HTTP error** (non-2xx response received)
/// - **Timeout** (request timed out)
/// - **Connection failure** (DNS, refused, TLS, etc.)
///
/// Does not inspect or overfit response payloads — only the HTTP status code
/// and transport-level errors matter for witness classification.
public struct WitnessProbe: WitnessProbing {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func probe(target: WitnessTarget) async -> WitnessProbeResult {
        guard let url = URL(string: target.url) else {
            return WitnessProbeResult(
                targetLabel: target.label,
                outcome: .connectionFailure("invalid URL: \(target.url)"),
                checkedAt: Date()
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = target.timeoutSeconds

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return WitnessProbeResult(
                    targetLabel: target.label,
                    outcome: .connectionFailure("non-HTTP response"),
                    checkedAt: Date()
                )
            }
            let statusCode = http.statusCode
            let outcome: WitnessProbeResult.Outcome = target.isSuccessStatus(statusCode)
                ? .success(statusCode: statusCode)
                : .httpError(statusCode: statusCode)
            return WitnessProbeResult(
                targetLabel: target.label,
                outcome: outcome,
                checkedAt: Date()
            )
        } catch let urlError as URLError {
            let outcome: WitnessProbeResult.Outcome
            switch urlError.code {
            case .timedOut:
                outcome = .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                outcome = .connectionFailure("no network")
            case .cannotFindHost, .cannotConnectToHost:
                outcome = .connectionFailure(urlError.localizedDescription)
            case .dnsLookupFailed:
                outcome = .connectionFailure("DNS lookup failed")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                outcome = .connectionFailure("TLS failure: \(urlError.localizedDescription)")
            default:
                outcome = .connectionFailure(urlError.localizedDescription)
            }
            return WitnessProbeResult(
                targetLabel: target.label,
                outcome: outcome,
                checkedAt: Date()
            )
        } catch {
            return WitnessProbeResult(
                targetLabel: target.label,
                outcome: .connectionFailure("unexpected error: \(error.localizedDescription)"),
                checkedAt: Date()
            )
        }
    }
}

// MARK: - Test probe

/// A probe that returns pre-configured results in sequence. For tests only —
/// no real network calls are made.
public actor RecordedWitnessProbe: WitnessProbing {
    private let results: [WitnessProbeResult]
    private var index = 0

    public init(results: [WitnessProbeResult]) {
        self.results = results
    }

    public func probe(target: WitnessTarget) async -> WitnessProbeResult {
        let current = index
        index += 1
        guard current < results.count else {
            // Return last result if exhausted — keeps tests simple.
            return results.last ?? WitnessProbeResult(
                targetLabel: target.label,
                outcome: .connectionFailure("no more recorded results"),
                checkedAt: Date()
            )
        }
        // Override the label to match the target being probed.
        let stored = results[current]
        return WitnessProbeResult(
            targetLabel: target.label,
            outcome: stored.outcome,
            checkedAt: Date()
        )
    }
}
