import AndromedaMCPHub
import ArgumentParser
import Foundation
import MemoryKit

#if canImport(OSLog)
    import os
#endif

/// HAB-600 / HAB-602 — run ADR-0020 memory-chain proof legs from the CLI.
///
/// Studio dogfood: `andromeda memory-chain prove` writes
/// `~/.andromeda/proofs/memory-chain.json` so HUD `memory_health` can census.
struct MemoryChainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory-chain",
        abstract: "Memory-chain proof legs (HAB-600 / HAB-602) — write ADR-0020 census.",
        subcommands: [Prove.self, Status.self],
        defaultSubcommand: Status.self
    )

    static let diagnostics = os.Logger(subsystem: "ai.andromeda.memory-chain", category: "cli")

    // MARK: - Status (read-only)

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show current memory-chain.json proof census (read-only)."
        )

        @Option(name: .long, help: "Proof document path (default ~/.andromeda/proofs/memory-chain.json).")
        var path: String = MemoryChainProofStore.defaultPath

        func run() async throws {
            let expanded = (path as NSString).expandingTildeInPath
            guard let state = try MemoryChainProofStore.load(from: path) else {
                print("memory-chain: proof not recorded at \(expanded)")
                print("  run: andromeda memory-chain prove")
                return
            }
            print("memory-chain: version \(state.version)  lastRun=\(state.lastRun?.description ?? "nil")")
            for leg in state.legs {
                let when = leg.at.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
                print("  \(leg.status.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))  \(leg.id)  @ \(when)")
                if !leg.detail.isEmpty {
                    print("           \(leg.detail)")
                }
            }
        }
    }

    // MARK: - Prove

    struct Prove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run proof legs and merge into memory-chain.json (write owner)."
        )

        @Option(name: .long, help: "Proof document path (default ~/.andromeda/proofs/memory-chain.json).")
        var path: String = MemoryChainProofStore.defaultPath

        @Flag(name: .long, help: "Also probe Ladybug :8286/health (honest pending until upsert/query).")
        var ladybug: Bool = false

        @Flag(name: .long, help: "Skip agent-to-agent curtain retain→recall leg.")
        var skipAgentToAgent: Bool = false

        @Option(name: .long, help: "Writer agent id for retain attribution.")
        var writer: String = "agent-a"

        @Option(name: .long, help: "Reader agent id for recall narrative.")
        var reader: String = "agent-b"

        func run() async throws {
            if !skipAgentToAgent {
                MemoryChainCommand.diagnostics.info("🩺 running agent-to-agent curtain proof")
                let surface = try await CLICurtainAgentSurface.makeEphemeral()
                let state = try await MemoryChainProofRunner.runAgentToAgent(
                    surface: surface,
                    path: path,
                    writerAgent: writer,
                    readerAgent: reader
                )
                Self.printLeg(state, id: MemoryChainProofLegID.agentToAgent.rawValue)
            }

            if ladybug {
                MemoryChainCommand.diagnostics.info("🐞 probing ladybug-index health")
                let state = try await MemoryChainProofRunner.runLadybugIndex(
                    probe: LadybugHTTPHealthProbe(),
                    path: path
                )
                Self.printLeg(state, id: MemoryChainProofLegID.ladybugIndex.rawValue)
            }

            if skipAgentToAgent, !ladybug {
                throw ValidationError("nothing to prove — omit --skip-agent-to-agent or pass --ladybug")
            }

            print("memory-chain: wrote \(path)")
            print("  HUD memory_health will census on next read (no UI change needed).")
        }

        private static func printLeg(_ state: MemoryChainProofState, id: String) {
            guard let leg = state.legs.first(where: { $0.id == id }) else { return }
            print("  \(leg.status.rawValue)  \(leg.id) — \(leg.detail)")
        }
    }
}

/// CLI-local curtain adapter (same contract as HUDCore `CurtainAgentToAgentSurface`).
private struct CLICurtainAgentSurface: AgentToAgentMemoryProving, Sendable {
    private let curtain: MemoryComplexityCurtain

    init(curtain: MemoryComplexityCurtain) {
        self.curtain = curtain
    }

    static func makeEphemeral() async throws -> CLICurtainAgentSurface {
        CLICurtainAgentSurface(curtain: try await MemoryComplexityCurtain.makeEphemeral())
    }

    func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID {
        let receipt = try await curtain.retain(
            narrative: narrative,
            project: project,
            agent: writerAgent,
            provenance: MemoryVerb.retain.rawValue
        )
        return receipt.memoryID
    }

    func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool {
        _ = readerAgent
        let response = await curtain.recall(query: query)
        return response.hits.contains(where: { $0.id == memoryID })
    }
}
