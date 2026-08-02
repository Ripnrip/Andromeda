import AndromedaDomain
import Foundation
import HTTPTypes
import Hummingbird

/// Read-only health dependency injected into the HTTP edge.
public protocol HealthStatusProviding: Sendable {
    func healthStatus() async -> RuntimeHealthStatus
}

/// Hummingbird adapter for the initial runtime health surface.
public struct HealthRouter: Sendable {
    private let provider: any HealthStatusProviding

    public init(provider: any HealthStatusProviding) {
        self.provider = provider
    }

    public func build() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        let provider = self.provider

        router.get("/health") { _, _ -> Response in
            let status = await provider.healthStatus()
            return try Self.encodeJSON(status)
        }

        return router
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
}
