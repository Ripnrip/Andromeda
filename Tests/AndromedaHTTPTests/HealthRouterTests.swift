import AndromedaDomain
import AndromedaHTTP
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@Suite("AndromedaHTTP.HealthRouter")
struct HealthRouterTests {
    @Test("health endpoint returns runtime status")
    func health() async throws {
        let app = Application(
            router: HealthRouter(
                provider: StaticHealthProvider(
                    status: RuntimeHealthStatus(
                        status: "healthy",
                        service: "Andromeda Runtime",
                        version: "0.2.0-runtime-v2",
                        journal: "memory"
                    )
                )
            ).build()
        )

        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = String(buffer: response.body)
                #expect(body.contains("healthy"))
                #expect(body.contains("Andromeda Runtime"))
                #expect(body.contains("memory"))
            }
        }
    }
}

private struct StaticHealthProvider: HealthStatusProviding {
    let status: RuntimeHealthStatus

    func healthStatus() async -> RuntimeHealthStatus {
        status
    }
}
