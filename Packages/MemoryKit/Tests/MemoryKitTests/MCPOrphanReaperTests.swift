/* 
 * Tests for the MCP orphan reaper classifier — chain walks, ownership,
 * and dry-run refusal to signal anything.
 */

@testable import MemoryKit
import Testing

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
            ),
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
        #expect(MCPOrphanReaper.looksLikeMCP("node /Users/admin/.nvm/versions/node/v22.20.0/bin/playwright-mcp"))
        #expect(!MCPOrphanReaper.looksLikeMCP("Google Chrome Helper (Renderer)"))
    }

    // MARK: - Intentional PPID-1 daemons (the mcporter lesson)

    /// mcporter runs three deliberate `daemon start --foreground` nodes with
    /// PPID 1 (launchd-adopted). They are NOT needles today — deliberately:
    /// a needle-matching intentional daemon at PPID 1 classifies `orphaned`
    /// and becomes a reaper target the moment someone runs `--apply`.
    /// Until the CLI allowlist is operator-curated (see `--spare`), DO NOT
    /// add an `mcporter` needle.
    @Test("mcporter daemons are invisible to the heuristic (intentional)")
    func mcporterDaemonsNotNeedles() {
        #expect(!MCPOrphanReaper.looksLikeMCP(
            "node /Users/admin/.local/bin/mcporter daemon start --foreground"
        ))
    }

    @Test("needle-matching intentional daemon at PPID 1 is spared by allowlist, not reaped")
    func sparePIDsProtectIntentionalDaemons() async {
        // Hypothetical future: someone adds a needle that matches the
        // claude-mem worker daemon (bun, PPID 1 after operator restart).
        // Pattern captured live 2026-09-28: the daemon matches via
        // `claude-mem` needle and has ppid 1.
        let intentionalDaemon = MCPProcessParentSnapshot(
            pid: 4242,
            parentPID: 1,
            command: "/Users/admin/.bun/bin/bun /Users/admin/.claude/plugins/cache/thedotmack/claude-mem/13.14.0/scripts/worker-service.cjs --daemon",
            memoryMB: 87
        )
        let reaperWithFakeSignal = MCPOrphanReaper(signal: { _, _ in -1 }) // would fail if called
        let report = await reaperWithFakeSignal.reap(
            rows: [intentionalDaemon],
            apply: true,
            sparePIDs: [4242]
        )
        guard case .orphaned = report.classifications.first?.verdict else {
            Issue.record("expected orphaned classification (visibility preserved)")
            return
        }
        #expect(!report.dryRun)
        #expect(report.spared == [4242])
        #expect(report.reaped.isEmpty)
        #expect(report.failed.isEmpty)
    }

    // MARK: - Broker-chain wall (live shapes observed 2026-09-27/28)

    @Test("hermes venv python broker chain → owned")
    func hermesBrokerChainIsOwned() async {
        let rows = [
            MCPProcessParentSnapshot(
                pid: 7980, parentPID: 5000,
                command: "/nvm/bin/playwright-mcp", memoryMB: 8
            ),
            MCPProcessParentSnapshot(
                pid: 5000, parentPID: 400,
                command: "/Users/admin/.hermes/hermes-agent/venv/bin/python -m hermes_agent.server", memoryMB: 300
            ),
        ]
        let result = await reaper.classifyRows(rows)
        guard case .owned = result.first?.verdict else {
            Issue.record("expected owned, got \(String(describing: result.first?.verdict))")
            return
        }
    }

    @Test("Claude.app broker chain through Helpers/disclaimer intermediate → owned")
    func claudeAppDisclaimerChainIsOwned() async {
        // Live shape 2026-09-27: Claude Desktop spawns MCP servers under
        // `.../Helpers/disclaimer --pgroup ...` intermediates. The MCP-looking
        // row is the CHILD; the disclaimer helper is its broker. The explicit
        // `claude.app/contents/helpers` broker needle must classify it owned
        // (the loose `claude` substring would also match, but the explicit
        // needle is the contract).
        let rows = [
            MCPProcessParentSnapshot(
                pid: 22234, parentPID: 22231,
                command: "npx @modelcontextprotocol/server-filesystem /Users/admin", memoryMB: 7
            ),
            MCPProcessParentSnapshot(
                pid: 22231, parentPID: 22025,
                command: "/Applications/Claude.app/Contents/Helpers/disclaimer --pgroup 123 --spawn-preload", memoryMB: 281
            ),
        ]
        let result = await reaper.classifyRows(rows)
        guard case let .owned(brokerPID, _) = result.first?.verdict else {
            Issue.record("expected owned, got \(String(describing: result.first?.verdict))")
            return
        }
        #expect(brokerPID == 22231)
    }

    @Test("deep wrapper chain beyond 3 hops → unknown, never signaled")
    func deepChainStaysUnknown() async {
        let rows = [
            MCPProcessParentSnapshot(pid: 9, parentPID: 8, command: "qdrant-mcp-server", memoryMB: 300),
            MCPProcessParentSnapshot(pid: 8, parentPID: 7, command: "uv tool uvx wrapper-a", memoryMB: 1),
            MCPProcessParentSnapshot(pid: 7, parentPID: 6, command: "uv tool uvx wrapper-b", memoryMB: 1),
            MCPProcessParentSnapshot(pid: 6, parentPID: 5, command: "uv tool uvx wrapper-c", memoryMB: 1),
            MCPProcessParentSnapshot(pid: 5, parentPID: 400, command: "some unknown host", memoryMB: 1),
        ]
        let report = await reaper.reap(rows: rows, apply: true)
        guard case .unknown = report.classifications.first?.verdict else {
            Issue.record("expected unknown for >3-hop chain, got \(String(describing: report.classifications.first?.verdict))")
            return
        }
        #expect(report.reaped.isEmpty)
        #expect(report.failed.isEmpty)
    }

    @Test("failed signal path lands in failed, not reaped")
    func failedSignalPath() async {
        let orphan = MCPProcessParentSnapshot(
            pid: 31337, parentPID: 1,
            command: "qdrant-mcp-server", memoryMB: 300
        )
        // Simulate EPERM: every kill attempt errors.
        let failing = MCPOrphanReaper(signal: { _, _ in -1 })
        let report = await failing.reap(rows: [orphan], apply: true)
        #expect(report.failed == [31337])
        #expect(report.reaped.isEmpty)
    }
}
