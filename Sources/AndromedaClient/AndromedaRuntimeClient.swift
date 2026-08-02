import AndromedaDomain
import Foundation

/// Typed guest-side client for the Milestone 0 health endpoint.
public struct AndromedaRuntimeClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func health() async throws -> RuntimeHealthStatus {
        let requestURL = baseURL.appending(path: "health")
        let (data, _) = try await session.data(from: requestURL)
        return try JSONDecoder().decode(RuntimeHealthStatus.self, from: data)
    }
}
