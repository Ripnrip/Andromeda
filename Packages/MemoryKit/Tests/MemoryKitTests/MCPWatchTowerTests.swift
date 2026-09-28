/**
 * Tests for MCPWatchTower — bounded-cycle contract, drift accumulation,
 * and the dry-run guarantee that a watch never signals anything.
 */

import Testing
@testable import MemoryKit

@Suite("MCPWatchTower — bounded foreground watch, never a daemon")
struct MCPWatchTowerTests {

    // MARK: - Fixtures (same epidemic shapes as the reaper tests)

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

    private var ownedSet: [MCPProcessParentSnapshot] {
        [ownedPythonChild(), liveUvxWrapper(), liveClaudeBroker()]
    }

    // MARK: - Bounded-run contract (the anti-daemon invariant)

    @Test("watch runs exactly maxCycles and stops")
    func boundedRunStops() async {
        let tower = MCPWatchTower()
        let summary = await tower.watch(
            maxCycles: 3,
            interval: .milliseconds(10),
            apply: false,
            snapshot: { [] }
        )
        // The cycles array is the call record: one entry per snapshot.
        #expect(summary.cycles.count == 3)
        #expect(summary.cycles.map(\.index) == [1, 2, 3])
    }

    @Test("maxCycles <= 0 clamps to one cycle — a watch always exits")
    func zeroCyclesClampsToOne() async {
        let tower = MCPWatchTower()
        let summary = await tower.watch(
            maxCycles: 0,
            interval: .milliseconds(1),
            apply: false,
            snapshot: { [] }
        )
        #expect(summary.cycles.count == 1)
    }

    @Test("cancellation ends the run early without hanging")
    func cancellationEndsRun() async {
        let tower = MCPWatchTower()
        let task = Task {
            await tower.watch(
                maxCycles: 1_000_000,
                interval: .milliseconds(50),
                apply: false,
                snapshot: { [] }
            )
        }
        // Give it a couple of ticks, then cancel — the run must finish.
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        let summary = await task.value
        #expect(summary.cycles.count < 1_000_000)
        #expect(!summary.cycles.isEmpty)
    }

    // MARK: - Cycle classification

    @Test("runCycle classifies an orphan without signaling (observe mode)")
    func observeModeNeverReaps() async {
        let tower = MCPWatchTower()
        let cycle = await tower.runCycle(
            rows: [orphanedUvxWrapper()],
            apply: false,
            index: 1
        )
        #expect(cycle.orphanCount == 1)
        #expect(cycle.reaped.isEmpty)
        #expect(cycle.failed.isEmpty)
        #expect(cycle.classifications.count == 1)
    }

    @Test("runCycle spares owned chains")
    func ownedChargesAreSpared() async {
        let tower = MCPWatchTower()
        let cycle = await tower.runCycle(rows: ownedSet, apply: false, index: 1)
        #expect(cycle.orphanCount == 0)
        #expect(cycle.classifications.count == 2) // python child + uvx wrapper are MCP-looking
        for entry in cycle.classifications {
            if case .owned = entry.verdict { continue }
            Issue.record("expected owned, got \(entry.verdict)")
        }
    }

    // MARK: - Summary aggregation

    @Test("summary aggregates drift across cycles")
    func driftAggregates() async {
        let tower = MCPWatchTower()
        let summary = await tower.watch(
            maxCycles: 2,
            interval: .milliseconds(5),
            apply: false
        ) { [orphanedUvxWrapper()] }
        #expect(summary.totalOrphans == 2) // one orphan seen twice
        #expect(summary.peakOrphanedMemoryMB > 0)
        #expect(summary.apply == false)
        #expect(summary.totalReaped == 0)
        #expect(summary.totalFailed == 0)
    }

    @Test("clean fleet summary is zero-drift")
    func cleanFleetIsZeroDrift() async {
        let tower = MCPWatchTower()
        let summary = await tower.watch(
            maxCycles: 2,
            interval: .milliseconds(5),
            apply: false,
            snapshot: { [] }
        )
        #expect(summary.totalOrphans == 0)
        #expect(summary.peakOrphanedMemoryMB == 0)
    }

    // MARK: - Cycle value semantics

    @Test("cycle index and orphan memory are exposed")
    func cycleExposesMemory() async {
        let cycle = MCPWatchCycle(
            index: 7,
            classifications: [
                MCPOrphanClassification(
                    process: orphanedUvxWrapper(),
                    verdict: .orphaned(reason: "test")
                )
            ],
            reaped: [],
            failed: []
        )
        #expect(cycle.index == 7)
        #expect(cycle.orphanedMemoryMB == 5)
        #expect(cycle.orphanCount == 1)
    }
}
