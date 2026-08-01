import AndromedaDomain
import AndromedaMemory
import Foundation
import HTTPTypes
import Hummingbird

public struct RuntimeRouter: Sendable {
    private let healthProvider: any HealthStatusProviding
    private let memoryRuntime: MemoryRuntime

    public init(healthProvider: any HealthStatusProviding, memoryRuntime: MemoryRuntime) {
        self.healthProvider = healthProvider
        self.memoryRuntime = memoryRuntime
    }

    public func build() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        let healthProvider = self.healthProvider
        let memoryRuntime = self.memoryRuntime

        router.get("/health") { _, _ -> Response in
            try Self.encodeJSON(await healthProvider.healthStatus())
        }

        router.post("/v1/memory/remember") { request, _ -> Response in
            do {
                let rememberRequest = try await Self.decode(RecallOrRememberRequest<RememberIntent>.self, from: request).payload
                let response = try await memoryRuntime.remember(rememberRequest)
                return try Self.encodeJSON(response)
            } catch {
                return Self.errorResponse(for: error)
            }
        }

        router.post("/v1/memory/recall") { request, _ -> Response in
            do {
                let recallRequest = try await Self.decode(RecallOrRememberRequest<RecallRequest>.self, from: request).payload
                let response = try await memoryRuntime.recall(recallRequest)
                return try Self.encodeJSON(response)
            } catch {
                return Self.errorResponse(for: error)
            }
        }

        return router
    }

    private static func decode<T: Decodable>(_ type: T.Type, from request: Request) async throws -> T {
        let body = try await request.body.collect(upTo: 4 * 1024 * 1024)
        let data = Data(body.readableBytesView)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AndromedaRuntimeError.invalidRuntimeRequest("Failed to decode request body: \(error.localizedDescription)")
        }
    }

    private static func encodeJSON(_ value: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(data: data))
        )
    }

    private static func errorResponse(for error: Error) -> Response {
        let runtimeError = error as? AndromedaRuntimeError
        let status: HTTPResponse.Status
        switch runtimeError {
        case .invalidMemoryContent, .invalidRecallQuery, .invalidRuntimeRequest:
            status = .badRequest
        case .none:
            status = .internalServerError
        default:
            status = .internalServerError
        }

        let payload: [String: String] = [
            "error": runtimeError?.localizedDescription ?? error.localizedDescription,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: .init(data: data))
        )
    }
}

private struct RecallOrRememberRequest<Payload: Decodable>: Decodable {
    let payload: Payload

    init(from decoder: Decoder) throws {
        self.payload = try Payload(from: decoder)
    }
}
