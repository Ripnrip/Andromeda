import Foundation

/// Guest-facing MCP config fragment — never includes Slack/GitHub secrets.
public struct GuestMCPConfig: Sendable, Equatable, Codable {
    public let serverName: String
    public let url: String
    /// Broker credential for Andromeda only (not upstream provider tokens).
    /// When `includeBrokerToken` is false, guests reference an env var instead.
    public let headers: [String: String]
    public let notes: String

    public init(serverName: String, url: String, headers: [String: String], notes: String) {
        self.serverName = serverName
        self.url = url
        self.headers = headers
        self.notes = notes
    }

    /// Builds a Cursor/Claude-compatible mcp.json entry pointing at Andromeda.
    public static func make(
        gatewayBaseURL: String,
        brokerToken: String?,
        includeBrokerTokenInline: Bool = false
    ) -> GuestMCPConfig {
        let url = gatewayBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/mcp"
        var headers: [String: String] = [:]
        if includeBrokerTokenInline, let brokerToken, !brokerToken.isEmpty {
            // Still not an upstream secret — only the Andromeda broker token.
            headers["Authorization"] = "Bearer \(brokerToken)"
        } else {
            headers["Authorization"] = "Bearer ${ANDROMEDA_BROKER_TOKEN}"
        }
        return GuestMCPConfig(
            serverName: "andromeda",
            url: url,
            headers: headers,
            notes: "Host Andromeda keeps Slack/GitHub tokens. Guest configs must not contain SLACK_* or GITHUB_* secrets."
        )
    }

    /// Renders a Cursor-style mcp.json document.
    public func renderMCPJSON() throws -> String {
        let document: [String: Any] = [
            "mcpServers": [
                serverName: [
                    "url": url,
                    "headers": headers,
                ] as [String: Any],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPShimError.invalidRequest("failed to encode guest mcp.json")
        }
        return text + "\n"
    }

    /// Returns true when the rendered config still contains forbidden upstream secret patterns.
    public static func containsUpstreamSecrets(_ text: String) -> Bool {
        let patterns = [
            "xoxb-",
            "xoxp-",
            "ghp_",
            "github_pat_",
            "SLACK_BOT_TOKEN",
            "SLACK_TOKEN",
            "GITHUB_TOKEN",
            "GH_TOKEN",
        ]
        return patterns.contains { text.contains($0) }
    }
}

/// Interactive checklist models for `andromeda setup` / `andromeda doctor`.
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

    public func render() -> String {
        var lines: [String] = ["Andromeda doctor", ""]
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
        lines.append("summary: \(failedCount) fail, \(warnCount) warn, \(items.count) checks")
        return lines.joined(separator: "\n")
    }
}

public struct SetupPlan: Sendable, Equatable {
    public let items: [ChecklistItem]
    public let guestConfig: GuestMCPConfig
    public let dryRun: Bool

    public init(items: [ChecklistItem], guestConfig: GuestMCPConfig, dryRun: Bool) {
        self.items = items
        self.guestConfig = guestConfig
        self.dryRun = dryRun
    }

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
        }
        lines.append("")
        lines.append("Guest MCP endpoint: \(guestConfig.url)")
        lines.append("Guest note: \(guestConfig.notes)")
        return lines.joined(separator: "\n")
    }
}

/// Pure checklist builders — no process mutation, safe for tests.
public enum HostDiagnostics {
    public static func doctor(
        vault: SecretVault,
        brokerTokenConfigured: Bool,
        gatewayReachable: Bool,
        guestConfigText: String?,
        menubarAvailable: Bool
    ) -> DoctorReport {
        var items: [ChecklistItem] = []

        items.append(
            ChecklistItem(
                id: "gateway",
                title: "Hummingbird gateway",
                status: gatewayReachable ? .pass : .fail,
                detail: gatewayReachable ? "reachable" : "not reachable",
                fixHint: gatewayReachable ? nil : "Run `andromeda serve` or `andromeda setup` on the host"
            )
        )

        items.append(
            ChecklistItem(
                id: "broker",
                title: "Broker token",
                status: brokerTokenConfigured ? .pass : .fail,
                detail: brokerTokenConfigured ? "configured" : "missing",
                fixHint: brokerTokenConfigured ? nil : "Set ANDROMEDA_BROKER_TOKEN on the host"
            )
        )

        for snapshot in vault.snapshots {
            items.append(
                ChecklistItem(
                    id: "secret.\(snapshot.capability.rawValue)",
                    title: "Secret \(snapshot.capability.rawValue)",
                    status: snapshot.configured ? .pass : .warn,
                    detail: snapshot.configured ? "present (\(snapshot.envKey))" : "not set",
                    fixHint: snapshot.configured ? nil : "Set \(snapshot.envKey) on the host only"
                )
            )
        }

        if let guestConfigText {
            let dirty = GuestMCPConfig.containsUpstreamSecrets(guestConfigText)
            items.append(
                ChecklistItem(
                    id: "guest.mcp",
                    title: "Guest MCP config scrub",
                    status: dirty ? .fail : .pass,
                    detail: dirty ? "contains upstream secret markers" : "no upstream secrets detected",
                    fixHint: dirty ? "Regenerate with `andromeda setup` — remove Slack/GitHub tokens from guest mcp.json" : nil
                )
            )
        } else {
            items.append(
                ChecklistItem(
                    id: "guest.mcp",
                    title: "Guest MCP config scrub",
                    status: .skip,
                    detail: "no guest config provided"
                )
            )
        }

        items.append(
            ChecklistItem(
                id: "ui.menubar",
                title: "Visible status surface",
                status: menubarAvailable ? .pass : .warn,
                detail: menubarAvailable ? "menubar/floating bar available" : "CLI checklist only on this host",
                fixHint: menubarAvailable ? nil : "On macOS, HUD/menubar provides live status; CLI doctor remains authoritative"
            )
        )

        return DoctorReport(items: items)
    }

    public static func setupPlan(
        vault: SecretVault,
        brokerToken: String,
        gatewayBaseURL: String,
        vmDetected: Bool,
        dryRun: Bool,
        menubarAvailable: Bool
    ) -> SetupPlan {
        var items: [ChecklistItem] = []
        items.append(
            ChecklistItem(
                id: "host.start",
                title: "Host entrypoint",
                status: .pass,
                detail: "setup starts on host (not guest)"
            )
        )
        items.append(
            ChecklistItem(
                id: "vm.detect",
                title: "Guest VM signal",
                status: vmDetected ? .pass : .warn,
                detail: vmDetected ? "VM/guest signal detected" : "no VM detected yet — continue host wiring",
                fixHint: vmDetected ? nil : "Boot Apple VM / guest and re-run setup checklist"
            )
        )
        items.append(
            ChecklistItem(
                id: "gateway",
                title: "Hummingbird server",
                status: dryRun ? .skip : .pass,
                detail: dryRun ? "would start gateway (dry-run)" : "gateway start requested (foreground / visible)"
            )
        )
        items.append(
            ChecklistItem(
                id: "ui",
                title: "Visible status",
                status: menubarAvailable ? .pass : .warn,
                detail: menubarAvailable ? "menubar/floating bar path available" : "CLI status checklist"
            )
        )
        for snapshot in vault.snapshots {
            items.append(
                ChecklistItem(
                    id: "secret.\(snapshot.capability.rawValue)",
                    title: "Host secret \(snapshot.capability.rawValue)",
                    status: snapshot.configured ? .pass : .warn,
                    detail: snapshot.configured ? "configured" : "missing — shim will omit capability"
                )
            )
        }
        let guest = GuestMCPConfig.make(
            gatewayBaseURL: gatewayBaseURL,
            brokerToken: brokerToken,
            includeBrokerTokenInline: false
        )
        items.append(
            ChecklistItem(
                id: "guest.config",
                title: "Emit guest MCP config",
                status: .pass,
                detail: guest.url
            )
        )
        return SetupPlan(items: items, guestConfig: guest, dryRun: dryRun)
    }
}
