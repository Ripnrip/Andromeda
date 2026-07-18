/**
 * 🎭 The MCPRegistryView - Read-Only Sprawl Roster
 *
 * Modern SwiftUI: ContentUnavailableView, LazyVStack + ScrollView (stable IDs),
 * material chrome, extracted rows — observe-only, no tracker brands.
 */

import Foundation
import SwiftUI

// MARK: - Presentation

public enum MCPRegistryPresentation: Sendable {
    public static func title(entityCount: Int, sprawlGroupCount: Int) -> String {
        if entityCount == 0 {
            return "MCP Registry — empty"
        }
        if sprawlGroupCount > 0 {
            return "MCP Registry — \(entityCount) · \(sprawlGroupCount) sprawl"
        }
        return "MCP Registry — \(entityCount)"
    }

    public static let emptyMessage = "No MCP servers observed. Run infra.mcp.scan."

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

    public func apply(scan: MCPRegistryScanResult) {
        let live = scan.entities.filter(\.isLive)
        entities = live.isEmpty ? scan.entities : live
        processCount = scan.processCount
        sprawlGroupCount = scan.sprawlGroups.count
        lastMessage = MCPRegistryPresentation.title(
            entityCount: entities.count,
            sprawlGroupCount: sprawlGroupCount
        )
    }

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

public struct MCPRegistryView: View {
    @Bindable public var model: MCPRegistryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: MCPRegistryModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MemoryKitPanelHeader(
                title: model.title,
                systemImage: "server.rack",
                caption: "infra.mcp.scan",
                tint: .orange,
                accessibilityIdentifier: "mcp.registry.title"
            )

            if model.isEmpty {
                ContentUnavailableView {
                    Label("No MCP servers", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text(MCPRegistryPresentation.emptyMessage)
                }
                .accessibilityIdentifier("mcp.registry.empty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.entities) { entity in
                            MCPRegistryRow(entity: entity)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
        .memoryKitPanelChrome()
        .animation(MemoryKitMotion.animation(reduceMotion: reduceMotion), value: model.entities.count)
    }
}

// MARK: - Row

private struct MCPRegistryRow: View {
    let entity: MCPServerEntity

    var body: some View {
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
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.25), in: Capsule())
                    .accessibilityLabel("Duplicate \(badge)")
                    .accessibilityIdentifier("mcp.registry.badge.\(entity.duplicateGroup)")
            }
        }
        .memoryKitChipChrome()
        .accessibilityIdentifier("mcp.registry.row.\(entity.id)")
    }
}

// MARK: - Fixtures

public enum MCPRegistryFixtures {
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
            MCPProcessSnapshot(pid: 4001, command: "npm exec firecrawl-mcp", memoryMB: 71)
        )
        snaps.append(
            MCPProcessSnapshot(pid: 4002, command: "npm exec firecrawl-mcp", memoryMB: 71)
        )
        return snaps
    }

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
    public static var previewEmpty: MCPRegistryModel {
        let model = MCPRegistryModel()
        model.clear()
        return model
    }

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

#Preview("MCP Registry — Empty") {
    MCPRegistryView(model: .previewEmpty)
        .preferredColorScheme(.dark)
}

#Preview("MCP Registry — Sprawl") {
    MCPRegistryView(model: .previewSprawl)
        .preferredColorScheme(.dark)
}
#endif
