import AndromedaAutoCache
import AndromedaCore
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOCore

/// Builds the Hummingbird router exposing Autocache-compatible Anthropic routes.
public struct GatewayRouter: Sendable {
    public let controller: AutocacheController

    public init(controller: AutocacheController) {
        self.controller = controller
    }

    public func build() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        let controller = self.controller

        router.get("/") { _, _ -> Response in
            try Self.encodeJSON(controller.healthPayload())
        }
        router.get("/health") { _, _ -> Response in
            try Self.encodeJSON(controller.healthPayload())
        }

        if controller.config.enableMetrics {
            router.get("/metrics") { _, _ -> Response in
                try Self.encodeJSONObject(controller.metricsPayload())
            }
            router.get("/savings") { _, _ -> Response in
                try Self.encodeJSONObject(await controller.savingsPayload())
            }
        }

        router.get("/v1/models") { request, _ -> Response in
            try await Self.handleModels(controller: controller, request: request)
        }

        router.post("/v1/messages") { request, _ -> Response in
            try await Self.handleMessages(controller: controller, request: request)
        }

        return router
    }

    private static func handleMessages(
        controller: AutocacheController,
        request: Request
    ) async throws -> Response {
        let body = try await request.body.collect(upTo: 32 * 1024 * 1024)
        let data = Data(body.readableBytesView)
        let headers = headerDictionary(from: request.headers)
        let bypass = CacheMetadataHeaders.shouldBypass(
            headers: headers.map { ($0.key, $0.value) }
        )

        do {
            let processed = try await controller.processMessages(
                body: data,
                requestHeaders: headers,
                bypass: bypass
            )
            return makeUpstreamResponse(processed)
        } catch let error as AndromedaError {
            return errorResponse(for: error)
        }
    }

    private static func handleModels(
        controller: AutocacheController,
        request: Request
    ) async throws -> Response {
        let headers = headerDictionary(from: request.headers)
        guard let apiKey = controller.resolveAPIKey(from: headers), !apiKey.isEmpty else {
            return errorResponse(for: .missingAPIKey)
        }
        var forward = headers
        forward["x-api-key"] = apiKey
        do {
            let upstream = try await controller.proxy.getModels(headers: forward)
            return Response(
                status: .init(code: upstream.statusCode, reasonPhrase: ""),
                headers: HTTPFields(upstreamFilteredHeaders(upstream.headers)),
                body: .init(byteBuffer: ByteBuffer(data: upstream.body))
            )
        } catch let error as AndromedaError {
            return errorResponse(for: error)
        } catch {
            return errorResponse(
                for: .upstreamFailure(
                    status: 502,
                    message: "Failed to forward request to Anthropic API"
                )
            )
        }
    }

    private static func makeUpstreamResponse(_ processed: ProcessedMessagesResponse) -> Response {
        var fields = HTTPFields(upstreamFilteredHeaders(processed.upstream.headers))
        if let metadata = processed.metadata {
            for header in CacheMetadataHeaders.make(from: metadata) {
                if let name = HTTPField.Name(header.name) {
                    fields[name] = header.value
                }
            }
        } else if processed.bypassed {
            if let name = HTTPField.Name(AutocacheHeader.injected) {
                fields[name] = "false"
            }
        }
        if fields[.contentType] == nil {
            fields[.contentType] = "application/json"
        }

        return Response(
            status: .init(code: processed.upstream.statusCode, reasonPhrase: ""),
            headers: fields,
            body: .init(byteBuffer: ByteBuffer(data: processed.upstream.body))
        )
    }

    private static func errorResponse(for error: AndromedaError) -> Response {
        let status: HTTPResponse.Status
        switch error {
        case .invalidRequest, .decodingFailed, .missingAPIKey, .invalidConfiguration:
            status = .badRequest
        case .upstreamFailure(let code, _):
            status = .init(code: code == 0 ? 502 : code, reasonPhrase: "")
        case .encodingFailed:
            status = .internalServerError
        case .cancelled:
            status = .requestTimeout
        }

        let payload: [String: Any] = [
            "error": [
                "type": "autocache_error",
                "code": error.code,
                "message": error.message,
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    private static func headerDictionary(from headers: HTTPFields) -> [String: String] {
        var result: [String: String] = [:]
        for field in headers {
            result[field.name.rawName] = field.value
        }
        return result
    }

    private static func upstreamFilteredHeaders(
        _ headers: [String: String]
    ) -> [(HTTPField.Name, String)] {
        headers.compactMap { key, value in
            let lower = key.lowercased()
            if lower == "content-encoding" || lower == "transfer-encoding" || lower == "content-length" {
                return nil
            }
            guard let name = HTTPField.Name(key) else { return nil }
            return (name, value)
        }
    }

    private static func encodeJSON(_ value: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }

    private static func encodeJSONObject(_ object: [String: Any]) throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: object)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

private extension HTTPFields {
    init(_ pairs: [(HTTPField.Name, String)]) {
        self.init()
        for (name, value) in pairs {
            self[name] = value
        }
    }
}
