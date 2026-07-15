/**
 * 🎭 MCPServerRegistryTests - Sprawl Quality Assurance Ritual
 *
 * "We summon a fake Activity Monitor chorus — filesystem ×15 —
 * prove the registry groups twins, emits telemetry, and never
 * reaches for a kill wand. Observe only; the show must go on."
 *
 * - The Theatrical QA Virtuoso of MCP Observability
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🚀 MCP Server Registry + Telemetry Suite")
struct MCPServerRegistryTests {

    // MARK: - Catalog seeds

    @Test("📜 Catalog seeds Cursor / Claude / Codex / Hermes configs")
    func testCatalogSeedsKnownSources() {
        let seeds = MCPServerRegistry.catalogSeeds()
        let sources = Set(seeds.map(\.source))

        #expect(sources.contains(.cursor))
        #expect(sources.contains(.claude))
        #expect(sources.contains(.codex))
        #expect(sources.contains(.hermes))
        #expect(seeds.count >= 30)
        #expect(seeds.allSatisfy { $0.isLive == false })
        #expect(seeds.contains { $0.packageName.contains("server-filesystem") })
    }

    @Test("🎭 Capability IDs are infra.mcp.list / infra.mcp.scan (no tracker brands)")
    func testCapabilityIDsHideTrackers() {
        #expect(MCPCapabilityID.list.rawValue == "infra.mcp.list")
        #expect(MCPCapabilityID.scan.rawValue == "infra.mcp.scan")
        #expect(MCPCapabilityID.list.rawValue.lowercased().contains("linear") == false)
        #expect(MCPCapabilityID.scan.rawValue.lowercased().contains("multica") == false)
    }

    // MARK: - Normalizer

    @Test("🔮 Normalizer extracts package + duplicate group from npm exec")
    func testPackageNormalizer() {
        let cmd = "npm exec @modelcontextprotocol/server-filesystem /Users/admin"
        let package = MCPPackageNormalizer.packageName(fromCommand: cmd)
        #expect(package == "@modelcontextprotocol/server-filesystem")
        #expect(
            MCPPackageNormalizer.duplicateGroup(forPackage: package)
                == "@modelcontextprotocol/server-filesystem"
        )

        let versioned = "npm exec chrome-devtools-mcp@1.5.0"
        #expect(MCPPackageNormalizer.packageName(fromCommand: versioned) == "chrome-devtools-mcp")
    }

    // MARK: - Live scan + duplicates (fixtures — no kill)

    @Test("🌊 Sprawl fixture groups filesystem/memory/sequential as ×15 duplicates")
    func testSprawlDuplicateGrouping() {
        let hook = RecordingMCPTelemetrySpanHook()
        let telemetry = RecordingMCPTelemetry(hook: hook)
        let enumerator = MockMCPProcessEnumerator(
            processes: MCPRegistryFixtures.sprawlProcessList()
        )

        var registry = MCPServerRegistry(enumerator: enumerator, telemetry: telemetry)
        let result = registry.scan()

        #expect(result.processCount == 47) // 15*3 + 2 firecrawl
        #expect(result.sprawlGroups["@modelcontextprotocol/server-filesystem"] == 15)
        #expect(result.sprawlGroups["@modelcontextprotocol/server-memory"] == 15)
        #expect(result.sprawlGroups["@modelcontextprotocol/server-sequential-thinking"] == 15)
        #expect(result.sprawlGroups["firecrawl-mcp"] == 2)

        let liveFS = result.entities.filter {
            $0.isLive && $0.duplicateGroup == "@modelcontextprotocol/server-filesystem"
        }
        #expect(liveFS.count == 15)
        #expect(liveFS.allSatisfy { $0.liveInstanceCount == 15 })
        #expect(liveFS.allSatisfy { $0.isDuplicate })
        #expect(liveFS.first?.duplicateBadgeLabel == "×15")
        #expect(liveFS.first?.memoryMB == 71)
        #expect(liveFS.first?.pid != nil)
    }

    @Test("🌙 Unique fixture has no sprawl badges")
    func testUniqueProcessNoSprawl() {
        let telemetry = RecordingMCPTelemetry()
        var registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(
                processes: MCPRegistryFixtures.uniqueProcessList()
            ),
            telemetry: telemetry
        )
        let result = registry.scan()

        #expect(result.processCount == 1)
        #expect(result.sprawlGroups.isEmpty)
        let live = result.entities.filter(\.isLive)
        #expect(live.count == 1)
        #expect(live.first?.isDuplicate == false)
        #expect(live.first?.duplicateBadgeLabel == nil)
    }

    @Test("🌙 Null enumerator leaves seeds config-only (no fake live)")
    func testNullEnumeratorNoFakeLive() {
        var registry = MCPServerRegistry(
            enumerator: NullMCPProcessEnumerator(),
            telemetry: RecordingMCPTelemetry()
        )
        let result = registry.scan()
        #expect(result.processCount == 0)
        #expect(result.sprawlGroups.isEmpty)
        #expect(result.entities.filter(\.isLive).isEmpty)
    }

    @Test("📜 infra.mcp.list returns roster; scan mutates via observing copy")
    func testListAndImmutableScan() {
        let registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(
                processes: MCPRegistryFixtures.uniqueProcessList()
            ),
            telemetry: RecordingMCPTelemetry()
        )
        #expect(registry.list().count == MCPServerRegistry.catalogSeeds().count)

        let (scanned, result) = registry.scanning()
        #expect(result.processCount == 1)
        #expect(scanned.list().contains { $0.isLive })
        #expect(scanned.duplicateEntities().isEmpty)
    }

    // MARK: - Telemetry day-1

    @Test("📡 Scan emits registry.scan + process_count + duplicate_detected")
    func testTelemetryEvents() {
        let hook = RecordingMCPTelemetrySpanHook()
        let telemetry = RecordingMCPTelemetry(hook: hook)
        var registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(
                processes: MCPRegistryFixtures.sprawlProcessList()
            ),
            telemetry: telemetry
        )
        _ = registry.scan()

        let names = hook.events.map(\.name)
        #expect(names.contains("registry.scan"))
        #expect(names.contains("mcp.process_count"))
        #expect(names.contains("mcp.duplicate_detected"))

        let duplicates = hook.events.compactMap { event -> (String, Int)? in
            if case let .duplicateDetected(group, count) = event {
                return (group, count)
            }
            return nil
        }
        #expect(duplicates.contains { $0.0.contains("filesystem") && $0.1 == 15 })
        #expect(duplicates.contains { $0.0 == "firecrawl-mcp" && $0.1 == 2 })

        if case let .processCount(count)? = hook.events.first(where: {
            if case .processCount = $0 { return true }
            return false
        }) {
            #expect(count == 47)
        } else {
            Issue.record("Expected mcp.process_count event")
        }
    }

    @Test("📜 File span hook writes JSON lines for observability agent")
    func testFileSpanHook() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("mcp-telemetry-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let hook = FileMCPTelemetrySpanHook(fileURL: url)
        let telemetry = MCPTelemetry(spanHook: hook)
        telemetry.emit(.processCount(3))
        telemetry.emit(.duplicateDetected(group: "filesystem", count: 15))

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("mcp.process_count"))
        #expect(text.contains("mcp.duplicate_detected"))
        #expect(text.contains("\"count\":\"15\"") || text.contains("\"count\": \"15\"") || text.contains("15"))
    }

    @Test("🎭 Entity Codable round-trip")
    func testEntityCodable() throws {
        let entity = MCPServerEntity(
            id: "mcp.live.filesystem.1001",
            packageName: "@modelcontextprotocol/server-filesystem",
            command: "npm exec @modelcontextprotocol/server-filesystem",
            pid: 1001,
            memoryMB: 71,
            duplicateGroup: "@modelcontextprotocol/server-filesystem",
            source: .cursor,
            liveInstanceCount: 15,
            isLive: true
        )
        let data = try JSONEncoder().encode(entity)
        let decoded = try JSONDecoder().decode(MCPServerEntity.self, from: data)
        #expect(decoded == entity)
        #expect(decoded.duplicateBadgeLabel == "×15")
    }

    // MARK: - ps parser (no live shell in assertion path)

    @Test("👁️ Shell enumerator parser extracts MCP rows from ps text")
    func testParsePSOutput() {
        let sample = """
          1234  72704 npm exec @modelcontextprotocol/server-filesystem /tmp
          9999   1000 /usr/bin/ssh user@host
          5555  71000 node /path/mcp-server-memory
        """
        let snaps = ShellMCPProcessEnumerator.parsePSOutput(sample)
        #expect(snaps.count == 2)
        #expect(snaps.contains { $0.pid == 1234 })
        #expect(snaps.contains { $0.pid == 5555 })
        #expect(snaps.contains { $0.pid == 9999 } == false)
        #expect(ShellMCPProcessEnumerator.looksLikeMCP("vim README.md") == false)
    }
}

@Suite("🎭 MCP Registry View Presentation Rituals")
@MainActor
struct MCPRegistryViewTests {

    @Test("🌙 Empty presentation copy + title")
    func testEmptyPresentation() {
        let model = MCPRegistryModel()
        model.clear()
        #expect(model.isEmpty)
        #expect(model.title == "MCP Registry — empty")
        #expect(model.lastMessage == MCPRegistryPresentation.emptyMessage)
        #expect(MCPRegistryPresentation.emptyMessage.lowercased().contains("linear") == false)
        #expect(MCPRegistryPresentation.emptyMessage.lowercased().contains("multica") == false)
    }

    @Test("🌊 Sprawl presentation shows counts + badges")
    func testSprawlPresentation() {
        var registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(
                processes: MCPRegistryFixtures.sprawlProcessList()
            ),
            telemetry: RecordingMCPTelemetry()
        )
        let scan = registry.scan()
        let model = MCPRegistryModel()
        model.apply(scan: scan)

        #expect(model.isEmpty == false)
        #expect(model.processCount == 47)
        #expect(model.sprawlGroupCount == 4)
        #expect(model.title.contains("sprawl"))
        #expect(model.entities.contains { $0.duplicateBadgeLabel == "×15" })

        let fs = model.entities.first {
            $0.duplicateGroup == "@modelcontextprotocol/server-filesystem"
        }
        #expect(fs != nil)
        let subtitle = MCPRegistryPresentation.subtitle(for: fs!)
        #expect(subtitle.contains("pid"))
        #expect(subtitle.contains("MB"))
    }

    @Test("💎 Presentation titles cover empty + sprawl (pixel catalog in MCPRegistrySnapshotTests)")
    func testPresentationTitles() {
        #expect(MCPRegistryPresentation.title(entityCount: 0, sprawlGroupCount: 0) == "MCP Registry — empty")
        #expect(
            MCPRegistryPresentation.title(entityCount: 47, sprawlGroupCount: 4)
                == "MCP Registry — 47 · 4 sprawl"
        )
    }
}
