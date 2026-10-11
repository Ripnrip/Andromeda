import Foundation
import Testing
@testable import AndromedaMCPHub

/// In-memory stub for hermetic agent-to-agent proof tests (no MemoryKit).
private actor StubAgentMemory: AgentToAgentMemoryProving {
    private var rows: [(id: UUID, narrative: String, agent: String)] = []
    var retainShouldThrow = false
    var forceMiss = false

    func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID {
        _ = project
        if retainShouldThrow {
            throw StubError.retainBoom
        }
        let id = UUID()
        rows.append((id, narrative, writerAgent))
        return id
    }

    func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool {
        _ = readerAgent
        if forceMiss { return false }
        return rows.contains { row in
            row.id == memoryID && row.narrative.localizedCaseInsensitiveContains(query)
        }
    }

    enum StubError: Error, LocalizedError {
        case retainBoom
        var errorDescription: String? { "stub retain boom" }
    }
}

@Suite("MemoryChainProofRunner")
struct MemoryChainProofRunnerTests {
    /// Proof writes must land inside the ADR-0020 sandbox.
    private func sandboxPath(_ name: String) -> String {
        MemoryChainProofStore.sandboxDirectory
            .appendingPathComponent("runner-\(name)-\(UUID().uuidString).json").path
    }

    private func ensureSandbox() throws {
        try FileManager.default.createDirectory(
            at: MemoryChainProofStore.sandboxDirectory,
            withIntermediateDirectories: true
        )
    }

    @Test("agent-to-agent pass writes leg and preserves prior legs")
    func agentToAgentPassMerges() async throws {
        try ensureSandbox()
        let path = sandboxPath("pass")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Prior Letta leg from HAB-602 Studio proof — must survive merge.
        try MemoryChainProofStore.save(
            MemoryChainProofState(
                lastRun: Date(timeIntervalSince1970: 1),
                legs: [
                    MemoryChainProofLeg(
                        id: MemoryChainProofLegID.lettaIngress.rawValue,
                        status: .pass,
                        at: Date(timeIntervalSince1970: 1),
                        detail: "prior letta-ingress"
                    )
                ]
            ),
            to: path
        )

        let stub = StubAgentMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub,
            path: path,
            now: now,
            nonce: "fixed-nonce"
        )

        #expect(state.legs.count == 2)
        let agentLeg = state.legs.first { $0.id == MemoryChainProofLegID.agentToAgent.rawValue }
        let lettaLeg = state.legs.first { $0.id == MemoryChainProofLegID.lettaIngress.rawValue }
        #expect(agentLeg?.status == .pass)
        #expect(agentLeg?.detail.contains("fixed-nonce") == true)
        #expect(lettaLeg?.status == .pass)
        #expect(lettaLeg?.detail == "prior letta-ingress")
        #expect(state.lastRun == now)

        let reloaded = try MemoryChainProofStore.load(from: path)
        #expect(reloaded?.legs.count == 2)
    }

    @Test("agent-to-agent miss records fail not pending")
    func agentToAgentMissFails() async throws {
        try ensureSandbox()
        let path = sandboxPath("miss")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setForceMiss(true)
        let state = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub,
            path: path,
            nonce: "miss-nonce"
        )
        #expect(state.legs.first?.status == .fail)
        #expect(state.legs.first?.detail.contains("missed") == true)
    }

    @Test("retain errors record fail")
    func retainErrorFails() async throws {
        try ensureSandbox()
        let path = sandboxPath("err")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setRetainShouldThrow(true)
        let state = try await MemoryChainProofRunner.runAgentToAgent(surface: stub, path: path)
        #expect(state.legs.first?.status == .fail)
        #expect(state.legs.first?.detail.contains("retain failed") == true)
    }

    @Test("ladybug probe merges ladybug-index leg")
    func ladybugLegMerges() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let now = Date(timeIntervalSince1970: 42)
        let probe = FixedLadybugProbe(
            leg: MemoryChainProofLeg(
                id: MemoryChainProofLegID.ladybugIndex.rawValue,
                status: .pending,
                at: now,
                detail: "health ok; upsert pending"
            )
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path, now: now)
        #expect(state.legs.count == 1)
        #expect(state.legs[0].id == MemoryChainProofLegID.ladybugIndex.rawValue)
        #expect(state.legs[0].status == .pending)
    }

    @Test("unreachable ladybug health is honest pending")
    func ladybugUnreachablePending() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug-down")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let probe = LadybugHTTPHealthProbe(
            baseURL: URL(string: "http://127.0.0.1:8286")!,
            http: FixedHTTPStatusProbe(error: URLError(.cannotConnectToHost))
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path)
        let leg = state.legs.first { $0.id == MemoryChainProofLegID.ladybugIndex.rawValue }
        #expect(leg?.status == .pending)
        #expect(leg?.detail.contains("unreachable") == true)
    }

    @Test("ladybug health 200 stays pending until upsert/query proven")
    func ladybugHealthyStillPending() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug-200")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let probe = LadybugHTTPHealthProbe(
            http: FixedHTTPStatusProbe(code: 200)
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path)
        let leg = state.legs.first { $0.id == MemoryChainProofLegID.ladybugIndex.rawValue }
        #expect(leg?.status == .pending)
        #expect(leg?.detail.contains("upsert/query") == true)
    }
}

extension StubAgentMemory {
    func setForceMiss(_ value: Bool) { forceMiss = value }
    func setRetainShouldThrow(_ value: Bool) { retainShouldThrow = value }
}
