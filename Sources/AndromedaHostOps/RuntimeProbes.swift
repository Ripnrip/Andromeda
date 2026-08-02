import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Lightweight HTTP probes used by setup / doctor. Failures become checklist rows — never crash the CLI.
public struct RuntimeProbes: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// True only for successful 2xx responses — 4xx/5xx must not count as reachable.
    public static func isSuccessfulHTTPStatus(_ statusCode: Int) -> Bool {
        (200..<300).contains(statusCode)
    }

    /// True when a health JSON body reports `status == "healthy"`. Missing/empty body is not healthy.
    public static func isHealthyPayload(_ data: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status = root["status"] as? String
        else {
            return false
        }
        return status == "healthy"
    }

    /// GET endpoint; true only on HTTP 2xx (wrong path / auth failures fail closed).
    public func isReachable(url: URL, timeout: TimeInterval = 2) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return Self.isSuccessfulHTTPStatus(http.statusCode)
        } catch {
            return false
        }
    }

    /// GET runtime `/health`; requires 2xx plus a healthy JSON payload.
    public func isHealthy(url: URL, timeout: TimeInterval = 2) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            guard Self.isSuccessfulHTTPStatus(http.statusCode) else { return false }
            return Self.isHealthyPayload(data)
        } catch {
            return false
        }
    }

    /// GET Qdrant `/collections` (or configured base); requires HTTP 2xx.
    public func isQdrantReachable(baseURL: URL, timeout: TimeInterval = 2) async -> Bool {
        let url = baseURL.appending(path: "collections")
        return await isReachable(url: url, timeout: timeout)
    }

    /// POST tools/list to `/mcp` and return tool names when authorized.
    public func listMCPToolNames(
        mcpURL: URL,
        bearerToken: String,
        timeout: TimeInterval = 3
    ) async -> Set<String>? {
        var request = URLRequest(url: mcpURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let result = root["result"] as? [String: Any],
                let tools = result["tools"] as? [[String: Any]]
            else {
                return nil
            }
            return Set(tools.compactMap { $0["name"] as? String })
        } catch {
            return nil
        }
    }
}

/// Best-effort guest VM detection used by setup / doctor checklists.
public enum GuestSignalDetector {
    /// Looks for env override, then common VM volume name hints.
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        if let explicit = environment["ANDROMEDA_VM_DETECTED"] {
            return explicit == "1" || explicit.lowercased() == "true"
        }
        if environment["ANDROMEDA_VM_SSH_HOST"] != nil {
            return true
        }
        guard fileManager.fileExists(atPath: "/Volumes") else { return false }
        let volumes = (try? fileManager.contentsOfDirectory(atPath: "/Volumes")) ?? []
        return volumes.contains {
            $0.localizedCaseInsensitiveContains("vm")
                || $0.localizedCaseInsensitiveContains("guest")
                || $0.localizedCaseInsensitiveContains("habitat")
        }
    }
}
