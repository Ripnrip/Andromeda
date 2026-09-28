/**
 * Tests for the MCP orphan reaper classifier — chain walks, ownership,
 * and dry-run refusal to signal anything.
 */

import Testing
@testable import MemoryKit

@Suite("MCPOrphanReaper — classify the sprawl, sparing the owned")
struct MCPOrphanReaperTests {

    let reaper = MCPOrphanReaper()

    // MARK: - Fixtures (shaped like the 2026-09-27 claude-mem epidemic)

    /// chroma python child whose uvx wrapper was reparented to launchd.
    private func orphanedPythonChild() -> MCPProcessParentSnapshot {
        MCPProcessParentSnapshot(
            pid: 9001,
            parentPID: 9000,
            command: "/Users/x/.cache/uv/archive-v0/AAA/bin/python /Users/x/.cache/uv/archive-v0/AAA/bin/chroma-mcp --client-type persistent",
            memoryMB: 300
        )
    }

    private func orphanedUvxWrapper() -> MCPProcessParentSnapshot {
        MCPProcessParentSnapshot(
            pid: 9000,
            parentPID: 1,
            command: "/opt/homebrew/bin/uv tool uvx --python 3.13 --from chroma-mcp==0.2.6 chroma-mcp",
            memoryMB: 5
        )
    }

    private func ownedPythonChild() -> MCPProcessParentSnapshot {
        MCPProcessParentSnapshot(
            pid: 7001,
            parentPID: 7000,
            command: "/Users/x/.cache/uv/archive-v0/BBB/bin/python /Users/x/.cache/uv/archive-v0/BBB/bin/chroma-mcp --client-type persistent",
            memoryMB: 310
        )
    }

    private func liveUvxWrapper() -> MCPProcessParentSnapshot {
        MCPProcessParentSnapshot(
            pid: 7000,
            parentPID: 6000,
            command: "/opt/homebrew/bin/uv tool uvx --python 3.13 --from chroma-mcp==0.2.6 chroma-mcp",
            memoryMB: 5
        )
    }

    private func liveClaudeBroker() -> MCPProcessParentSnapshot {
        MCPProcessParentSnapshot(
            pid: 6000,
            parentPID: 400,
            command: "/Users/admin/.local/bin/claude --settings settings-zai.json --dangerously-skip-permissions",
            memoryMB: 313
        )
    }

    // MARK: - Chain walks

    @Test("ppid 1 → orphaned")
    func ppidOneIsOrphaned() async {
        let result = await reaper.classifyRows([orphanedUvxWrapper()])
        #expect(result.count == 1)
        guard let first = result.first, case .orphaned = first.verdict else {
            if let first = result.first {
                Issue.record("expected orphaned, got \(first.verdict)")
            } else {
                Issue.record("expected 1 classification, got 0")
            }
            return
        }
    }

    @Test("dead parent → orphaned")
    func deadParentIsOrphaned() async {
        let rows = [
            MCPProcessParentSnapshot(
                pid: 9100,
                parentPID: 999_999,
                command: "qdrant-mcp-server",
                memoryMB: 300
            )
        ]
        let result = await reaper.classifyRows(rows)
        guard let first = result.first, case .orphaned = first.verdict else {
            Issue.record("expected orphaned, got \(result.map(\.verdict))")
            return
        }
    }

    @Test("live claude broker chain → owned")
    func liveBrokerChainIsOwned() async {
        let rows = [
            liveClaudeBroker(),
            liveUvxWrapper(),
            ownedPythonChild(),
        ]
        let result = await reaper.classifyRows(rows)
        let child = result.first { $0.process.pid == 7001 }
        #expect(child != nil)
        guard case let .owned(brokerPID, _) = child?.verdict else {
            Issue.record("expected owned, got \(String(describing: child?.verdict))")
            return
        }
        #expect(brokerPID == 6000)
    }

    @Test("dry-run reaps nothing and counts orphans")
    func dryRunReapsNothing() async {
        let rows = [orphanedUvxWrapper(), orphanedPythonChild()]
        let report = await reaper.reap(rows: rows, apply: false)
        #expect(report.dryRun)
        #expect(report.orphanCount == 2)
        #expect(report.reaped.isEmpty)
        #expect(report.failed.isEmpty)
        #expect(report.reclaimedMemoryMB > 0)
    }

    @Test("heuristic agrees with registry needles")
    func heuristicParity() {
        #expect(MCPOrphanReaper.looksLikeMCP("uv tool uvx --from chroma-mcp==0.2.6 chroma-mcp"))
        #expect(MCPOrphanReaper.looksLikeMCP("qdrant-mcp-server"))
        #expect(!MCPOrphanReaper.looksLikeMCP("Google Chrome Helper (Renderer)"))
    }
}
