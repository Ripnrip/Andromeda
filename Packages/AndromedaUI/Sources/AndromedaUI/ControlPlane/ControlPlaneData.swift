import SwiftUI

// MARK: - Control-plane domain

/// Honesty status — never greenwashed.
public enum PillarStatus: String, CaseIterable, Sendable {
    case shipped, partial, specified, live
    public var label: String {
        switch self {
        case .shipped:   return "✅ shipped"
        case .partial:   return "🚧 partial"
        case .specified: return "📐 specified"
        case .live:      return "✅ shipped"
        }
    }
    public var dot: String { self == .partial ? "partial" : self == .specified ? "spec" : "live" }
    public var color: Color {
        switch self {
        case .shipped, .live: return .andromedaLive
        case .partial:        return .andromedaAmber
        case .specified:      return .andromedaDim
        }
    }
}

/// The seven capabilities + settings.
public enum Pillar: String, CaseIterable, Identifiable, Sendable {
    case memory, mcp, skills, models, secrets, fleet, search, settings
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .memory: return "Memory · Anima"
        case .mcp: return "MCP host"
        case .skills: return "Skills registry"
        case .models: return "LLM proxy"
        case .secrets: return "Secrets broker"
        case .fleet: return "Fleet runtime"
        case .search: return "Ask Andromeda"
        case .settings: return "Settings"
        }
    }
    public var capabilityID: String {
        switch self {
        case .memory: return "memory.recall"
        case .mcp: return "mcp.host"
        case .skills: return "skills.invoke"
        case .models: return "infer.write"
        case .secrets: return "secrets.broker"
        case .fleet: return "fleet.pulse"
        case .search: return "search.ask"
        case .settings: return "system.admin"
        }
    }
    public var symbol: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .skills: return "sparkles"
        case .models: return "cpu"
        case .secrets: return "lock.shield"
        case .fleet: return "waveform.path.ecg"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
    public var status: PillarStatus {
        switch self {
        case .memory, .mcp, .models, .fleet: return .partial
        case .skills, .secrets: return .specified
        case .search, .settings: return .live
        }
    }
    public var blurb: String {
        switch self {
        case .memory: return "The salience-ranked working set behind the curtain — SwiftData hot store, vault, and vector recall. Clients call recall/store; Andromeda resolves the index."
        case .mcp: return "One consolidated host for Model-Context-Protocol servers — observed, deduped, surfaced as capabilities instead of 50× npm exec per studio."
        case .skills: return "Every agent skill invoked by stable id from one registry surface — no tribal hunting through ~/.claude/skills."
        case .models: return "The model registry, speed board, health and routing behind infer.write. Clients never pick a provider or hold a key."
        case .secrets: return "Keychain-backed vault. Capability IDs in, secrets injected server-side at call time — raw values never touch a client process."
        case .fleet: return "LaunchAgents, health, and telemetry as first-class entities — one auditable roster and pulse instead of scattered plists."
        case .search: return "Ask about Andromeda's own internals, or run real external web search — same surface, two very different sources."
        case .settings: return "Install, diagnose and maintain the local control plane — all Swift, no hybrid bash reopen."
        }
    }
}

// MARK: - Row models

/// Stable demo identity helpers — avoid `UUID()` stored properties in static catalogs
/// (non-deterministic + Swift 6 Sendable friction).
public struct CapabilityItem: Identifiable {
    public var id: String { ref }
    public let name, ref, desc, status: String
    public let statusColor: Color
    public let metrics: [(String, String)]
    public init(_ name: String, _ ref: String, _ desc: String, _ status: String, _ statusColor: Color, _ metrics: [(String, String)]) {
        self.name = name; self.ref = ref; self.desc = desc; self.status = status; self.statusColor = statusColor; self.metrics = metrics
    }
}

public struct ModelRow: Identifiable {
    public var id: String { name }
    public let name, tier: String
    public let tierColor: Color
    public init(_ name: String, _ tier: String, _ tierColor: Color) {
        self.name = name; self.tier = tier; self.tierColor = tierColor
    }
}

public struct SpeedRow: Identifiable {
    public var id: String { rank + ":" + name }
    public let rank, name, latency, tps: String
    public init(_ rank: String, _ name: String, _ latency: String, _ tps: String) {
        self.rank = rank; self.name = name; self.latency = latency; self.tps = tps
    }
}

public struct MemChange: Identifiable {
    public var id: String { time + "|" + author + "|" + text }
    public let author, time, text: String
    public let dreaming: Bool
    public init(_ author: String, _ time: String, _ text: String, dreaming: Bool = false) {
        self.author = author; self.time = time; self.text = text; self.dreaming = dreaming
    }
}

public struct MemLayer: Identifiable {
    public var id: String { key }
    public let key, name, kind, count, path, detail: String
    public init(_ key: String, _ name: String, _ kind: String, _ count: String, _ path: String, _ detail: String) {
        self.key = key; self.name = name; self.kind = kind; self.count = count; self.path = path; self.detail = detail
    }
}

public enum ControlPlaneData {
    public static let models: [ModelRow] = [
        .init("claude-DeepSeek-V4-Flash", "fast", .andromedaLive),
        .init("claude-DeepSeek-V4-Pro", "deep", .andromedaTeal),
        .init("claude-FW-GLM-5.2", "deep", .andromedaTeal),
        .init("claude-grok-4.5", "deep", .andromedaTeal),
        .init("claude-haiku-4-5", "fast", .andromedaLive),
        .init("claude-Kimi-K2.7-Code", "code", .andromedaAmber),
        .init("claude-opus-4-8", "deep", .andromedaTeal),
        .init("gpt-4o-mini", "fast", .andromedaLive),
    ]
    public static let speed: [SpeedRow] = [
        .init("1", "gpt-4o-mini", "919ms", "145 t/s"),
        .init("2", "gpt-4.1-mini", "1212ms", "135 t/s"),
        .init("3", "claude-haiku-4-5", "1629ms", "54 t/s"),
        .init("4", "gemini-2.5-flash-lite", "1998ms", "12 t/s"),
        .init("5", "gemini-3.1-flash-lite", "1998ms", "103 t/s"),
        .init("6", "gpt-oss-20b", "3424ms", "135 t/s"),
    ]
    public static let changes: [MemChange] = [
        .init("Berserker", "3m ago", "Record snapshot policy preference for non-visual PRs"),
        .init("Dreaming", "6d ago", "feat(reflection): update dream-state for sweeps #127–#137", dreaming: true),
        .init("Berserker", "5d ago", "docs: add encrypted memory-broker plan to pending-work"),
        .init("Dreaming", "5d ago", "fix(reflection): sync test count 151 and finalize docs", dreaming: true),
        .init("Berserker", "6d ago", "fix: update dream-state model reference"),
    ]
    public static let layers: [MemLayer] = [
        .init("swiftdata", "SwiftData", "hot store", "151 blocks", "~/Andromeda/anima.store", "In-memory + on-disk hot working set. First hop for memory.recall before vault or vector recall."),
        .init("realm", "RealmDB", "core blocks", "42 blocks", "realm://anima/core", "Letta-style editable core memory blocks — persona, human, project. Live-editable and versioned."),
        .init("outbox", "Outbox", "write queue", "7 pending", "outbox://anima", "Durable, ordered write queue. memory.store enqueues here; drained to stores + vector index exactly once."),
        .init("qdrant", "Qdrant", "archival", "18.4k passages", "qdrant://anima/passages", "Vector archival memory. Semantic recall over passages, salience-ranked — the archival analog to Letta."),
        .init("vault", "Vault", "sealed", "12 secrets", "keychain://andromeda", "Keychain-backed secrets, brokered server-side at call time. Never exposed to a client process env."),
    ]
    public static func items(for p: Pillar) -> [CapabilityItem] {
        switch p {
        case .mcp: return [
            .init("filesystem", "mcp://local/fs", "Local filesystem tools — read, write, glob. Deduped to one host process.", "live", .andromedaLive, [("9", "tools"), ("1", "process")]),
            .init("source control", "mcp://scm", "Repo browse, diff and PR tools surfaced as capabilities — brand hidden.", "live", .andromedaLive, [("12", "tools"), ("1", "process")]),
            .init("relational db", "mcp://db/pg", "Query + schema introspection. Shared lifecycle host not yet fully shipped.", "partial", .andromedaAmber, [("6", "tools"), ("2", "process")]),
            .init("browser", "mcp://web/pw", "Playwright automation. Orphan-process pressure watched by fleet pulse.", "partial", .andromedaAmber, [("14", "tools"), ("3", "process")]),
        ]
        case .skills: return [
            .init("make.deck", "skills.invoke/deck", "Compose a slide deck from a brief. Invoked by id from the registry.", "live", .andromedaLive, [("v2.1", "version"), ("240ms", "p50")]),
            .init("web.research", "skills.invoke/research", "Grounded findings with live sources, streamed back to the caller.", "live", .andromedaLive, [("v1.4", "version"), ("streamed", "mode")]),
            .init("image.compose", "skills.invoke/image", "Layout + placeholder imagery. Registry entity specified, not built.", "spec", .andromedaDim, [("v0.9", "version"), ("beta", "stage")]),
            .init("pdf.read", "skills.invoke/pdf", "Extract structured text and assets from PDFs for downstream skills.", "live", .andromedaLive, [("v1.2", "version"), ("180ms", "p50")]),
        ]
        case .secrets: return [
            .init("provider key · reasoning", "secrets.broker/infer", "Injected server-side at call time. Client never sees the raw value.", "spec", .andromedaDim, [("sk-••a91", "masked"), ("keychain", "backing")]),
            .init("scm token", "secrets.broker/scm", "Powers github_proxy. Env-scrubbed agents get HOME + PATH only.", "spec", .andromedaDim, [("ghp-••4d2", "masked"), ("keychain", "backing")]),
            .init("slack token", "secrets.broker/slack", "Powers slack_proxy via broker — never SLACK_BOT_TOKEN in process env.", "spec", .andromedaDim, [("xoxb-••", "masked"), ("keychain", "backing")]),
            .init("db dsn", "secrets.broker/db", "Connection string sealed in vault; brokered to db capability only.", "spec", .andromedaDim, [("postgres://••", "masked"), ("vault", "backing")]),
        ]
        case .fleet: return [
            .init("node · atlas", "fleet.pulse/atlas", "LaunchAgent roster host. last_success 40s ago.", "healthy", .andromedaLive, [("34%", "cpu"), ("51%", "mem")]),
            .init("node · vega", "fleet.pulse/vega", "Telemetry hub + observability. Spend / kill switches armed.", "healthy", .andromedaLive, [("61%", "cpu"), ("72%", "mem")]),
            .init("node · rigel", "fleet.pulse/rigel", "Reconnecting — MCP process pressure high; watchdog restarting.", "degraded", .andromedaAmber, [("—", "cpu"), ("—", "mem")]),
            .init("scheduler", "fleet.pulse/cron", "launchd timers for sweeps + dreaming reflections.", "healthy", .andromedaLive, [("7", "agents"), ("0", "failed")]),
        ]
        default: return []
        }
    }
}
