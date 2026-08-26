import SwiftUI

// MARK: - Add a model / Add an MCP server
//
// One three-step shell for both paths: pick → shape → verify. The verify step
// runs a real probe rather than claiming success, and the footer states what
// has and has not been committed yet.

public struct AddResourceSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @Bindable var model: OrchestratorModel
    let wizard: OrchestratorModel.Wizard

    private var spec: WizardSpec {
        wizard == .addModel ? .addModel : .addMCPServer
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            stepBar
            ScrollView {
                Group {
                    switch model.wizardStep {
                    case 0: pickStep
                    case 1: shapeStep
                    default: verifyStep
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            footer
        }
        .frame(width: 720, height: 620)
        .background(palette.chrome)
        .task(id: model.wizardStep) {
            guard model.wizardStep == 2 else { return }
            await model.runProbe(lineCount: spec.probe.count)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 12) {
            AndromedaMarkView(size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Kicker(spec.kind)
                Text(spec.title)
                    .font(OrchestratorFont.sans(14, .semibold))
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            Button("esc") { model.wizard = nil; dismiss() }
                .buttonStyle(ConsoleButtonStyle(kind: .quiet))
        }
        .padding(16)
        .background(palette.panel)
        .overlay(alignment: .bottom) { Divider().overlay(palette.hairline) }
    }

    private var stepBar: some View {
        HStack(spacing: 10) {
            ForEach(Array(spec.steps.enumerated()), id: \.offset) { index, label in
                let done = index < model.wizardStep
                let here = index == model.wizardStep
                HStack(spacing: 8) {
                    Text(done ? "●" : here ? "◐" : "○")
                        .font(OrchestratorFont.mono(10, .semibold))
                        .foregroundStyle(done ? palette.green : here ? palette.cyan : palette.dim)
                    Text("\(index + 1) \(label)")
                        .font(OrchestratorFont.mono(10, .semibold))
                        .foregroundStyle(here ? palette.ink : palette.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(here ? palette.cyan.opacity(0.09) : .clear, in: .rect(cornerRadius: 999))
                .overlay {
                    Capsule().strokeBorder(here ? palette.cyan.opacity(0.45) : palette.hairline, lineWidth: 1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.void)
        .overlay(alignment: .bottom) { Divider().overlay(palette.hairline) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(spec.footnote)
                .font(OrchestratorFont.mono(10.5))
                .foregroundStyle(palette.muted)
            Spacer()
            Button(model.wizardStep == 0 ? "CANCEL" : "BACK") {
                if model.wizardStep == 0 { model.wizard = nil; dismiss() }
                else { model.advanceWizard(by: -1) }
            }
            .buttonStyle(ConsoleButtonStyle(kind: .quiet))
            Button(commitLabel) {
                if model.wizardStep == 2 { model.wizard = nil; dismiss() }
                else { model.advanceWizard(by: 1) }
            }
            .buttonStyle(ConsoleButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(palette.panel)
        .overlay(alignment: .top) { Divider().overlay(palette.hairline) }
    }

    private var commitLabel: String {
        guard model.wizardStep == 2 else { return "CONTINUE" }
        return wizard == .addModel ? "PUBLISH ALIAS" : "IMPORT SERVER"
    }

    // MARK: Steps

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spec.pickHint)
                .font(OrchestratorFont.sans(12))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Text("›").font(OrchestratorFont.mono(10, .semibold)).foregroundStyle(palette.cyan)
                Text(spec.query).font(OrchestratorFont.mono(12)).foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .panel(radius: 9, fill: palette.void, border: palette.cyan.opacity(0.42))

            VStack(spacing: 0) {
                ForEach(Array(spec.candidates.enumerated()), id: \.offset) { index, candidate in
                    Button {
                        model.wizardSelection = index
                    } label: {
                        HStack(spacing: 12) {
                            Text(index == model.wizardSelection ? "◉" : candidate.status == .idle ? "○" : "◇")
                                .font(OrchestratorFont.mono(10, .semibold))
                                .foregroundStyle(index == model.wizardSelection ? palette.cyan : palette.dim)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.name)
                                    .font(OrchestratorFont.mono(12, .semibold))
                                    .foregroundStyle(palette.ink)
                                Text(candidate.detail)
                                    .font(OrchestratorFont.sans(11))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(candidate.meta)
                                .font(OrchestratorFont.mono(10))
                                .foregroundStyle(palette.muted)
                            StatusBadge(candidate.status, text: candidate.badge)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 11)
                        .background(index == model.wizardSelection ? palette.cyan.opacity(0.08) : .clear)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Divider().overlay(palette.hairline.opacity(0.6)) }
                    .entrance(index, step: 0.055)
                }
            }
            .panel(radius: 11)
        }
    }

    private var shapeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(Array(spec.fields.enumerated()), id: \.offset) { index, field in
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(field.label)
                        Text(field.value)
                            .font(OrchestratorFont.mono(12.5, .semibold))
                            .foregroundStyle(field.highlighted ? palette.cyan : palette.ink)
                            .lineLimit(1)
                        Text(field.hint)
                            .font(OrchestratorFont.sans(10.5))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(radius: 10)
                    .entrance(index, step: 0.07)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Kicker(spec.chipsLabel)
                FlowLayout(spacing: 7) {
                    ForEach(spec.chips, id: \.self) { chip in
                        let withheld = model.withheldScopes.contains(chip)
                        Button { model.toggleScope(chip) } label: {
                            HStack(spacing: 7) {
                                Text(withheld ? "○" : "●").font(OrchestratorFont.mono(10))
                                Text(chip).font(OrchestratorFont.mono(10.5))
                            }
                            .foregroundStyle(withheld ? palette.dim : palette.cyan)
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(withheld ? .clear : palette.cyan.opacity(0.1), in: .rect(cornerRadius: 999))
                            .overlay {
                                Capsule().strokeBorder(withheld ? palette.hairline : palette.cyan.opacity(0.45), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chip), \(withheld ? "withheld" : "granted")")
                    }
                }
                Text(spec.chipsHint)
                    .font(OrchestratorFont.sans(10.5))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 11, fill: palette.void)
        }
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(spec.probe.enumerated()), id: \.offset) { index, line in
                    let done = index < model.probeProgress
                    let active = index == model.probeProgress
                    HStack(spacing: 10) {
                        Text(done ? "●" : active ? "◐" : "○")
                            .font(OrchestratorFont.mono(10.5))
                            .foregroundStyle(done ? palette.green : active ? palette.cyan : palette.dim)
                        Text(line.0)
                            .font(OrchestratorFont.mono(11))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text(done ? line.1 : active ? "…" : "")
                            .font(OrchestratorFont.mono(11))
                            .foregroundStyle(palette.muted)
                            .monospacedDigit()
                    }
                    .opacity(done || active ? 1 : 0.34)
                    .animation(OrchestratorMotion.settle, value: model.probeProgress)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 11, fill: palette.void)

            let finished = model.probeProgress >= spec.probe.count
            HStack(spacing: 10) {
                ForEach(Array(spec.results.enumerated()), id: \.offset) { _, result in
                    VStack(alignment: .leading, spacing: 5) {
                        Kicker(result.label)
                        Text(finished ? result.value : "—")
                            .font(OrchestratorFont.mono(14, .semibold))
                            .foregroundStyle(finished ? (result.good ? palette.green : palette.cyan) : palette.dim)
                            .contentTransition(.numericText())
                        Text(result.note)
                            .font(OrchestratorFont.sans(10.5))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(radius: 10, fill: finished ? nil : palette.void)
                }
            }
            .animation(OrchestratorMotion.entrance, value: finished)

            HStack(spacing: 9) {
                Text("◈").font(OrchestratorFont.mono(11, .semibold)).foregroundStyle(palette.cyan)
                Text(spec.curtain)
                    .font(OrchestratorFont.sans(11.5))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 10, fill: palette.cyan.opacity(0.07), border: palette.cyan.opacity(0.35))
        }
    }
}

// MARK: - Wizard content

struct WizardSpec: Sendable {
    struct Candidate: Sendable {
        var name: String
        var detail: String
        var meta: String
        var badge: String
        var status: OrchestratorStatus
    }
    struct Field: Sendable {
        var label: String
        var value: String
        var hint: String
        var highlighted = false
    }
    struct Result: Sendable {
        var label: String
        var value: String
        var note: String
        var good = false
    }

    var kind: String
    var title: String
    var steps: [String]
    var pickHint: String
    var query: String
    var candidates: [Candidate]
    var fields: [Field]
    var chipsLabel: String
    var chips: [String]
    var chipsHint: String
    var probe: [(String, String)]
    var results: [Result]
    var curtain: String
    var footnote: String

    static let addModel = WizardSpec(
        kind: "Providers & models",
        title: "Add a model",
        steps: ["Pick model", "Alias & routing", "Probe"],
        pickHint: "Andromeda lists only what your keys can actually reach — no menu of models that 401 on first call.",
        query: "claude-sonnet",
        candidates: [
            .init(name: "claude-sonnet-4.5", detail: "anthropic · 200k context · vision · tools", meta: "$3.00 / $15.00", badge: "REACHABLE", status: .healthy),
            .init(name: "claude-haiku-4.5", detail: "anthropic · 200k context · fastest", meta: "$0.80 / $4.00", badge: "REACHABLE", status: .healthy),
            .init(name: "claude-sonnet-4.5 (bedrock)", detail: "bedrock · us-west-2 · same weights", meta: "$3.30 / $16.50", badge: "REACHABLE", status: .healthy),
            .init(name: "gpt-5.1", detail: "openai · 400k context · responses native", meta: "$2.50 / $10.00", badge: "BREAKER OPEN", status: .degraded),
            .init(name: "qwen3-14b", detail: "ollama · 127.0.0.1:11434 · local weights", meta: "free", badge: "LOCAL", status: .healthy),
            .init(name: "grok-4.5", detail: "xai · no key in Keychain", meta: "—", badge: "NO KEY", status: .idle),
        ],
        fields: [
            .init(label: "Alias clients will call", value: "sonnet-latest", hint: "Stable name. Swap the target underneath without touching a client.", highlighted: true),
            .init(label: "Fallback ladder", value: "bedrock → openai → ollama", hint: "Cross-vendor hops translate request shape automatically."),
            .init(label: "Prompt cache", value: "auto breakpoints", hint: "Gateway injects cache_control and reports ROI per alias."),
            .init(label: "Budget guard", value: "$180 / day", hint: "Soft warn at 80%, shed to haiku-fast at 100%."),
        ],
        chipsLabel: "Capabilities this alias advertises",
        chips: ["reasoning", "vision", "tools", "cache", "json-mode", "long-context"],
        chipsHint: "Agents request capabilities, never brands. Unchecked capabilities are refused at the gateway, not at the provider.",
        probe: [
            ("resolve anthropic.api · TLS pinned", "38ms"),
            ("secret proxy:anthropic_key ← Keychain (broker only)", "6ms"),
            ("POST /v1/messages · 1 token probe", "412ms"),
            ("translate shape → /v1/responses", "2ms"),
            ("translate shape → /v1/chat/completions", "2ms"),
            ("inject cache breakpoint · 2 blocks", "1ms"),
            ("register alias sonnet-latest", "4ms"),
        ],
        results: [
            .init(label: "p95", value: "412ms", note: "gateway adds 3ms"),
            .init(label: "dialects", value: "3 / 3", note: "messages · responses · completions"),
            .init(label: "cache", value: "eligible", note: "est. 34% hit, −$61/day", good: true),
        ],
        curtain: "Clients see sonnet-latest. They never see the provider brand, the key, or the fallback ladder behind it.",
        footnote: "Nothing is published until you commit — the probe used one token."
    )

    static let addMCPServer = WizardSpec(
        kind: "MCP host",
        title: "Add an MCP server",
        steps: ["Source", "Scopes & secrets", "Handshake"],
        pickHint: "Paste a command or URL, or take one from the catalogue. It runs as one supervised child of the host — never a fresh npx per terminal.",
        query: "npx @modelcontextprotocol/server-github",
        candidates: [
            .init(name: "github", detail: "npx @modelcontextprotocol/server-github · stdio", meta: "14 tools", badge: "IN 3 CONFIGS", status: .degraded),
            .init(name: "postgres", detail: "https://mcp.internal/pg · http", meta: "5 tools", badge: "NEW", status: .healthy),
            .init(name: "sentry", detail: "https://mcp.sentry.dev · http", meta: "6 tools", badge: "NEW", status: .healthy),
            .init(name: "notion", detail: "npx @notionhq/mcp · stdio", meta: "11 tools", badge: "NEW", status: .healthy),
            .init(name: "filesystem (cursor copy)", detail: "cursor/mcp.json · unpinned npx, no scopes", meta: "7 tools", badge: "DUPLICATE", status: .idle),
        ],
        fields: [
            .init(label: "Transport", value: "stdio · supervised", hint: "Host owns the process. Crash loops back off instead of multiplying.", highlighted: true),
            .init(label: "Restart policy", value: "restart · backoff 2s → 30s", hint: "Six zombie instances was the old default. This is the new one."),
            .init(label: "Secret binding", value: "proxy:github_token", hint: "Resolved from Keychain at call time. Never written to agent env."),
            .init(label: "Sandbox", value: "~/dev · read, write scoped", hint: "Paths outside the sandbox are refused before the tool runs."),
        ],
        chipsLabel: "Tool scopes to expose",
        chips: ["repo:read", "issues:write", "pr:write", "actions:read", "gists:write", "delete:repo"],
        chipsHint: "Tap to withhold a scope. Withheld tools disappear from every client's tool list — they are not merely refused at call time.",
        probe: [
            ("spawn child · pid 41822", "82ms"),
            ("initialize · protocol 2025-06-18", "36ms"),
            ("tools/list → 14 tools", "44ms"),
            ("dedupe 2 copies from cursor/mcp.json, codex.toml", "8ms"),
            ("bind secret proxy:github_token", "5ms"),
            ("health probe github.search_code", "184ms"),
            ("register in one registry · all clients", "3ms"),
        ],
        results: [
            .init(label: "tools", value: "14", note: "12 exposed, 2 withheld"),
            .init(label: "duplicates", value: "2 removed", note: "3 configs → 1 registry", good: true),
            .init(label: "p95", value: "184ms", note: "health probe green"),
        ],
        curtain: "Clients call github.search_code. The token stays in the broker and the agent environment stays scrubbed.",
        footnote: "Import writes one registry entry, then rewrites the client configs to point at the host."
    )
}

#Preview("Add a model") {
    let model = OrchestratorModel(firstRun: false)
    return AddResourceSheet(model: model, wizard: .addModel)
        .orchestratorPalette()
}

#Preview("Add an MCP server · light") {
    let model = OrchestratorModel(firstRun: false)
    model.wizardStep = 1
    return AddResourceSheet(model: model, wizard: .addMCPServer)
        .environment(\.colorScheme, .light)
        .orchestratorPalette()
}
