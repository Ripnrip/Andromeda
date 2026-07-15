import AndromedaAutoCache
import AndromedaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// HTTP client that forwards Autocache-transformed Anthropic Messages requests.
public struct AnthropicProxyClient: @unchecked Sendable {
    public let anthropicURL: URL
    private let session: URLSession
    private let logger: Logger

    public init(
        anthropicURL: String,
        session: URLSession = .shared,
        logger: Logger = Logger(label: "andromeda.gateway.proxy")
    ) {
        let normalized = anthropicURL.hasSuffix("/")
            ? String(anthropicURL.dropLast())
            : anthropicURL
        self.anthropicURL = URL(string: normalized) ?? URL(string: "https://api.anthropic.com")!
        self.session = session
        self.logger = logger
    }

    public func validate(_ request: AnthropicRequest) throws {
        guard !request.model.isEmpty else {
            throw AndromedaError.invalidRequest("model is required")
        }
        guard request.maxTokens > 0 else {
            throw AndromedaError.invalidRequest("max_tokens must be positive")
        }
        guard !request.messages.isEmpty else {
            throw AndromedaError.invalidRequest("messages cannot be empty")
        }
    }

    public func forwardMessages(
        _ request: AnthropicRequest,
        headers: [String: String]
    ) async throws -> UpstreamResponse {
        let url = anthropicURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if headers["anthropic-version"] == nil && headers["Anthropic-Version"] == nil {
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        for (key, value) in headers where !shouldSkipHeader(key) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw AndromedaError.encodingFailed(error.localizedDescription)
        }

        logger.debug("Forwarding Anthropic request model=\(request.model) streaming=\(request.isStreaming)")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AndromedaError.upstreamFailure(status: 502, message: "Invalid upstream response")
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let stringValue = value as? String {
                responseHeaders[name] = stringValue
            }
        }

        return UpstreamResponse(
            statusCode: http.statusCode,
            headers: responseHeaders,
            body: data
        )
    }

    public func getModels(headers: [String: String]) async throws -> UpstreamResponse {
        let url = anthropicURL.appendingPathComponent("v1/models")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 60
        if headers["anthropic-version"] == nil && headers["Anthropic-Version"] == nil {
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        for (key, value) in headers where !shouldSkipHeader(key) {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AndromedaError.upstreamFailure(status: 502, message: "Invalid upstream response")
        }
        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let stringValue = value as? String {
                responseHeaders[name] = stringValue
            }
        }
        return UpstreamResponse(statusCode: http.statusCode, headers: responseHeaders, body: data)
    }

    private func shouldSkipHeader(_ key: String) -> Bool {
        let lower = key.lowercased()
        return [
            "host", "content-length", "connection", "transfer-encoding",
            "accept-encoding", "content-encoding",
        ].contains(lower)
    }
}

public struct UpstreamResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data
}
