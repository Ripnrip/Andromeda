/**
 * 🎭 The MCPRegistryView - Read-Only Sprawl Roster
 *
 * "A quiet list of MCP citizens with duplicate badges —
 * empty stage when the house is dark, sprawl chorus when
 * filesystem sings fifteen times. No kill buttons. No tracker brands."
 *
 * - The Theatrical Console Virtuoso of Andromeda Observe
 */

import Foundation
import SwiftUI

// MARK: - Presentation model (testable without SnapshotTesting)

/// 🌟 Pure presentation helpers for the MCP roster — empty / sprawl / badges.
public enum MCPRegistryPresentation: Sendable {
    /// 🎨 Headline for the roster panel.
    public static func title(entityCount: Int, sprawlGroupCount: Int) -> String {
        if entityCount == 0 {
            return "MCP Registry — empty"
        }
        if sprawlGroupCount > 0 {
            return "MCP Registry — \(entityCount) · \(sprawlGroupCount) sprawl"
        }
        return "MCP Registry — \(entityCount)"
    }

    /// 🌊 Empty-state copy (no Linear/Multica names).
    public static let emptyMessage = "No MCP servers observed. Run infra.mcp.scan."

    /// 🎨 Row subtitle: source · pid · memory.
    public static func subtitle(for entity: MCPServerEntity) -> String {
        var parts: [String] = [entity.source.displayName]
        if let pid = entity.pid {
            parts.append("pid \(pid)")
        }
        if let mb = entity.memoryMB {
            parts.append(String(format: "%.0f MB", mb))
        }
        if entity.isLive == false {
            parts.append("config")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Model

/// 🎭 Main-actor roster model for the read-only MCP list.
@MainActor
@Observable
public final class MCPRegistryModel {
    public private(set) var entities: [MCPServerEntity]
    public private(set) var processCount: Int
    public private(set) var sprawlGroupCount: Int
    public var lastMessage: String?

    public init(
        entities: [MCPServerEntity] = [],
        processCount: Int = 0,
        sprawlGroupCount: Int = 0
    ) {
        self.entities = entities
        self.processCount = processCount
        self.sprawlGroupCount = sprawlGroupCount
    }

    /// 📜 Apply a scan result (capability `infra.mcp.scan` outcome).
    public func apply(scan: MCPRegistryScanResult) {
        // Prefer live rows with duplicate badges; also surface annotated config seeds that sprawl.
        let live = scan.entities.filter(\.isLive)
        if live.isEmpty {
            entities = scan.entities
        } else {
            entities = live
        }
        processCount = scan.processCount
        sprawlGroupCount = scan.sprawlGroups.count
        lastMessage = MCPRegistryPresentation.title(
            entityCount: entities.count,
            sprawlGroupCount: sprawlGroupCount
        )
    }

    /// 🌙 Clear to empty state.
    public func clear() {
        entities = []
        processCount = 0
        sprawlGroupCount = 0
        lastMessage = MCPRegistryPresentation.emptyMessage
    }

    public var title: String {
        MCPRegistryPresentation.title(
            entityCount: entities.count,
            sprawlGroupCount: sprawlGroupCount
        )
    }

    public var isEmpty: Bool { entities.isEmpty }
}

// MARK: - View

/**
 * 🎭 MCPRegistryView — read-only list + duplicate badge.
 *
 * Never exposes Linear / Multica. Capabilities remain `infra.mcp.*`.
 */
public struct MCPRegistryView: View {
    @Bindable public var model: MCPRegistryModel

    public init(model: MCPRegistryModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.headline)
                .accessibilityIdentifier("mcp.registry.title")

            if model.isEmpty {
                Text(MCPRegistryPresentation.emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mcp.registry.empty")
            } else {
                List(model.entities) { entity in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entity.packageName)
                                .font(.body.monospaced())
                                .lineLimit(1)
                            Text(MCPRegistryPresentation.subtitle(for: entity))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let badge = entity.duplicateBadgeLabel {
                            Text(badge)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.25))
                                .clipShape(Capsule())
                                .accessibilityLabel("Duplicate \(badge)")
                                .accessibilityIdentifier("mcp.registry.badge.\(entity.duplicateGroup)")
                        }
                    }
                    .accessibilityIdentifier("mcp.registry.row.\(entity.id)")
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }
}

// MARK: - Fixtures (tests + previews — never kills processes)

/// 🧪 Shared fixture factory for previews + tests (observe-only sprawl).
public enum MCPRegistryFixtures {
    /// 🌊 Fake process list mirroring Studio sprawl (filesystem/memory/sequential ×15).
    public static func sprawlProcessList() -> [MCPProcessSnapshot] {
        var snaps: [MCPProcessSnapshot] = []
        for i in 1...15 {
            snaps.append(
                MCPProcessSnapshot(
                    pid: 1000 + i,
                    command: "npm exec @modelcontextprotocol/server-filesystem /Users/admin",
                    memoryMB: 71
                )
            )
            snaps.append(
                MCPProcessSnapshot(
                    pid: 2000 + i,
                    command: "npm exec @modelcontextprotocol/server-memory",
                    memoryMB: 71
                )
            )
            snaps.append(
                MCPProcessSnapshot(
                    pid: 3000 + i,
                    command: "npm exec @modelcontextprotocol/server-sequential-thinking",
                    memoryMB: 71
                )
            )
        }
        snaps.append(
            MCPProcessSnapshot(
                pid: 4001,
                command: "npm exec firecrawl-mcp",
                memoryMB: 71
            )
        )
        snaps.append(
            MCPProcessSnapshot(
                pid: 4002,
                command: "npm exec firecrawl-mcp",
                memoryMB: 71
            )
        )
        return snaps
    }

    /// 🌙 Quiet single-server fixture (no duplicates).
    public static func uniqueProcessList() -> [MCPProcessSnapshot] {
        [
            MCPProcessSnapshot(
                pid: 42,
                command: "npm exec @modelcontextprotocol/server-filesystem /tmp",
                memoryMB: 64
            ),
        ]
    }
}

#if DEBUG
extension MCPRegistryModel {
    /// 🌙 Empty house — no MCP processes on stage.
    public static var previewEmpty: MCPRegistryModel {
        let model = MCPRegistryModel()
        model.clear()
        return model
    }

    /// 🌊 Studio-style sprawl — filesystem ×15 (+ memory / sequential twins).
    public static var previewSprawl: MCPRegistryModel {
        let snaps = MCPRegistryFixtures.sprawlProcessList()
        let hook = RecordingMCPTelemetrySpanHook()
        let telemetry = RecordingMCPTelemetry(hook: hook)
        var registry = MCPServerRegistry(
            enumerator: MockMCPProcessEnumerator(processes: snaps),
            telemetry: telemetry
        )
        let scan = registry.scan()
        let model = MCPRegistryModel()
        model.apply(scan: scan)
        return model
    }
}

#Preview("MCP Registry — Empty (Light)") {
    MCPRegistryView(model: .previewEmpty)
        .preferredColorScheme(.light)
}

#Preview("MCP Registry — Empty (Dark)") {
    MCPRegistryView(model: .previewEmpty)
        .preferredColorScheme(.dark)
}

#Preview("MCP Registry — Sprawl (Light)") {
    MCPRegistryView(model: .previewSprawl)
        .preferredColorScheme(.light)
}

#Preview("MCP Registry — Sprawl (Dark)") {
    MCPRegistryView(model: .previewSprawl)
        .preferredColorScheme(.dark)
}

#Preview("MCP Registry — Sprawl (Large Dynamic Type)") {
    MCPRegistryView(model: .previewSprawl)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("MCP Registry — Empty (a11y identifiers present)") {
    // Reduce-motion is honored implicitly (view has no motion); keep a11y IDs in empty state.
    MCPRegistryView(model: .previewEmpty)
        .preferredColorScheme(.light)
}
#endif
