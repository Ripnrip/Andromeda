import Foundation
import Testing
import MemoryKit
import AndromedaMCPHub
@testable import AndromedaHUDCore

@Suite("CurtainAgentToAgentSurface × MemoryChainProofRunner")
struct CurtainAgentToAgentProofTests {
    /// End-to-end: real curtain retain/recall drives the ADR-0020 agent-to-agent leg (HAB-600/602).
    @Test("curtain agent-a retain is recalled by agent-b and written as pass")
    func curtainRoundTripWritesPass() async throws {
        try FileManager.default.createDirectory(
            at: MemoryChainProofStore.sandboxDirectory,
            withIntermediateDirectories: true
        )
        let path = MemoryChainProofStore.sandboxDirectory
            .appendingPathComponent("curtain-a2a-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let surface = try await CurtainAgentToAgentSurface.makeEphemeral()
        let state = try await MemoryChainProofRunner.runAgentToAgent(
            surface: surface,
            path: path,
            writerAgent: "agent-a",
            readerAgent: "agent-b",
            nonce: "curtain-e2e-nonce"
        )

        let leg = state.legs.first { $0.id == MemoryChainProofLegID.agentToAgent.rawValue }
        #expect(leg?.status == .pass)
        #expect(leg?.detail.contains("agent-a") == true)
        #expect(leg?.detail.contains("agent-b") == true)
        #expect(leg?.detail.contains("curtain-e2e-nonce") == true)

        let loaded = try MemoryChainProofStore.load(from: path)
        #expect(loaded?.legs.first?.status == .pass)
    }

    /// PR #91 review P2-2 — reader identity is authorized, not discarded.
    /// Default shared policy: a *different* agent may recall the proof
    /// narrative (that cross-agent recall is the leg being proven).
    @Test("shared policy: cross-agent reader is allowed, writer reader allowed")
    func sharedPolicyAllowsCrossAgentReader() async throws {
        let surface = try await CurtainAgentToAgentSurface.makeEphemeral()
        let query = "policy-shared-nonce cross-agent recall"
        let id = try await surface.retain(
            narrative: "policy-shared-nonce cross-agent recall narrative",
            project: "andromeda",
            writerAgent: "agent-a"
        )
        #expect(await surface.recallContains(query: query, memoryID: id, readerAgent: "agent-b") == true)
        #expect(await surface.recallContains(query: query, memoryID: id, readerAgent: "agent-a") == true)
        // Unknown memory (never retained through this surface) is denied.
        #expect(await surface.recallContains(query: query, memoryID: UUID(), readerAgent: "agent-b") == false)
    }

    /// PR #91 review P2-2 — writerOnly policy: only the writer may read;
    /// a different agent is denied even though the content matches.
    @Test("writerOnly policy: cross-agent reader is denied")
    func writerOnlyPolicyDeniesCrossAgentReader() async throws {
        let surface = try await CurtainAgentToAgentSurface.makeEphemeral(policy: .writerOnly)
        let query = "policy-private-nonce recall"
        let id = try await surface.retain(
            narrative: "policy-private-nonce recall narrative",
            project: "andromeda",
            writerAgent: "agent-a"
        )
        #expect(await surface.recallContains(query: query, memoryID: id, readerAgent: "agent-b") == false)
        #expect(await surface.recallContains(query: query, memoryID: id, readerAgent: "agent-a") == true)
    }
}
