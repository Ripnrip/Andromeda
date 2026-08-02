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
    public init() {}

    public func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = request.body
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return UpstreamHTTPResponse(status: status, body: data)
    }
}
