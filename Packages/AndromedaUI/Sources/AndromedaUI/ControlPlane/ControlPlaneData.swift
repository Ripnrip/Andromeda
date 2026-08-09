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
        case .models: return "infer.write"
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
        case .memory, .mcp, .fleet: return .partial
        case .skills, .secrets, .models: return .specified
        case .search, .settings: return .live
        }
    }
    public var blurb: String {
        switch self {
        case .memory: return "The salience-ranked working set behind the curtain — SwiftData is the shipped hot store. Clients call recall/store; Andromeda owns routing."
        case .mcp: return "One consolidated host for Model-Context-Protocol servers — observed, deduped, surfaced as capabilities instead of 50× npm exec per studio."
        case .skills: return "Every agent skill invoked by stable id from one registry surface — no tribal hunting through ~/.claude/skills."
        case .models: return "infer.write is a stable client id. Today it aliases episodic-store write — not model generation. Real proxy routing is specified, not shipped."
        case .secrets: return "Capability IDs in, secrets injected server-side at call time — raw values never touch a client process."
        case .fleet: return "LaunchAgents, health, and telemetry as first-class entities — one auditable roster and pulse instead of scattered plists."
        case .search: return "Ask about Andromeda's own internals, or run real external web search — same surface, two very different sources."
        case .settings: return "Install, diagnose and maintain the local control plane — all Swift, no hybrid bash reopen."
        }
    }
}

// MARK: - Row models

/// Stable demo identity helpers — avoid `UUID()` stored properties in static catalogs
/// (non-deterministic + Swift 6 Sendable friction).
///
/// Do not store SwiftUI `Color` in these value types: `Color` is not `Sendable`, and
/// static catalogs must be concurrency-safe under Swift 6.
public struct CapabilityItem: Identifiable, Sendable {
    public var id: String { ref }
    public let name, ref, desc, status: String
    public let metrics: [(String, String)]
    public init(_ name: String, _ ref: String, _ desc: String, _ status: String, _ metrics: [(String, String)]) {
        self.name = name; self.ref = ref; self.desc = desc; self.status = status; self.metrics = metrics
    }

    /// View-layer mapping — computed so the stored model stays Sendable.
    public var statusColor: Color {
        switch status {
        case "live", "healthy", "shipped": return .andromedaLive
        case "partial", "degraded": return .andromedaAmber
        default: return .andromedaDim
        }
    }
}

public struct ModelRow: Identifiable, Sendable {
    public var id: String { name }
    public let name, tier: String
    public init(_ name: String, _ tier: String) {
        self.name = name; self.tier = tier
    }

    public var tierColor: Color {
        switch tier {
        case "fast": return .andromedaLive
        case "code": return .andromedaAmber
        default: return .andromedaTeal
        }
    }
}

public struct SpeedRow: Identifiable, Sendable {
    public var id: String { rank + ":" + name }
    public let rank, name, latency, tps: String
    public init(_ rank: String, _ name: String, _ latency: String, _ tps: String) {
        self.rank = rank; self.name = name; self.latency = latency; self.tps = tps
    }
}

public struct MemChange: Identifiable, Sendable {
    public var id: String { time + "|" + author + "|" + text }
    public let author, time, text: String
    public let dreaming: Bool
    public init(_ author: String, _ time: String, _ text: String, dreaming: Bool = false) {
        self.author = author; self.time = time; self.text = text; self.dreaming = dreaming
    }
}

public struct MemLayer: Identifiable, Sendable {
    public var id: String { key }
    public let key, name, kind, count, path, detail: String
    public init(_ key: String, _ name: String, _ kind: String, _ count: String, _ path: String, _ detail: String) {
        self.key = key; self.name = name; self.kind = kind; self.count = count; self.path = path; self.detail = detail
    }
}

public enum ControlPlaneData {
    /// Client-facing lanes only — capability / tier aliases, never provider brands.
    public static let models: [ModelRow] = [
        .init("infer.write · fast", "fast"),
        .init("infer.write · deep", "deep"),
        .init("infer.write · code", "code"),
    ]
    /// Speed board uses the same stable aliases (no provider model names).
    public static let speed: [SpeedRow] = [
        .init("1", "infer.write · fast", "—", "spec"),
        .init("2", "infer.write · deep", "—", "spec"),
        .init("3", "infer.write · code", "—", "spec"),
    ]
    public static let changes: [MemChange] = [
        .init("Berserker", "3m ago", "Record snapshot policy preference for non-visual PRs"),
        .init("Dreaming", "6d ago", "feat(reflection): update dream-state for sweeps #127–#137", dreaming: true),
        .init("Berserker", "5d ago", "docs: add encrypted memory-broker plan to pending-work"),
        .init("Dreaming", "5d ago", "fix(reflection): sync test count 151 and finalize docs", dreaming: true),
        .init("Berserker", "6d ago", "fix: update dream-state model reference"),
    ]
    /// Only the shipped hot store. Backend brands / unbuilt layers stay behind the curtain.
    public static let layers: [MemLayer] = [
        .init(
            "swiftdata",
            "SwiftData",
            "hot store",
            "shipped",
            "~/Andromeda/anima.store",
            "Implemented hot working set for memory.recall / memory.store. Other store backends are operator-internal and not client-visible."
        ),
    ]
    public static func items(for p: Pillar) -> [CapabilityItem] {
        switch p {
        case .mcp: return [
            .init("filesystem", "mcp://local/fs", "Local filesystem tools — read, write, glob. Deduped to one host process.", "live", [("9", "tools"), ("1", "process")]),
            .init("source control", "mcp://scm", "Repo browse, diff and PR tools surfaced as capabilities — brand hidden.", "live", [("12", "tools"), ("1", "process")]),
            .init("relational db", "mcp://db/pg", "Query + schema introspection. Shared lifecycle host not yet fully shipped.", "partial", [("6", "tools"), ("2", "process")]),
            .init("browser", "mcp://web/pw", "Playwright automation. Orphan-process pressure watched by fleet pulse.", "partial", [("14", "tools"), ("3", "process")]),
        ]
        case .skills: return [
            .init("make.deck", "skills.invoke/deck", "Compose a slide deck from a brief. Registry entity specified, not built.", "spec", [("—", "version"), ("spec", "stage")]),
            .init("web.research", "skills.invoke/research", "Grounded findings with live sources. Registry entity specified, not built.", "spec", [("—", "version"), ("spec", "stage")]),
            .init("image.compose", "skills.invoke/image", "Layout + placeholder imagery. Registry entity specified, not built.", "spec", [("—", "version"), ("spec", "stage")]),
            .init("pdf.read", "skills.invoke/pdf", "Extract structured text and assets from PDFs. Registry entity specified, not built.", "spec", [("—", "version"), ("spec", "stage")]),
        ]
        case .secrets: return [
            .init("infer credential", "secrets.broker/infer", "Injected server-side at call time. Client never sees the raw value.", "spec", [("•••", "masked"), ("broker", "backing")]),
            .init("scm token", "secrets.broker/scm", "Powers github_proxy. Env-scrubbed agents get HOME + PATH only.", "spec", [("•••", "masked"), ("broker", "backing")]),
            .init("slack token", "secrets.broker/slack", "Powers slack_proxy via broker — never raw tokens in process env.", "spec", [("•••", "masked"), ("broker", "backing")]),
            .init("db dsn", "secrets.broker/db", "Connection string sealed; brokered to db capability only.", "spec", [("•••", "masked"), ("broker", "backing")]),
        ]
        case .fleet: return [
            .init("node · atlas", "fleet.pulse/atlas", "LaunchAgent roster host. last_success 40s ago.", "healthy", [("34%", "cpu"), ("51%", "mem")]),
            .init("node · vega", "fleet.pulse/vega", "Telemetry hub + observability. Spend / kill switches armed.", "healthy", [("61%", "cpu"), ("72%", "mem")]),
            .init("node · rigel", "fleet.pulse/rigel", "Reconnecting — MCP process pressure high; watchdog restarting.", "degraded", [("—", "cpu"), ("—", "mem")]),
            .init("scheduler", "fleet.pulse/cron", "launchd timers for sweeps + dreaming reflections.", "healthy", [("7", "agents"), ("0", "failed")]),
        ]
        default: return []
        }
    }
}
