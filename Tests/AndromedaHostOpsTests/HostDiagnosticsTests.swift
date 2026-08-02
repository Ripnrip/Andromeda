import AndromedaHostOps
import AndromedaSecrets
import Foundation
import Testing

@Suite("HostDiagnostics")
struct HostDiagnosticsTests {
    /// Builds a complete doctor report and asserts exit code + key rows.
    @Test("doctor fails closed when runtime and broker are missing")
    func doctorFailsClosed() {
        let report = HostDiagnostics.doctor(
            runtimeReachable: false,
            brokerTokenConfigured: false,
            secrets: [
                SecretPresence(
                    reference: SecretReference(service: "andromeda.github", account: "token"),
                    present: false,
                    label: "github"
                ),
            ],
            qdrantReachable: false,
            journalPathExists: false,
            vaultPathExists: false,
            guestConfigText: nil,
            toolsListNames: nil,
            vmSignalDetected: false,
            menubarAvailable: false
        )
        #expect(report.exitCode == 1)
        #expect(report.failedCount >= 2)
        #expect(report.items.contains { $0.id == "runtime.health" && $0.status == .fail })
        #expect(report.items.contains { $0.id == "broker.token" && $0.status == .fail })
    }

    /// Happy-path doctor: runtime up, curated tools exact, guest config clean.
    @Test("doctor passes when curated tools match and guest config is clean")
    func doctorPassesWhenHealthy() {
        let guest = GuestMCPConfig.make(runtimeBaseURL: "http://studio:8788", brokerToken: nil)
        let json = try! guest.renderMCPJSON()
        let report = HostDiagnostics.doctor(
            runtimeReachable: true,
            brokerTokenConfigured: true,
            secrets: [
                SecretPresence(
                    reference: SecretReference(service: "andromeda.github", account: "token"),
                    present: true,
                    label: "github"
                ),
                SecretPresence(
                    reference: SecretReference(service: "andromeda.slack", account: "token"),
                    present: true,
                    label: "slack"
                ),
            ],
            qdrantReachable: true,
            journalPathExists: true,
            vaultPathExists: true,
            guestConfigText: json,
            toolsListNames: HostDiagnostics.curatedToolNames,
            vmSignalDetected: true,
            menubarAvailable: true
        )
        #expect(report.exitCode == 0)
        #expect(report.failedCount == 0)
        #expect(report.items.contains { $0.id == "mcp.tools" && $0.status == .pass })
        #expect(report.items.contains { $0.id == "guest.mcp" && $0.status == .pass })
    }

    /// Unexpected extra tools must fail the curated-surface check.
    @Test("doctor fails when tools/list exposes unexpected names")
    func doctorFailsOnUnexpectedTools() {
        var names = HostDiagnostics.curatedToolNames
        names.insert("raw_github_api")
        let report = HostDiagnostics.doctor(
            runtimeReachable: true,
            brokerTokenConfigured: true,
            secrets: [],
            qdrantReachable: nil,
            journalPathExists: true,
            vaultPathExists: true,
            guestConfigText: nil,
            toolsListNames: names,
            vmSignalDetected: false,
            menubarAvailable: false
        )
        #expect(report.items.contains { $0.id == "mcp.tools" && $0.status == .fail })
        #expect(report.exitCode == 1)
    }

    /// Guest config scrub must catch upstream token markers.
    @Test("doctor fails guest scrub when upstream secret markers are present")
    func doctorScrubsGuestSecrets() {
        let dirty = #"{"mcpServers":{"andromeda":{"url":"http://x/mcp","headers":{"Authorization":"Bearer ghp_leak"}}}}"#
        let report = HostDiagnostics.doctor(
            runtimeReachable: true,
            brokerTokenConfigured: true,
            secrets: [],
            qdrantReachable: nil,
            journalPathExists: true,
            vaultPathExists: true,
            guestConfigText: dirty,
            toolsListNames: nil,
            vmSignalDetected: false,
            menubarAvailable: false
        )
        #expect(report.items.contains { $0.id == "guest.mcp" && $0.status == .fail })
    }
}

@Suite("GuestMCPConfig")
struct GuestMCPConfigTests {
    /// Guest fragment must target /mcp and never embed upstream env keys.
    @Test("guest mcp.json points at /mcp without upstream secret markers")
    func guestConfigIsKeyless() throws {
        let guest = GuestMCPConfig.make(runtimeBaseURL: "http://100.64.0.1:8788/", brokerToken: "should-not-inline")
        let json = try guest.renderMCPJSON()
        #expect(guest.url.hasSuffix("/mcp"))
        #expect(json.contains("ANDROMEDA_MCP_BEARER_TOKEN"))
        #expect(!GuestMCPConfig.containsUpstreamSecrets(json))
        #expect(!json.contains("should-not-inline"))
        #expect(!json.contains("GITHUB_TOKEN"))
        #expect(!json.contains("SLACK_BOT_TOKEN"))
    }

    /// Idempotent URL builder must not double-append /mcp.
    @Test("make does not double-append /mcp")
    func noDoubleMCP() {
        let guest = GuestMCPConfig.make(runtimeBaseURL: "http://host:8788/mcp", brokerToken: nil)
        #expect(guest.url == "http://host:8788/mcp")
    }
}

@Suite("SetupPlan")
struct SetupPlanTests {
    /// Setup plan always starts on the host and emits a guest endpoint.
    @Test("setup plan is host-first and emits guest endpoint")
    func setupPlanHostFirst() {
        let plan = HostDiagnostics.setupPlan(
            secrets: [
                SecretPresence(
                    reference: SecretReference(service: "andromeda.github", account: "token"),
                    present: false,
                    label: "github"
                ),
            ],
            brokerTokenConfigured: true,
            runtimeBaseURL: "http://studio.tailnet:8788",
            journalPathExists: false,
            vaultPathExists: false,
            vmSignalDetected: false,
            dryRun: true,
            menubarAvailable: false
        )
        #expect(plan.items.contains { $0.id == "host.entrypoint" && $0.status == .pass })
        #expect(plan.guestConfig.url.contains("/mcp"))
        let rendered = plan.render()
        #expect(rendered.contains("dry-run"))
        #expect(rendered.contains("Guest MCP endpoint"))
    }
}

@Suite("KeychainPresenceChecker")
struct KeychainPresenceCheckerTests {
    /// Injectable runner proves presence checks never need secret bytes.
    @Test("presence checker uses injectable runner")
    func injectablePresence() {
        let checker = KeychainPresenceChecker(runner: .init { service, account in
            service == "andromeda.github" && account == "token"
        })
        #expect(checker.isPresent(SecretReference(service: "andromeda.github", account: "token")))
        #expect(!checker.isPresent(SecretReference(service: "andromeda.slack", account: "token")))
    }
}

@Suite("GuestSignalDetector")
struct GuestSignalDetectorTests {
    /// Env override must win for CI / scripted checklists.
    @Test("env override detects guest signal")
    func envOverride() {
        #expect(GuestSignalDetector.detect(environment: ["ANDROMEDA_VM_DETECTED": "1"]))
        #expect(!GuestSignalDetector.detect(environment: ["ANDROMEDA_VM_DETECTED": "0"]))
        #expect(GuestSignalDetector.detect(environment: ["ANDROMEDA_VM_SSH_HOST": "agent-habitat"]))
    }
}
