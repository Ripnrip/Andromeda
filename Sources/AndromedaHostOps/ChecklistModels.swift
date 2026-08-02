import Foundation

/// One row in the host-first setup / doctor checklist.
public struct ChecklistItem: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        case pass
        case warn
        case fail
        case skip
    }

    public let id: String
    public let title: String
    public let status: Status
    public let detail: String
    public let fixHint: String?

    public init(
        id: String,
        title: String,
        status: Status,
        detail: String,
        fixHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fixHint = fixHint
    }
}

/// Aggregated `andromeda-runtime doctor` report. Exit code mirrors worst severity.
public struct DoctorReport: Sendable, Equatable {
    public let items: [ChecklistItem]
    public let generatedAt: Date

    public init(items: [ChecklistItem], generatedAt: Date = Date()) {
        self.items = items
        self.generatedAt = generatedAt
    }

    public var failedCount: Int { items.filter { $0.status == .fail }.count }
    public var warnCount: Int { items.filter { $0.status == .warn }.count }

    public var exitCode: Int32 {
        failedCount > 0 ? 1 : 0
    }

    /// Renders a phone-skimmable checklist for operators.
    public func render() -> String {
        var lines: [String] = ["Andromeda doctor", ""]
        for item in items {
            lines.append("\(Self.mark(item.status)) \(item.title) — \(item.detail)")
            if let fixHint = item.fixHint {
                lines.append("       fix: \(fixHint)")
            }
        }
        lines.append("")
        lines.append("summary: \(failedCount) fail, \(warnCount) warn, \(items.count) checks")
        return lines.joined(separator: "\n")
    }

    private static func mark(_ status: ChecklistItem.Status) -> String {
        switch status {
        case .pass: return "[pass]"
        case .warn: return "[warn]"
        case .fail: return "[fail]"
        case .skip: return "[skip]"
        }
    }
}

/// Aggregated `andromeda-runtime setup` plan plus guest MCP fragment.
public struct SetupPlan: Sendable, Equatable {
    public let items: [ChecklistItem]
    public let guestConfig: GuestMCPConfig
    public let dryRun: Bool

    public init(items: [ChecklistItem], guestConfig: GuestMCPConfig, dryRun: Bool) {
        self.items = items
        self.guestConfig = guestConfig
        self.dryRun = dryRun
    }

    /// Renders the host-first setup checklist and guest endpoint.
    public func render() -> String {
        var lines: [String] = [
            dryRun ? "Andromeda setup (dry-run)" : "Andromeda setup",
            "",
        ]
        for item in items {
            let mark: String
            switch item.status {
            case .pass: mark = "[pass]"
            case .warn: mark = "[warn]"
            case .fail: mark = "[fail]"
            case .skip: mark = "[skip]"
            }
            lines.append("\(mark) \(item.title) — \(item.detail)")
            if let fixHint = item.fixHint {
                lines.append("       fix: \(fixHint)")
            }
        }
        lines.append("")
        lines.append("Guest MCP endpoint: \(guestConfig.url)")
        lines.append("Guest note: \(guestConfig.notes)")
        return lines.joined(separator: "\n")
    }
}
