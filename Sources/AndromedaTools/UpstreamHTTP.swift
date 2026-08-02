import Foundation

public struct UpstreamHTTPRequest: Sendable, Equatable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct UpstreamHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Executes upstream HTTP calls on the host. Injectable so tests never touch
/// the network and can capture exactly what the broker sent.
public protocol UpstreamHTTPExecuting: Sendable {
    func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse
}

public struct URLSessionUpstreamHTTP: UpstreamHTTPExecuting {
    /// Maximum bytes to download from the upstream before stopping. Bounds host
    /// memory when an authenticated VM requests a very large resource.
    public let maxDownloadBytes: Int

    public init(maxDownloadBytes: Int = 8 * 1_024 * 1_024) {
        self.maxDownloadBytes = maxDownloadBytes
    }

    public func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = request.body

        // Stream the response body with an early-exit once the configured limit
        // is reached. Prevents a large GitHub resource from buffering fully
        // in host memory before bodyText applies maxResponseBytes.
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        var collected = Data()
        collected.reserveCapacity(min(maxDownloadBytes, 64 * 1_024))
        do {
            for try await byte in asyncBytes {
                collected.append(byte)
                if collected.count >= maxDownloadBytes { break }
            }
        } catch {
            // Network errors mid-stream are non-fatal for partial reads.
        }

        return UpstreamHTTPResponse(status: status, body: collected)
    }
}
