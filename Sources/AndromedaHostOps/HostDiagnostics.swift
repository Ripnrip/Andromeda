import AndromedaSecrets
import Foundation

/// Snapshot of whether a Keychain reference resolves — never carries secret bytes.
public struct SecretPresence: Sendable, Equatable {
    public let reference: SecretReference
    public let present: Bool
    public let label: String

    public init(reference: SecretReference, present: Bool, label: String) {
        self.reference = reference
        self.present = present
        self.label = label
    }
}

/// Pure checklist builders for host-first setup / doctor — no process mutation, safe for tests.
public enum HostDiagnostics {
    /// Curated tool names the VM must see (and only these) after M4.
    public static let curatedToolNames: Set<String> = [
        "andromeda_github_get_me",
        "andromeda_github_request",
        "andromeda_slack_post_message",
        "andromeda_slack_request",
    ]

    /// Builds a doctor report from host observations.
    public static func doctor(
        runtimeReachable: Bool,
        brokerTokenConfigured: Bool,
        secrets: [SecretPresence],
        qdrantReachable: Bool?,
        journalPathExists: Bool,
        vaultPathExists: Bool,
        guestConfigText: String?,
        toolsListNames: Set<String>?,
        vmSignalDetected: Bool,
        menubarAvailable: Bool
    ) -> DoctorReport {
        var items: [ChecklistItem] = []

        items.append(
            ChecklistItem(
                id: "runtime.health",
                title: "Runtime HTTP health",
                status: runtimeReachable ? .pass : .fail,
                detail: runtimeReachable ? "reachable" : "not reachable",
                fixHint: runtimeReachable ? nil : "Run `andromeda-runtime serve` on the host (visible foreground)"
            )
        )

        items.append(
            ChecklistItem(
                id: "broker.token",
                title: "MCP bearer token",
                status: brokerTokenConfigured ? .pass : .fail,
                detail: brokerTokenConfigured ? "configured" : "missing",
                fixHint: brokerTokenConfigured ? nil : "Set ANDROMEDA_MCP_BEARER_TOKEN on the host"
            )
        )

        for secret in secrets {
            items.append(
                ChecklistItem(
                    id: "secret.\(secret.label)",
                    title: "Keychain \(secret.label)",
                    status: secret.present ? .pass : .warn,
                    detail: secret.present
                        ? "present (\(secret.reference.service)/\(secret.reference.account))"
                        : "missing (\(secret.reference.service)/\(secret.reference.account))",
                    fixHint: secret.present
                        ? nil
                        : "Seed with `andromeda-runtime setup --fix` (token never printed)"
                )
            )
        }

        if let qdrantReachable {
            items.append(
                ChecklistItem(
                    id: "projection.qdrant",
                    title: "Qdrant projection",
                    status: qdrantReachable ? .pass : .warn,
                    detail: qdrantReachable ? "reachable" : "unreachable",
                    fixHint: qdrantReachable ? nil : "Start Qdrant or set ANDROMEDA_TEST_QDRANT_URL / --qdrant-url"
                )
            )
        } else {
            items.append(
                ChecklistItem(
                    id: "projection.qdrant",
                    title: "Qdrant projection",
                    status: .skip,
                    detail: "not probed"
                )
            )
        }

        items.append(
            ChecklistItem(
                id: "memory.journal",
                title: "Journal path",
                status: journalPathExists ? .pass : .warn,
                detail: journalPathExists ? "exists" : "missing — will be created on serve",
                fixHint: journalPathExists ? nil : "Pass --journal-path to serve, or run setup --fix"
            )
        )

        items.append(
            ChecklistItem(
                id: "memory.vault",
                title: "Vault directory",
                status: vaultPathExists ? .pass : .warn,
                detail: vaultPathExists ? "exists" : "missing — will be created on serve",
                fixHint: vaultPathExists ? nil : "Pass --vault-dir to serve, or run setup --fix"
            )
        )

        if let guestConfigText {
            let dirty = GuestMCPConfig.containsUpstreamSecrets(guestConfigText)
            items.append(
                ChecklistItem(
                    id: "guest.mcp",
                    title: "Guest MCP config scrub",
                    status: dirty ? .fail : .pass,
                    detail: dirty ? "contains upstream secret markers" : "no upstream secrets detected",
                    fixHint: dirty
                        ? "Regenerate with `andromeda-runtime setup` — remove Slack/GitHub tokens from guest mcp.json"
                        : nil
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

        if let toolsListNames {
            let unexpected = toolsListNames.subtracting(curatedToolNames)
            let missing = curatedToolNames.subtracting(toolsListNames)
            if !unexpected.isEmpty {
                items.append(
                    ChecklistItem(
                        id: "mcp.tools",
                        title: "Curated tools/list",
                        status: .fail,
                        detail: "unexpected tools: \(unexpected.sorted().joined(separator: ", "))",
                        fixHint: "Ensure only curated andromeda_* tools are registered"
                    )
                )
            } else if !missing.isEmpty {
                items.append(
                    ChecklistItem(
                        id: "mcp.tools",
                        title: "Curated tools/list",
                        status: .warn,
                        detail: "missing tools: \(missing.sorted().joined(separator: ", "))",
                        fixHint: "Configure GitHub/Slack Keychain refs and restart serve with --mcp-bearer-token"
                    )
                )
            } else {
                items.append(
                    ChecklistItem(
                        id: "mcp.tools",
                        title: "Curated tools/list",
                        status: .pass,
                        detail: "exactly \(curatedToolNames.count) curated andromeda_* tools"
                    )
                )
            }
        } else {
            items.append(
                ChecklistItem(
                    id: "mcp.tools",
                    title: "Curated tools/list",
                    status: .skip,
                    detail: "MCP not probed (runtime down or no bearer)"
                )
            )
        }

        items.append(
            ChecklistItem(
                id: "vm.signal",
                title: "Guest VM signal",
                status: vmSignalDetected ? .pass : .warn,
                detail: vmSignalDetected ? "VM/guest signal detected" : "no VM detected yet",
                fixHint: vmSignalDetected ? nil : "Boot Apple VM / guest and re-run doctor"
            )
        )

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

    /// Builds a setup plan (idempotent checklist + guest config).
    public static func setupPlan(
        secrets: [SecretPresence],
        brokerTokenConfigured: Bool,
        runtimeBaseURL: String,
        journalPathExists: Bool,
        vaultPathExists: Bool,
        vmSignalDetected: Bool,
        dryRun: Bool,
        menubarAvailable: Bool
    ) -> SetupPlan {
        var items: [ChecklistItem] = []

        items.append(
            ChecklistItem(
                id: "host.entrypoint",
                title: "Host entrypoint",
                status: .pass,
                detail: "setup starts on host (not guest)"
            )
        )

        items.append(
            ChecklistItem(
                id: "vm.detect",
                title: "Guest VM signal",
                status: vmSignalDetected ? .pass : .warn,
                detail: vmSignalDetected ? "VM/guest signal detected" : "no VM detected yet — continue host wiring",
                fixHint: vmSignalDetected ? nil : "Boot Apple VM / guest and re-run setup checklist"
            )
        )

        items.append(
            ChecklistItem(
                id: "broker.token",
                title: "MCP bearer token",
                status: brokerTokenConfigured ? .pass : .fail,
                detail: brokerTokenConfigured ? "configured" : "missing",
                fixHint: brokerTokenConfigured ? nil : "Export ANDROMEDA_MCP_BEARER_TOKEN before serve"
            )
        )

        for secret in secrets {
            items.append(
                ChecklistItem(
                    id: "secret.\(secret.label)",
                    title: "Host Keychain \(secret.label)",
                    status: secret.present ? .pass : .warn,
                    detail: secret.present
                        ? "configured (\(secret.reference.service)/\(secret.reference.account))"
                        : "missing — run with --fix to seed from env (never printed)"
                )
            )
        }

        items.append(
            ChecklistItem(
                id: "memory.journal",
                title: "Journal path",
                status: journalPathExists ? .pass : (dryRun ? .skip : .warn),
                detail: journalPathExists
                    ? "ready"
                    : (dryRun ? "would create parent dirs (dry-run)" : "will create parent dirs with --fix")
            )
        )

        items.append(
            ChecklistItem(
                id: "memory.vault",
                title: "Vault directory",
                status: vaultPathExists ? .pass : (dryRun ? .skip : .warn),
                detail: vaultPathExists
                    ? "ready"
                    : (dryRun ? "would create vault dir (dry-run)" : "will create vault dir with --fix")
            )
        )

        items.append(
            ChecklistItem(
                id: "ui.status",
                title: "Visible status",
                status: menubarAvailable ? .pass : .warn,
                detail: menubarAvailable ? "menubar/floating bar path available" : "CLI status checklist"
            )
        )

        let guest = GuestMCPConfig.make(
            runtimeBaseURL: runtimeBaseURL,
            brokerToken: nil,
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

        items.append(
            ChecklistItem(
                id: "runtime.next",
                title: "Start runtime",
                status: dryRun ? .skip : .pass,
                detail: dryRun
                    ? "would start andromeda-runtime serve (dry-run)"
                    : "next: run `andromeda-runtime serve` in the foreground (visible)"
            )
        )

        return SetupPlan(items: items, guestConfig: guest, dryRun: dryRun)
    }
}
