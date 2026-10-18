import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Leg seams (HAB-602 / HAB-600)

/// Stable proof-leg identifiers recorded in `memory-chain.json` (ADR-0020).
public enum MemoryChainProofLegID: String, Sendable, CaseIterable, Equatable {
    /// Agent A `memory_retain` / store → Agent B `memory_recall` (HAB-600 / HAB-602).
    case agentToAgent = "agent-to-agent"
    /// Git-backed Letta ingress counted in-context (HAB-602 Letta lane).
    case lettaIngress = "letta-ingress"
    /// Ladybug hub index health + query path (HAB-602 Ladybug leg).
    case ladybugIndex = "ladybug-index"
}

/// Curtain / MCP surface that can prove agent-to-agent retain → recall.
public protocol AgentToAgentMemoryProving: Sendable {
    /// Persist a narrative attributed to `writerAgent`. Returns the durable memory id.
    func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID
    /// Recall as `readerAgent`. Returns true when `memoryID` appears in hits.
    ///
    /// Implementations MUST authorize `readerAgent` against the surface's
    /// `AgentMemoryReadPolicy` (PR #91 review P2-2) — the reader identity is a
    /// typed allow/deny input, never a discardable parameter.
    func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool
}

/// Who may read a memory retained through the proof surface (PR #91 review
/// P2-2): the agent-to-agent leg is *deliberately* shared — the cross-agent
/// read is an asserted policy, not an oversight.
public enum AgentMemoryReadPolicy: String, Sendable, Equatable, CaseIterable {
    /// Narrative is retained `visibility: "shared"`; any agent may read it.
    /// This is the proof-leg default: the whole point of the leg is that a
    /// *different* agent can recall what the writer retained.
    case sharedAcrossAgents
    /// Narrative is retained `visibility: "private"`; only the writer may
    /// read it. Cross-agent recall returns false (deny), not a silent hit.
    case writerOnly

    /// Visibility the surface must stamp on retains under this policy.
    public var retentionVisibility: String {
        switch self {
        case .sharedAcrossAgents: "shared"
        case .writerOnly: "private"
        }
    }

    /// Typed allow/deny for one (reader, writer) pair.
    public func authorizes(reader: String, writer: String) -> Bool {
        switch self {
        case .sharedAcrossAgents:
            true
        case .writerOnly:
            reader == writer
        }
    }
}

/// Optional Ladybug chain probe (health now; upsert/query may stay pending).
public protocol LadybugIndexProving: Sendable {
    /// Attempt the Ladybug proof leg. Honest `pending` when the hub is unreachable.
    func prove(now: Date) async -> MemoryChainProofLeg
}

// MARK: - Runner

/// Writes ADR-0020 proof state after running memory-chain legs (HAB-602 lane).
///
/// The HUD only *reads* `MemoryChainProofStore`; this runner is the write owner.
public enum MemoryChainProofRunner: Sendable {
    /// Distinctive nonce so concurrent proof runs do not collide on recall.
    public static func makeNonce(now: Date = Date()) -> String {
        let stamp = Int(now.timeIntervalSince1970)
        return "hab602-\(stamp)-\(UUID().uuidString.prefix(8))"
    }

    /// Run the agent-to-agent leg and merge into the proof document at `path`.
    ///
    /// Acceptance (HAB-602 § Proof / HAB-600): writer retains a unique narrative;
    /// a different reader agent recalls it by content. Pass only when the hit
    /// is found — otherwise `fail` (attempted) rather than silent pending.
    ///
    /// Cancellation (PR #91 review P2-3): a cancelled run rethrows
    /// `CancellationError` without recording a fail leg and without touching
    /// the proof document — cancellation is not a proof result.
    ///
    /// Idempotency (PR #91 review P2-3): pass a durable `runKey` to make
    /// retries safe. When the leg already recorded a pass under the same key,
    /// the run short-circuits (no second durable retain); the narrative token
    /// is derived from the key, so retains from retried attempts of one run
    /// are identical and traceable. Without a key each invocation is a fresh
    /// attempt (documented, not idempotent).
    public static func runAgentToAgent(
        surface: any AgentToAgentMemoryProving,
        path: String = MemoryChainProofStore.defaultPath,
        project: String = "andromeda",
        writerAgent: String = "agent-a",
        readerAgent: String = "agent-b",
        now: Date = Date(),
        nonce: String? = nil,
        runKey: String? = nil
    ) async throws -> MemoryChainProofState {
        // Idempotent replay: a pass recorded under this run key is already
        // proven — do not create another durable retain for it.
        if let runKey,
           let prior = try alreadyPassedLegState(id: MemoryChainProofLegID.agentToAgent.rawValue,
                                                 runKey: runKey, path: path) {
            return prior
        }

        // Deterministic token for keyed runs: retries re-emit the same
        // narrative (same outbox content hash) so duplicates are contained
        // and deducible downstream.
        let token = nonce ?? runKey ?? makeNonce(now: now)
        let narrative =
            "HAB-602 agent-to-agent proof token \(token) — curtain verbs across agents"
        let query = "HAB-602 agent-to-agent proof token \(token)"

        try Task.checkCancellation()

        let leg: MemoryChainProofLeg
        do {
            let memoryID = try await surface.retain(
                narrative: narrative,
                project: project,
                writerAgent: writerAgent
            )
            let found = await surface.recallContains(
                query: query,
                memoryID: memoryID,
                readerAgent: readerAgent
            )
            // State mutation happens after this point — a cancel that raced
            // the leg must not be recorded as a proof result.
            try Task.checkCancellation()
            if found {
                leg = MemoryChainProofLeg(
                    id: MemoryChainProofLegID.agentToAgent.rawValue,
                    status: .pass,
                    at: now,
                    detail:
                        "\(writerAgent) retain → \(readerAgent) recall hit \(memoryID.uuidString) (\(token))",
                    runKey: runKey
                )
            } else {
                leg = MemoryChainProofLeg(
                    id: MemoryChainProofLegID.agentToAgent.rawValue,
                    status: .fail,
                    at: now,
                    detail:
                        "\(readerAgent) recall missed memory \(memoryID.uuidString) for token \(token)",
                    runKey: runKey
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            leg = MemoryChainProofLeg(
                id: MemoryChainProofLegID.agentToAgent.rawValue,
                status: .fail,
                at: now,
                detail: "retain failed: \(error.localizedDescription)",
                runKey: runKey
            )
        }

        return try mergeAndSave(leg: leg, path: path, now: now)
    }

    /// Runs the Ladybug index leg (honest pending when unreachable).
    ///
    /// Cancellation propagates: a cancelled caller gets `CancellationError`
    /// and the proof document is left untouched (PR #91 review P2-3).
    public static func runLadybugIndex(
        probe: any LadybugIndexProving,
        path: String = MemoryChainProofStore.defaultPath,
        now: Date = Date()
    ) async throws -> MemoryChainProofState {
        let leg = await probe.prove(now: now)
        try Task.checkCancellation()
        return try mergeAndSave(leg: leg, path: path, now: now)
    }

    /// Merge one leg into existing proof state (preserving other legs) and save.
    ///
    /// The whole read-merge-write is a cross-process transaction (PR #91
    /// review P1-1): an exclusive `flock` on `<path>.lock` serializes
    /// concurrent legs — whether from parallel Tasks in this process or a
    /// simultaneously running `andromeda memory-chain prove` — so neither
    /// merge can be lost. The save itself publishes via atomic rename.
    public static func mergeAndSave(
        leg: MemoryChainProofLeg,
        path: String,
        now: Date = Date()
    ) throws -> MemoryChainProofState {
        // The lock file must only ever be created inside the ADR-0020 sandbox;
        // for paths outside it, fall through and let save() throw the honest
        // sandbox refusal rather than creating files elsewhere.
        if MemoryChainProofStore.isInsideSandbox(path) {
            let expanded = (path as NSString).expandingTildeInPath
            let lock = try CrossProcessFileLock.acquire(lockFilePath: expanded + ".lock")
            defer { lock.release() }
            return try mergeAndSaveUnlocked(leg: leg, path: path, now: now)
        }
        return try mergeAndSaveUnlocked(leg: leg, path: path, now: now)
    }

    /// The merge body — caller must already hold the transaction lock (or be
    /// intentionally outside the sandbox, where save refuses the write).
    private static func mergeAndSaveUnlocked(
        leg: MemoryChainProofLeg,
        path: String,
        now: Date
    ) throws -> MemoryChainProofState {
        let prior = try MemoryChainProofStore.load(from: path)
        var byID: [String: MemoryChainProofLeg] = [:]
        for existing in prior?.legs ?? [] {
            byID[existing.id] = existing
        }
        byID[leg.id] = leg
        // Stable order: known ids first, then any extras alphabetically.
        let known = MemoryChainProofLegID.allCases.map(\.rawValue)
        var ordered: [MemoryChainProofLeg] = []
        for id in known {
            if let row = byID.removeValue(forKey: id) {
                ordered.append(row)
            }
        }
        for id in byID.keys.sorted() {
            if let row = byID[id] { ordered.append(row) }
        }
        let state = MemoryChainProofState(
            version: MemoryChainProofStore.version,
            lastRun: now,
            legs: ordered
        )
        try MemoryChainProofStore.save(state, to: path)
        return state
    }

    /// Returns the prior state when leg `id` already recorded a pass under
    /// `runKey` — the idempotent-replay short-circuit for keyed runs.
    private static func alreadyPassedLegState(
        id: String,
        runKey: String,
        path: String
    ) throws -> MemoryChainProofState? {
        guard let prior = try MemoryChainProofStore.load(from: path) else { return nil }
        guard let leg = prior.legs.first(where: { $0.id == id }) else { return nil }
        guard leg.status == .pass, leg.runKey == runKey else { return nil }
        return prior
    }
}

// MARK: - Ladybug HTTP health probe

/// Injectable GET status probe — tests mock without touching the network.
public protocol HTTPStatusProbing: Sendable {
    /// Returns the HTTP status code for `url`, or throws on transport failure.
    func statusCode(for url: URL, timeout: TimeInterval) async throws -> Int
}

/// Live GET via `URLSession` (FoundationNetworking on Linux).
public struct URLSessionHTTPStatusProbe: HTTPStatusProbing {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func statusCode(for url: URL, timeout: TimeInterval) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return http.statusCode
    }
}

/// Probes Ladybug `:8286/health`. HTTP 200 → pending (health only, not full chain);
/// unreachable → pending (leg started, not proven). Non-200 → fail.
public struct LadybugHTTPHealthProbe: LadybugIndexProving, Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval
    private let http: any HTTPStatusProbing

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8286")!,
        timeout: TimeInterval = 2,
        http: any HTTPStatusProbing = URLSessionHTTPStatusProbe()
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.http = http
    }

    public func prove(now: Date) async -> MemoryChainProofLeg {
        let healthURL = baseURL.appendingPathComponent("health")
        do {
            let status = try await http.statusCode(for: healthURL, timeout: timeout)
            if status == 200 {
                // Health alone is not full-chain proof (upsert/query still TBD on
                // the Python serve surface). Record honest pending with evidence.
                return MemoryChainProofLeg(
                    id: MemoryChainProofLegID.ladybugIndex.rawValue,
                    status: .pending,
                    at: now,
                    detail:
                        "health HTTP 200 at \(healthURL.absoluteString); upsert/query chain not yet proven"
                )
            }
            return MemoryChainProofLeg(
                id: MemoryChainProofLegID.ladybugIndex.rawValue,
                status: .fail,
                at: now,
                detail: "health HTTP \(status) at \(healthURL.absoluteString)"
            )
        } catch {
            return MemoryChainProofLeg(
                id: MemoryChainProofLegID.ladybugIndex.rawValue,
                status: .pending,
                at: now,
                detail: "ladybug unreachable (\(error.localizedDescription)); leg started, not proven"
            )
        }
    }
}

/// Test / fixture probe that returns a fixed Ladybug leg.
public struct FixedLadybugProbe: LadybugIndexProving, Sendable {
    public let leg: MemoryChainProofLeg
    public init(leg: MemoryChainProofLeg) { self.leg = leg }
    public func prove(now: Date) async -> MemoryChainProofLeg { leg }
}

/// Fixed status-code HTTP probe for tests.
public struct FixedHTTPStatusProbe: HTTPStatusProbing, Sendable {
    public let code: Int
    public let error: (any Error)?

    public init(code: Int) {
        self.code = code
        self.error = nil
    }

    public init(error: any Error) {
        self.code = -1
        self.error = error
    }

    public func statusCode(for url: URL, timeout: TimeInterval) async throws -> Int {
        _ = url
        _ = timeout
        if let error { throw error }
        return code
    }
}
