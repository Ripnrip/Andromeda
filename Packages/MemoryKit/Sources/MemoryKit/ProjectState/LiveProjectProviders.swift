/**
 * 🎭 The Live Project Providers - HTTP Adapters Behind the Velvet
 *
 * "Multica speaks Habitat REST; Linear speaks GraphQL when keyed.
 * Clients hear only project.state.* — never a brand name on the glass."
 *
 * - The Cosmic Operator Fabric Orchestrator
 */

import Foundation

// MARK: - Configuration (operator / Studio only)

/// 🌟 Operator config for live `project.state` providers — never ship brands to clients.
public struct ProjectStateBridgeConfiguration: Sendable, Equatable {
    public var multicaBaseURL: URL
    public var multicaToken: String?
    public var multicaWorkspaceID: String
    public var multicaProjectID: String?
    public var linearAPIKey: String?
    public var linearTeamID: String?
    public var linearProjectID: String?

    public init(
        multicaBaseURL: URL = URL(string: "http://127.0.0.1:3637")!,
        multicaToken: String? = nil,
        multicaWorkspaceID: String = "5bc5bd70-8e83-41db-8a5b-46ccfc8b5422",
        multicaProjectID: String? = "17237130-3eef-4562-89dd-9269caa371ba",
        linearAPIKey: String? = nil,
        linearTeamID: String? = "373469d2-1278-4868-b6f6-708d9d4a48be",
        linearProjectID: String? = "df11aac0-8284-48ac-b2b8-b85838123938"
    ) {
        self.multicaBaseURL = multicaBaseURL
        self.multicaToken = multicaToken
        self.multicaWorkspaceID = multicaWorkspaceID
        self.multicaProjectID = multicaProjectID
        self.linearAPIKey = linearAPIKey
        self.linearTeamID = linearTeamID
        self.linearProjectID = linearProjectID
    }

    /// 🔮 Load from process environment, optional dotenv files, + `~/.multica/config.json` (Studio operator path).
    /// Precedence: process env wins; then first dotenv hit among documented paths (never logs secret values).
    public static func loadFromEnvironment(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dotenvSearchPaths: [String]? = nil
    ) -> ProjectStateBridgeConfiguration {
        let fileVars = Self.loadDotenvValues(
            fileManager: fileManager,
            searchPaths: dotenvSearchPaths ?? Self.defaultDotenvSearchPaths()
        )
        func resolved(_ key: String) -> String? {
            if let value = environment[key], !value.isEmpty { return value }
            if let value = fileVars[key], !value.isEmpty { return value }
            return nil
        }

        var config = ProjectStateBridgeConfiguration()
        if let base = resolved("MULTICA_SERVER_URL"), let url = URL(string: base) {
            config.multicaBaseURL = url
        }
        if let ws = resolved("MULTICA_WORKSPACE_ID") {
            config.multicaWorkspaceID = ws
        }
        if let project = resolved("MULTICA_PROJECT_ID") {
            config.multicaProjectID = project
        }
        if let token = resolved("MULTICA_TOKEN") {
            config.multicaToken = token
        } else {
            config.multicaToken = Self.readMulticaTokenFromConfig(fileManager: fileManager)
        }
        if let key = resolved("LINEAR_API_KEY") {
            config.linearAPIKey = key
        }
        if let team = resolved("LINEAR_TEAM_ID") {
            config.linearTeamID = team
        }
        if let project = resolved("LINEAR_PROJECT_ID") {
            config.linearProjectID = project
        }
        return config
    }

    /// 🗺️ Documented operator dotenv locations — repo `.env` then `~/.multibrain/.env`.
    public static func defaultDotenvSearchPaths() -> [String] {
        let home = NSHomeDirectory()
        return [
            (home as NSString).appendingPathComponent("Developer/multibrain/.env"),
            (home as NSString).appendingPathComponent(".multibrain/.env"),
        ]
    }

    /// 💎 Merge KEY=VALUE lines across dotenv paths (no shell expansion; never logs values).
    /// Earlier paths win on key collisions; later files fill missing keys (Codex P2: don't stop at first hit).
    public static func loadDotenvValues(
        fileManager: FileManager = .default,
        searchPaths: [String]
    ) -> [String: String] {
        var merged: [String: String] = [:]
        var loadedFiles: [String] = []
        for path in searchPaths {
            guard fileManager.fileExists(atPath: path),
                  let data = fileManager.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            var fileValues: [String: String] = [:]
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\""))
                    || (value.hasPrefix("'") && value.hasSuffix("'"))
                {
                    value = String(value.dropFirst().dropLast())
                }
                guard !key.isEmpty else { continue }
                fileValues[key] = value
            }
            guard !fileValues.isEmpty else { continue }
            loadedFiles.append(URL(fileURLWithPath: path).lastPathComponent)
            for (key, value) in fileValues where merged[key] == nil {
                merged[key] = value
            }
        }
        if !merged.isEmpty {
            print("💎 ✨ Dotenv wisdom merged from \(loadedFiles.joined(separator: "+")) (\(merged.count) keys, values cloaked)")
        }
        return merged
    }

    /// 🧪 Whether process env or dotenv yields a non-empty `LINEAR_API_KEY` (live proofs — never logs the key).
    public static func linearKeyPresentFromEnvironment(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dotenvSearchPaths: [String]? = nil
    ) -> Bool {
        let config = loadFromEnvironment(
            fileManager: fileManager,
            environment: environment,
            dotenvSearchPaths: dotenvSearchPaths
        )
        return !(config.linearAPIKey ?? "").isEmpty
    }

    /// 💎 Read Multica CLI token without logging it — operator convenience on Studio.
    private static func readMulticaTokenFromConfig(fileManager: FileManager) -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".multica/config.json")
        guard let data = fileManager.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        return token
    }
}

/// 🌟 Factory — Studio-default live Multica + optional Linear behind the curtain.
public enum ProjectStateBridgeFactory {
    /// 🚀 Build an `OperatorProjectStateBridge` from env / Multica config.
    public static func makeStudioBridge(
        configuration: ProjectStateBridgeConfiguration = .loadFromEnvironment(),
        session: URLSession = .shared
    ) -> OperatorProjectStateBridge {
        let multica: any MulticaProjectProvider
        if let token = configuration.multicaToken, !token.isEmpty {
            multica = LiveMulticaProjectProvider(configuration: configuration, session: session)
            print("🌐 ✨ LIVE MULTICA PROVIDER WIRED (token present, never logged)")
        } else {
            multica = NullMulticaProjectProvider()
            print("🌙 ⚠️ Gentle reminder: Multica token missing — project.state Multica path unwired")
        }

        let linear: any LinearProjectProvider
        if let key = configuration.linearAPIKey, !key.isEmpty {
            linear = LiveLinearProjectProvider(configuration: configuration, session: session)
            print("🌐 ✨ LIVE LINEAR PROVIDER WIRED (key present, never logged)")
        } else {
            linear = NullLinearProjectProvider()
            print("🌙 ⚠️ Gentle reminder: LINEAR_API_KEY unset — Multica-only fan-out until keyed")
        }

        return OperatorProjectStateBridge(linear: linear, multica: multica)
    }
}

// MARK: - Live Multica

/// 🌟 Habitat HTTP provider for Multica issues — operator-only credentials.
public struct LiveMulticaProjectProvider: MulticaProjectProvider {
    private let configuration: ProjectStateBridgeConfiguration
    private let session: URLSession

    public init(configuration: ProjectStateBridgeConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func fetchIssues() async throws -> [MulticaIssueFragment] {
        guard let token = configuration.multicaToken, !token.isEmpty else {
            throw ProjectStateError.bridgeNotWired
        }
        var components = URLComponents(
            url: configuration.multicaBaseURL.appendingPathComponent("api/issues"),
            resolvingAgainstBaseURL: false
        )!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "workspace_id", value: configuration.multicaWorkspaceID)
        ]
        if let projectID = configuration.multicaProjectID {
            query.append(URLQueryItem(name: "project_id", value: projectID))
        }
        components.queryItems = query
        guard let url = components.url else {
            throw ProjectStateError.providerFailure("Invalid Multica issues URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response: response, data: data, verb: "list")
        let decoded = try JSONDecoder().decode(MulticaIssueListResponse.self, from: data)
        return decoded.issues.map {
            MulticaIssueFragment(id: $0.identifier ?? $0.id, title: $0.title, status: $0.status)
        }
    }

    public func createIssue(title: String, description: String?) async throws -> MulticaIssueFragment {
        guard let token = configuration.multicaToken, !token.isEmpty else {
            throw ProjectStateError.bridgeNotWired
        }
        var components = URLComponents(
            url: configuration.multicaBaseURL.appendingPathComponent("api/issues"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "workspace_id", value: configuration.multicaWorkspaceID)]
        guard let url = components.url else {
            throw ProjectStateError.providerFailure("Invalid Multica create URL")
        }

        var body: [String: Any] = [
            "title": title,
            "status": "todo",
            "workspace_id": configuration.multicaWorkspaceID
        ]
        if let projectID = configuration.multicaProjectID {
            body["project_id"] = projectID
        }
        if let description, !description.isEmpty {
            body["description"] = description
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(response: response, data: data, verb: "create")
        let issue = try JSONDecoder().decode(MulticaIssueDTO.self, from: data)
        print("🎉 ✨ MULTICA CREATE COMPLETE! id=\(issue.identifier ?? issue.id)")
        return MulticaIssueFragment(
            id: issue.identifier ?? issue.id,
            title: issue.title,
            status: issue.status
        )
    }

    public func updateIssue(id: String, title: String?, status: String?) async throws -> MulticaIssueFragment {
        // 🌙 Habitat HTTP returns 405 for PATCH/PUT on /api/issues/:id — CLI is the supported write path.
        guard title != nil || status != nil else {
            throw ProjectStateError.providerFailure("Empty Multica update patch")
        }
        var args = ["issue", "update", id, "--output", "json"]
        if let title { args += ["--title", title] }
        if let status { args += ["--status", status] }
        let data = try await MulticaCLIRunner.run(arguments: args)
        let issue = try JSONDecoder().decode(MulticaIssueDTO.self, from: data)
        print("🎉 ✨ MULTICA UPDATE COMPLETE! id=\(issue.identifier ?? issue.id)")
        return MulticaIssueFragment(
            id: issue.identifier ?? issue.id,
            title: issue.title,
            status: issue.status
        )
    }

    private static func throwIfNeeded(response: URLResponse, data: Data, verb: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProjectStateError.providerFailure("Multica \(verb): non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let clipped = body.prefix(180)
            throw ProjectStateError.providerFailure("Multica \(verb) HTTP \(http.statusCode): \(clipped)")
        }
    }
}

// MARK: - Live Linear

/// 🌟 Linear GraphQL provider — requires `LINEAR_API_KEY`; soft-skips when absent.
public struct LiveLinearProjectProvider: LinearProjectProvider {
    private let configuration: ProjectStateBridgeConfiguration
    private let session: URLSession
    private let endpoint = URL(string: "https://api.linear.app/graphql")!

    public init(configuration: ProjectStateBridgeConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func fetchIssues() async throws -> [LinearIssueFragment] {
        guard let key = configuration.linearAPIKey, !key.isEmpty else {
            throw ProjectStateError.bridgeNotWired
        }

        let filter: [String: Any]
        if let projectID = configuration.linearProjectID, !projectID.isEmpty {
            filter = ["project": ["id": ["eq": projectID]]]
        } else if let teamID = configuration.linearTeamID, !teamID.isEmpty {
            filter = ["team": ["id": ["eq": teamID]]]
        } else {
            filter = [:]
        }

        let query = """
        query ProjectStateIssues($filter: IssueFilter, $first: Int) {
          issues(filter: $filter, first: $first) {
            nodes { identifier title state { name } }
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["filter": filter, "first": 50]
        ]
        let data = try await graphql(key: key, payload: payload)
        let root = try Self.parseGraphQLResponse(data)
        guard let dataNode = root["data"] as? [String: Any],
              let issues = dataNode["issues"] as? [String: Any],
              let nodes = issues["nodes"] as? [[String: Any]]
        else {
            throw ProjectStateError.providerFailure("Linear GraphQL decode failed")
        }
        return nodes.compactMap { node in
            guard let id = node["identifier"] as? String,
                  let title = node["title"] as? String
            else { return nil }
            let state = (node["state"] as? [String: Any])?["name"] as? String ?? "Backlog"
            return LinearIssueFragment(id: id, title: title, state: state)
        }
    }

    public func createIssue(title: String, description: String?) async throws -> LinearIssueFragment {
        guard let key = configuration.linearAPIKey, !key.isEmpty else {
            throw ProjectStateError.bridgeNotWired
        }
        guard let teamID = configuration.linearTeamID, !teamID.isEmpty else {
            throw ProjectStateError.providerFailure("LINEAR_TEAM_ID required for create")
        }

        var input: [String: Any] = [
            "teamId": teamID,
            "title": title
        ]
        if let description, !description.isEmpty {
            input["description"] = description
        }
        if let projectID = configuration.linearProjectID, !projectID.isEmpty {
            input["projectId"] = projectID
        }

        let mutation = """
        mutation ProjectStateCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { identifier title state { name } }
          }
        }
        """
        let payload: [String: Any] = [
            "query": mutation,
            "variables": ["input": input]
        ]
        let data = try await graphql(key: key, payload: payload)
        let fragment = try Self.mutationFragment(data, container: "issueCreate")
        print("🎉 ✨ LINEAR CREATE COMPLETE! id=\(fragment.id)")
        return fragment
    }

    public func updateIssue(id: String, title: String?, state: String?) async throws -> LinearIssueFragment {
        guard let key = configuration.linearAPIKey, !key.isEmpty else {
            throw ProjectStateError.bridgeNotWired
        }
        // 🔮 Resolve BIN-* → UUID via filter, then issueUpdate
        let uuid = try await resolveIssueUUID(identifier: id, key: key)
        var input: [String: Any] = [:]
        if let title { input["title"] = title }
        if let state {
            // Linear wants stateId for transitions — map common names via workflowStates when possible.
            // Soft path: only title updates when state mapping unavailable; status via state name lookup.
            if let stateId = try await resolveStateID(named: state, key: key) {
                input["stateId"] = stateId
            }
        }
        guard !input.isEmpty else {
            throw ProjectStateError.providerFailure("Empty Linear update patch")
        }

        let mutation = """
        mutation ProjectStateUpdate($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) {
            success
            issue { identifier title state { name } }
          }
        }
        """
        let payload: [String: Any] = [
            "query": mutation,
            "variables": ["id": uuid, "input": input]
        ]
        let data = try await graphql(key: key, payload: payload)
        let fragment = try Self.mutationFragment(data, container: "issueUpdate")
        print("🎉 ✨ LINEAR UPDATE COMPLETE! id=\(fragment.id)")
        return fragment
    }

    private func resolveIssueUUID(identifier: String, key: String) async throws -> String {
        if UUID(uuidString: identifier) != nil { return identifier }
        let query = """
        query ResolveIssue($filter: IssueFilter) {
          issues(filter: $filter, first: 1) {
            nodes { id identifier }
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["filter": ["number": ["eq": Self.issueNumber(from: identifier)].compactMapValues { $0 }]]
        ]
        // Prefer identifier filter when available
        let payloadByIdent: [String: Any] = [
            "query": """
            query ResolveByIdent($id: String!) {
              issue(id: $id) { id identifier }
            }
            """,
            "variables": ["id": identifier]
        ]
        // Linear accepts identifier like BIN-39 in issue(id:)
        if let data = try? await graphql(key: key, payload: payloadByIdent),
           let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataNode = root["data"] as? [String: Any],
           let issue = dataNode["issue"] as? [String: Any],
           let uuid = issue["id"] as? String
        {
            return uuid
        }
        _ = payload
        throw ProjectStateError.providerFailure("Linear issue not found: \(identifier)")
    }

    private func resolveStateID(named name: String, key: String) async throws -> String? {
        guard let teamID = configuration.linearTeamID else { return nil }
        let query = """
        query TeamStates($teamId: String!) {
          team(id: $teamId) {
            states { nodes { id name type } }
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": ["teamId": teamID]
        ]
        let data = try await graphql(key: key, payload: payload)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = root["data"] as? [String: Any],
              let team = dataNode["team"] as? [String: Any],
              let states = team["states"] as? [String: Any],
              let nodes = states["nodes"] as? [[String: Any]]
        else {
            return nil
        }
        let needle = name.lowercased()
        if let exact = nodes.first(where: { ($0["name"] as? String)?.lowercased() == needle }) {
            return exact["id"] as? String
        }
        // Map client ProjectStateStatus vocabulary → Linear types
        let typeMap: [String: String] = [
            "backlog": "backlog",
            "todo": "unstarted",
            "active": "started",
            "in progress": "started",
            "blocked": "started",
            "done": "completed",
            "completed": "completed",
            "canceled": "canceled",
            "cancelled": "canceled"
        ]
        if let type = typeMap[needle],
           let match = nodes.first(where: { ($0["type"] as? String)?.lowercased() == type })
        {
            return match["id"] as? String
        }
        return nil
    }

    private static func issueNumber(from identifier: String) -> Int? {
        let parts = identifier.split(separator: "-")
        guard let last = parts.last else { return nil }
        return Int(last)
    }

    /// 🌩️ Parse GraphQL JSON and surface Linear errors before attempting success-path decode.
    private static func parseGraphQLResponse(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectStateError.providerFailure("Linear response is not JSON")
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            let detail = messages.isEmpty ? "unknown GraphQL error" : messages.joined(separator: "; ")
            throw ProjectStateError.providerFailure("Linear GraphQL error: \(detail)")
        }
        return root
    }

    /// 🌩️ Mutations: a partial response (data + errors) with the written issue is a
    /// success — the write landed. Only surface GraphQL errors when no issue was written.
    static func mutationFragment(_ data: Data, container: String) throws -> LinearIssueFragment {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let written = (root["data"] as? [String: Any])?[container] as? [String: Any],
           let issue = written["issue"] as? [String: Any],
           let id = issue["identifier"] as? String,
           let title = issue["title"] as? String
        {
            let state = (issue["state"] as? [String: Any])?["name"] as? String ?? "Backlog"
            return LinearIssueFragment(id: id, title: title, state: state)
        }
        _ = try Self.parseGraphQLResponse(data)  // throws with the real GraphQL messages when errors are present
        throw ProjectStateError.providerFailure("Linear \(container) decode failed")
    }

    private func graphql(key: String, payload: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ProjectStateError.providerFailure("Linear HTTP \(code)")
        }
        return data
    }
}

// MARK: - Multica CLI runner (update path)

/// 🛠️ Shell out to `multica` for Habitat writes HTTP refuses (405 on PATCH).
enum MulticaCLIRunner {
    static func run(arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Exhibit 3: ConcurrentProcess drains both pipes before
                // waiting on exit — the old wait-then-read shape deadlocked
                // on any output past the pipe buffer.
                do {
                    let output = try ConcurrentProcess.run(
                        executable: "/opt/homebrew/bin/multica",
                        arguments: arguments
                    )
                    guard output.status == 0 else {
                        let err = String(data: output.stderr, encoding: .utf8) ?? ""
                        continuation.resume(
                            throwing: ProjectStateError.providerFailure(
                                "multica \(arguments.prefix(3).joined(separator: " ")) failed: \(err.prefix(160))"
                            )
                        )
                        return
                    }
                    continuation.resume(returning: output.stdout)
                } catch {
                    continuation.resume(
                        throwing: ProjectStateError.providerFailure(error.localizedDescription)
                    )
                }
            }
        }
    }
}

// MARK: - Multica DTOs (private)

private struct MulticaIssueListResponse: Decodable {
    let issues: [MulticaIssueDTO]
}

private struct MulticaIssueDTO: Decodable {
    let id: String
    let identifier: String?
    let title: String
    let status: String
}
