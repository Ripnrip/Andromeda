import SwiftUI

// MARK: - Memory

public enum MemoryState: String, PillarState {
    case forming, consolidating, recalled, decaying, conflicted

    public var label: String { "memory." + rawValue }

    public var accent: Color {
        switch self {
        case .forming:       .andromedaTeal
        case .consolidating: .andromedaDream
        case .recalled:      .andromedaLive
        case .decaying:      .andromedaMuted
        case .conflicted:    .andromedaAlert
        }
    }

    public var badge: String {
        switch self {
        case .forming:       "forming · 3 new traces"
        case .consolidating: "consolidating · 12 links"
        case .recalled:      "recalled · 18ms"
        case .decaying:      "decaying · 2 fading"
        case .conflicted:    "conflicted · 1 held"
        }
    }

    public var log: String {
        switch self {
        case .forming:       "trace/site-split · unsealed · witnesses 1"
        case .consolidating: "linking 12 traces into 4 beliefs · 1 exception kept"
        case .recalled:      "answered from 3 traces · every line quotable"
        case .decaying:      "2 traces unrecalled for 94 days · salience 0.06"
        case .conflicted:    "trace/pooled-estimate contradicts a held belief"
        }
    }

    public var note: String {
        switch self {
        case .forming:
            "A trace is born unsealed and alone. It carries who witnessed it and when, and it can answer nothing until the write path commits it."
        case .consolidating:
            "Links are the memory. A trace with no edges is trivia; the same trace tied to four others is the thing that changes an answer."
        case .recalled:
            "Recall is not a lookup — it raises salience. A trace you keep needing gets harder to prune, which is how the memory learns what matters to you."
        case .decaying:
            "Low-salience traces fade rather than vanish: the content goes, the receipt stays, so “I used to know this” is still an answerable question."
        case .conflicted:
            "Contradiction is held, not resolved on the spot. The trace stays amber in the HUD and goes into the next dream with both sides intact."
        }
    }

    /// Salience delta this state applies to the type meters.
    public var salienceShift: Double {
        switch self {
        case .forming: 0.06; case .consolidating: 0.14; case .recalled: 0.24
        case .decaying: -0.18; case .conflicted: 0
        }
    }
}

/// The six kinds a trace can be. Named `TraceKind` to avoid colliding with
/// the control plane's existing `MemoryKind`.
public enum TraceKind: String, CaseIterable, Identifiable, Sendable {
    case episodic, semantic, procedural, preference, constraint, working

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var tint: Color {
        switch self {
        case .episodic:   .andromedaTeal
        case .semantic:   .andromedaGlow
        case .procedural: .andromedaLive
        case .preference: .andromedaAmber
        case .constraint: .andromedaAlert
        case .working:    .andromedaDream
        }
    }

    /// Baseline salience, 0…1.
    public var baseline: Double {
        switch self {
        case .episodic: 0.86; case .semantic: 0.72; case .procedural: 0.54
        case .preference: 0.41; case .constraint: 0.33; case .working: 0.22
        }
    }
}

/// The glyph a trace kind draws — the lattice reads as a legend at a glance.
public struct TraceGlyph: Shape, Sendable {
    public var kind: TraceKind
    public init(_ kind: TraceKind) { self.kind = kind }

    public func path(in rect: CGRect) -> Path {
        switch kind {
        case .episodic, .working:
            return Circle().path(in: rect)
        case .semantic:
            return RoundedRectangle(cornerRadius: 2).path(in: rect)
        case .procedural:
            return Capsule().path(in: rect)
        case .preference:
            // Teardrop: round except one squared corner.
            return UnevenRoundedRectangle(
                topLeadingRadius: rect.width / 2, bottomLeadingRadius: rect.width / 2,
                bottomTrailingRadius: 2, topTrailingRadius: rect.width / 2
            ).path(in: rect)
        case .constraint:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
            return p
        }
    }
}

/// One node of the trace lattice, positioned in a 220×150 design space.
public struct TraceNode: Identifiable, Sendable {
    public let id: Int
    public let kind: TraceKind
    public let name: String
    public let point: CGPoint

    public init(_ id: Int, _ kind: TraceKind, _ name: String, _ x: CGFloat, _ y: CGFloat) {
        self.id = id; self.kind = kind; self.name = name
        self.point = CGPoint(x: x, y: y)
    }

    public static let design = CGSize(width: 220, height: 150)

    public static let all: [TraceNode] = [
        .init(0, .episodic,   "site-split", 27,  31),
        .init(1, .semantic,   "pooling",    63,  73),
        .init(2, .episodic,   "standup",    25, 115),
        .init(3, .procedural, "triage",     61,  17),
        .init(4, .preference, "terse",      99,  47),
        .init(5, .constraint, "no-guess",   97, 111),
        .init(6, .working,    "drift",     137,  77),
    ]

    public static let edges: [(Int, Int)] = [(0, 1), (2, 1), (3, 1), (1, 4), (1, 6), (5, 6), (4, 6)]
}

/// How a node reads in the current memory state.
public enum TraceNodeMood: Sendable { case idle, fresh, linking, hit, onPath, fading, clashing }

public extension MemoryState {
    func mood(for node: TraceNode) -> TraceNodeMood {
        switch self {
        case .forming:       (node.id == 0 || node.id == 6) ? .fresh : .idle
        case .consolidating: [0, 1, 2, 3].contains(node.id) ? .linking : .idle
        case .recalled:      node.id == 1 ? .hit : ([0, 2].contains(node.id) ? .onPath : .idle)
        case .decaying:      [3, 5].contains(node.id) ? .fading : .idle
        case .conflicted:    [1, 6].contains(node.id) ? .clashing : .idle
        }
    }

    /// Edge treatment by index into `TraceNode.edges`.
    func edgeMood(_ i: Int) -> TraceNodeMood {
        switch self {
        case .consolidating: i < 4 ? .linking : .idle
        case .recalled:      i < 2 ? .onPath : .idle
        case .decaying:      [2, 5].contains(i) ? .fading : .idle
        case .conflicted:    i == 4 ? .clashing : .idle
        case .forming:       .idle
        }
    }
}

// MARK: - Perception

public enum PerceptionState: String, PillarState {
    case listening, recalling, whisper, focus

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .listening: .andromedaTeal; case .recalling: .andromedaGlow
        case .whisper:   .andromedaLive; case .focus:     .andromedaMuted
        }
    }
    public var badge: String {
        switch self {
        case .listening: "listening · speak"; case .recalling: "recalling · 4 brains"
        case .whisper:   "whisper · proactive"; case .focus:   "focus · muted"
        }
    }
    public var log: String {
        switch self {
        case .listening: "mic open · 00:03 · nothing leaves this machine"
        case .recalling: "sweeping vector · graph · episodic · web"
        case .whisper:   "you argued the opposite on Tuesday — want the trace?"
        case .focus:     "whispers held · 4 queued for later"
        }
    }
    public var note: String {
        switch self {
        case .listening:
            "Capture starts the instant you invoke it and stops when you stop. There is no ambient recording — the bars are the proof that it is on."
        case .recalling:
            "A question fans out to every store at once. What comes back is ranked by fit, not by whichever backend happened to answer first."
        case .whisper:
            "Andromida speaks first only when it holds something you already asked for. Every whisper carries the trace that prompted it."
        case .focus:
            "Focus does not discard what it wanted to say, it queues it. Nothing is lost to a do-not-disturb."
        }
    }
}

// MARK: - Write path

public enum WritePathState: String, PillarState {
    case capturing, writing, committing, syncing

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .capturing: .andromedaAlert; case .writing: .andromedaTeal
        case .committing: .andromedaGlow; case .syncing: .andromedaLive
        }
    }
    public var badge: String {
        switch self {
        case .capturing: "capturing · rec"; case .writing: "writing · memory.write"
        case .committing: "committing · outbox"; case .syncing: "syncing · draining"
        }
    }
    public var log: String {
        switch self {
        case .capturing:  "buffering to disk before anything else"
        case .writing:    "memory.write  trace/site-split  witnesses 1"
        case .committing: "0x41f4  APPEND → outbox  durable"
        case .syncing:    "outbox drains → vector · graph · episodic"
        }
    }
    public var note: String {
        switch self {
        case .capturing:
            "The first thing that happens to a memory is that it gets written down. Interpretation comes after durability, never before."
        case .writing:
            "The verb lands and the trace is drafted into shape — typed, attributed, and still entirely uncommitted."
        case .committing:
            "Commit means the outbox owns it. If Andromida dies at this line, the memory that survives is the memory you can account for."
        case .syncing:
            "The queue flushes to every backend and the counter falls to zero. A queue that never reaches zero is a health signal, not a mystery."
        }
    }

    /// Position along the capture → draft → commit → drain rail.
    public var stage: Int {
        switch self { case .capturing: 0; case .writing: 1; case .committing: 2; case .syncing: 3 }
    }
    public static let rail = ["capture", "draft", "commit", "drain"]
}

// MARK: - LLM proxy

public enum ProxyState: String, PillarState {
    case proxying, streaming, routing, tokens

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .proxying: .andromedaTeal; case .streaming: .andromedaGlow
        case .routing:  .andromedaAmber; case .tokens:   .andromedaLive
        }
    }
    public var badge: String {
        switch self {
        case .proxying: "proxying · warm"; case .streaming: "streaming · infer.deep"
        case .routing:  "routing · re-routed"; case .tokens: "token meter · live"
        }
    }
    public var log: String {
        switch self {
        case .proxying:  "gateway warm · upstream thinking…"
        case .streaming: "decoding 41 tok/s · block 7"
        case .routing:   "infer.deep saturated → infer.fast · 4ms triage"
        case .tokens:    "spend visible before it becomes a surprise"
        }
    }
    public var note: String {
        switch self {
        case .proxying:
            "One endpoint in front of every model. Your agent never learns which mind answered, so swapping one costs nothing downstream."
        case .streaming:
            "Tokens are handed back the moment they exist. Waiting for a whole answer to render is latency you paid for and did not need."
        case .routing:
            "The proxy re-routes to the cheapest healthy model that still fits the task, and says so in the HUD rather than degrading quietly."
        case .tokens:
            "Every call is counted where you can see it. A memory system that bills by the thought owes you a running total."
        }
    }

    /// Stable capability IDs only — upstream provider/model brands stay
    /// behind the operator curtain (AGENTS.md capability hiding).
    public static let models = ["infer.deep", "infer.fast", "infer.local"]
    /// Which upstream is carrying the request, if any.
    public var activeModel: Int? {
        switch self { case .routing: 1; case .proxying, .streaming: 0; case .tokens: nil }
    }
}

// MARK: - Agent skills

public enum SkillState: String, PillarState {
    case installing, invoking, ready

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .installing: .andromedaTeal; case .invoking: .andromedaGlow; case .ready: .andromedaLive
        }
    }
    public var badge: String {
        switch self {
        case .installing: "installing · transcribe"
        case .invoking:   "invoking · playwright"
        case .ready:      "ready · +3 abilities"
        }
    }
    public var log: String {
        switch self {
        case .installing: "fetching skill · registering verbs"
        case .invoking:   "skill running · 3 steps in · 1 tool held"
        case .ready:      "transcribe · playwright · reconcile registered"
        }
    }
    public var note: String {
        switch self {
        case .installing:
            "A skill declares the verbs it adds before it is allowed to run. Nothing installs itself into the toolbelt silently."
        case .invoking:
            "While a skill works, its steps are visible. A capability you cannot watch is a capability you cannot revoke."
        case .ready:
            "New abilities snap into the belt and stay inert until called. Growth is additive — it never rewrites what Andromida already knew how to do."
        }
    }

    public static let skills = ["transcribe", "playwright", "reconcile-sources"]
    public var activeSkill: Int? {
        switch self { case .installing: 0; case .invoking: 1; case .ready: nil }
    }
    public func tag(_ i: Int) -> String {
        switch (self, i) {
        case (.installing, 0): "installing"
        case (.invoking, 1):   "running"
        default:               "ready"
        }
    }
}

// MARK: - MCP

public enum MCPState: String, PillarState {
    case connecting, discovering, toolcall

    public var label: String { self == .toolcall ? "tool call" : rawValue }

    public var accent: Color {
        switch self {
        case .connecting: .andromedaAmber; case .discovering: .andromedaTeal; case .toolcall: .andromedaLive
        }
    }
    public var badge: String {
        switch self {
        case .connecting:  "connecting · tickets"
        case .discovering: "discovering · 12 tools"
        case .toolcall:    "tool call · docs.search"
        }
    }
    public var log: String {
        switch self {
        case .connecting:  "handshake · negotiating session…"
        case .discovering: "server advertises 12 · policy allows 3"
        case .toolcall:    "docs.search(\"pooling\") → 4 results · 212ms"
        }
    }
    public var note: String {
        switch self {
        case .connecting:
            "Amber until the handshake lands. A connector that half-connects is reported as amber, never rendered as green."
        case .discovering:
            "A server may offer anything; policy decides what Andromida can touch. Scope is sacred, and the gap is shown rather than hidden."
        case .toolcall:
            "The call goes out and the result comes back attributed. Anything a tool returns enters memory as a quotable trace, not as fact."
        }
    }

    /// Tool name + position in a unit circle around the hub.
    public static let tools: [(name: String, angle: Double, allowed: Bool)] = [
        ("search", -60, true), ("create", -10, false), ("list", 40, false),
        ("read", 110, true), ("update", 175, true), ("notify", -130, false),
    ]
}

// MARK: - Memory fabric

public enum FabricState: String, PillarState {
    /// Raw values are stable client capability IDs (`memory.*`); the storage
    /// engines behind them (graph store, vector store) stay behind the curtain.
    case web, graph, vector, procedural

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .web: .andromedaMuted; case .graph: .andromedaAmber
        case .vector: .andromedaTeal; case .procedural: .andromedaLive
        }
    }
    public var badge: String {
        switch self {
        case .web: "memory.web · fresh facts"; case .graph: "memory.graph · temporal"
        case .vector: "memory.vector · neighbours"; case .procedural: "memory.steps · 3/6"
        }
    }
    public var log: String {
        switch self {
        case .web:        "memory is cold on this — reaching out"
        case .graph:      "traversing entity edges across 94 days"
        case .vector:     "nearest neighbours · 0.86 cosine"
        case .procedural: "replaying how you usually answer this"
        }
    }
    public var note: String {
        switch self {
        case .web:
            "When nothing held is recent enough, Andromida says so and goes outside. It does not dress an old trace up as a current one."
        case .graph:
            "The graph holds change over time — not what you believe, but when you started believing it and what moved you."
        case .vector:
            "Resemblance, not keywords. This is the store that finds the note you could not remember the words for."
        case .procedural:
            "How-to memory replays in order. It is the difference between knowing your position and knowing your move."
        }
    }
}

// MARK: - Fleet signals

public enum FleetState: String, PillarState {
    case milestone, reindexing, ingesting, degraded, handoff

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .milestone: .andromedaGlow; case .reindexing: .andromedaAmber
        case .ingesting: .andromedaTeal; case .degraded: .andromedaAlert
        case .handoff:   .andromedaDream
        }
    }
    public var badge: String {
        switch self {
        case .milestone:  "milestone"
        case .reindexing: "reindexing · graph"
        case .ingesting:  "ingesting · antara-notes.md"
        case .degraded:   "degraded · vector store offline"
        case .handoff:    "handoff → dreaming"
        }
    }
    public var log: String {
        switch self {
        case .milestone:  "memories stored"
        case .reindexing: "graph re-weaving · queries served from snapshot"
        case .ingesting:  "412 traces extracted · witnesses attached"
        case .degraded:   "answering from graph + episodic only"
        case .handoff:    "passing 312 fragments to the dream agent"
        }
    }
    public var note: String {
        switch self {
        case .milestone:
            "A threshold crossed is worth one ripple and nothing more. Celebration that interrupts is just another notification."
        case .reindexing:
            "The graph rebuilds behind a snapshot, so recall stays answerable while the shape of the memory changes underneath it."
        case .ingesting:
            "Determinate progress you can trust: the bar tracks traces committed, not bytes read."
        case .degraded:
            "Honest failure. Andromida narrows what it claims to know rather than quietly answering worse from a smaller memory."
        case .handoff:
            "Work moves between agents on a visible wire. Every handoff is a trace, so a bad answer can be walked back to the agent that made it."
        }
    }

    public static let intake: [(name: String, meta: String, progress: Double)] = [
        ("antara-notes.md", "412 traces · 68%", 0.68),
        ("standup-2026-08.vtt", "96 traces · queued", 0),
        ("pooling-draft.md", "sealed · 3 witnesses", 1),
        ("zotero/instrument.pdf", "read · 0 traces yet", 0.14),
    ]
    /// Capability IDs, not engine brands (curtain law).
    public static let backends = ["vector", "graph", "episodic", "web"]
}
