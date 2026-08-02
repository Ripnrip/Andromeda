import AndromedaAutoCache
import AndromedaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import NIOCore

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

    /// 🌟 Buffered forward — non-streaming Messages responses.
    public func forwardMessages(
        _ request: AnthropicRequest,
        headers: [String: String]
    ) async throws -> UpstreamResponse {
        let urlRequest = try makeMessagesRequest(request, headers: headers)
        logger.debug("Forwarding Anthropic request model=\(request.model) streaming=false")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AndromedaError.upstreamFailure(status: 502, message: "Invalid upstream response")
        }

        return UpstreamResponse(
            statusCode: http.statusCode,
            headers: headerMap(from: http),
            body: data
        )
    }

    /// 🌊 SSE stream forward — yields ByteBuffers as Anthropic emits events (no full-body buffer).
    public func forwardMessagesStreaming(
        _ request: AnthropicRequest,
        headers: [String: String]
    ) async throws -> UpstreamStreamResponse {
        let urlRequest = try makeMessagesRequest(request, headers: headers)
        logger.debug("Forwarding Anthropic SSE stream model=\(request.model)")

        #if canImport(FoundationNetworking)
        // Linux FoundationNetworking lacks URLSession.bytes — buffer then stream once.
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AndromedaError.upstreamFailure(status: 502, message: "Invalid upstream response")
        }
        let statusCode = http.statusCode
        let responseHeaders = headerMap(from: http)
        let stream = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            continuation.yield(buffer)
            continuation.finish()
        }
        return UpstreamStreamResponse(
            statusCode: statusCode,
            headers: responseHeaders,
            body: stream
        )
        #else
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AndromedaError.upstreamFailure(status: 502, message: "Invalid upstream response")
        }

        let statusCode = http.statusCode
        let responseHeaders = headerMap(from: http)
        let stream = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            let task = Task {
                do {
                    var chunk = [UInt8]()
                    chunk.reserveCapacity(8192)
                    for try await byte in bytes {
                        chunk.append(byte)
                        if chunk.count >= 8192 {
                            var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                            buffer.writeBytes(chunk)
                            continuation.yield(buffer)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        var buffer = ByteBufferAllocator().buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return UpstreamStreamResponse(
            statusCode: statusCode,
            headers: responseHeaders,
            body: stream
        )
        #endif
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
        return UpstreamResponse(statusCode: http.statusCode, headers: headerMap(from: http), body: data)
    }

    // MARK: - Private alchemy

    private func makeMessagesRequest(
        _ request: AnthropicRequest,
        headers: [String: String]
    ) throws -> URLRequest {
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
        return urlRequest
    }

    private func headerMap(from http: HTTPURLResponse) -> [String: String] {
        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let stringValue = value as? String {
                responseHeaders[name] = stringValue
            }
        }
        return responseHeaders
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

/// 🌊 Streaming upstream — SSE chunks as ByteBuffers (not one buffered body).
public struct UpstreamStreamResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: AsyncThrowingStream<ByteBuffer, Error>
}
