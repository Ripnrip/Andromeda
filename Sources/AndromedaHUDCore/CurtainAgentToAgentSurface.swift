import Foundation
import MemoryKit
import AndromedaMCPHub

/// Adapts `MemoryComplexityCurtain` to the HAB-602 agent-to-agent proof seam.
///
/// Retain is attributed per writer agent; recall is shared behind the curtain
/// (clients never pick store brands). A pass means agent B can recall what
/// agent A retained — the canonical verbs lock for HAB-600 / HAB-602.
public struct CurtainAgentToAgentSurface: AgentToAgentMemoryProving, Sendable {
    private let curtain: MemoryComplexityCurtain

    public init(curtain: MemoryComplexityCurtain) {
        self.curtain = curtain
    }

    /// Ephemeral curtain for hermetic proof runs / CI.
    public static func makeEphemeral() async throws -> CurtainAgentToAgentSurface {
        CurtainAgentToAgentSurface(curtain: try await MemoryComplexityCurtain.makeEphemeral())
    }

    public func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID {
        let receipt = try await curtain.retain(
            narrative: narrative,
            project: project,
            agent: writerAgent,
            provenance: MemoryVerb.retain.rawValue
        )
        return receipt.memoryID
    }

    public func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool {
        // readerAgent is part of the proof narrative (who recalled); the curtain
        // surface is shared — attribution lives on the retain side today.
        _ = readerAgent
        let response = await curtain.recall(query: query)
        return response.hits.contains(where: { $0.id == memoryID })
    }
}
