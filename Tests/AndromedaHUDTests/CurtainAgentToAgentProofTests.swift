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
}
