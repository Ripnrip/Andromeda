import Foundation

/// 🌟 Stable client capability IDs for UI surfaces.
///
/// Single source of truth for dotted capability strings shown in the control
/// bar, control plane, and HUD chrome. Call sites use `.rawValue` — never
/// re-type the literal (swift-canon enum-design / issue #57).
public enum ClientCapabilityID: String, Sendable, CaseIterable {
    case memoryRecall = "memory.recall"
    case memoryStore = "memory.store"
    case mcpHost = "mcp.host"
    case skillsInvoke = "skills.invoke"
    case inferWrite = "infer.write"
    case secretsBroker = "secrets.broker"
    case fleetPulse = "fleet.pulse"
    case searchAsk = "search.ask"
    case systemAdmin = "system.admin"
}
