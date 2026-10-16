import Foundation
import MemoryKit
import AndromedaMCPHub

/// Remembers which agent retained each memory id, so reads can be authorized
/// against the surface's `AgentMemoryReadPolicy` (PR #91 review P2-2).
actor MemoryWriterAttribution {
    private var writers: [UUID: String] = [:]

    func record(memoryID: UUID, writer: String) {
        writers[memoryID] = writer
    }

    func writer(for memoryID: UUID) -> String? {
        writers[memoryID]
    }
}

/// Adapts `MemoryComplexityCurtain` to the HAB-602 agent-to-agent proof seam.
///
/// Reader identity is a typed allow/deny input, never discarded (PR #91 review
/// P2-2): under the default `.sharedAcrossAgents` policy the proof narrative is
/// retained deliberately `visibility: "shared"` and any agent — including a
/// different one — may recall it (that cross-agent recall IS the leg being
/// proven). Under `.writerOnly` the narrative is retained `private` and a
/// reader other than the writer is denied (recall returns false).
public struct CurtainAgentToAgentSurface: AgentToAgentMemoryProving, Sendable {
    private let curtain: MemoryComplexityCurtain
    private let policy: AgentMemoryReadPolicy
    private let attribution = MemoryWriterAttribution()

    public init(
        curtain: MemoryComplexityCurtain,
        policy: AgentMemoryReadPolicy = .sharedAcrossAgents
    ) {
        self.curtain = curtain
        self.policy = policy
    }

    /// Ephemeral curtain for hermetic proof runs / CI.
    public static func makeEphemeral(
        policy: AgentMemoryReadPolicy = .sharedAcrossAgents
    ) async throws -> CurtainAgentToAgentSurface {
        CurtainAgentToAgentSurface(
            curtain: try await MemoryComplexityCurtain.makeEphemeral(),
            policy: policy
        )
    }

    public func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID {
        let receipt = try await curtain.retain(
            narrative: narrative,
            project: project,
            agent: writerAgent,
            provenance: MemoryVerb.retain.rawValue,
            // Asserted read policy (PR #91 P2-2): the visibility stamped at
            // retain is what authorizes (or denies) cross-agent recall later.
            visibility: policy.retentionVisibility,
            tags: ["memory-chain-proof"]
        )
        await attribution.record(memoryID: receipt.memoryID, writer: writerAgent)
        return receipt.memoryID
    }

    public func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool {
        // Deny by default for memories this surface never retained: an
        // unauthorized read must not fall through to a bare content match.
        guard let writer = await attribution.writer(for: memoryID) else { return false }
        guard policy.authorizes(reader: readerAgent, writer: writer) else { return false }
        let response = await curtain.recall(query: query)
        return response.hits.contains(where: { $0.id == memoryID })
    }
}
