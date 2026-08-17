import SwiftUI

// MARK: - Pillar palette additions
// The nine-pillar board needs a dream ramp the core palette does not carry.
// Everything else reuses `Color.andromeda*` from AndromedaTheme.

public extension Color {
    /// Dream violet — the consolidation ramp used by Dreaming + handoff.
    static let andromedaDream      = Color(red: 0.545, green: 0.482, blue: 0.941)
    /// Threshold violet (hypnagogic).
    static let andromedaDreamEdge  = Color(red: 0.639, green: 0.580, blue: 0.949)
    /// Slow-wave violet (deep).
    static let andromedaDreamDeep  = Color(red: 0.365, green: 0.333, blue: 0.788)
    /// Directed violet (lucid).
    static let andromedaDreamLucid = Color(red: 0.765, green: 0.690, blue: 1.0)
    /// Failure red — degraded backends, held contradictions.
    static let andromedaAlert      = Color(red: 0.878, green: 0.361, blue: 0.361)
}

// MARK: - State protocol

/// One mode of one pillar. Every state carries its own accent, HUD badge,
/// log line, and the sentence that explains why the state exists.
public protocol PillarState: CaseIterable, Hashable, Identifiable, Sendable {
    var label: String { get }
    var accent: Color { get }
    var badge: String { get }
    var log: String { get }
    var note: String { get }
}

public extension PillarState {
    var id: String { label }

    /// Nth state in declaration order, wrapping — the driver's cycle step.
    static func cycled(_ n: Int) -> Self {
        let all = Array(allCases)
        return all[((n % all.count) + all.count) % all.count]
    }
}

// MARK: - Dreaming

public enum DreamState: String, PillarState {
    case awake, hypnagogic, rem, deep, lucid

    public var label: String { rawValue }

    public var accent: Color {
        switch self {
        case .awake:       .andromedaTeal
        case .hypnagogic:  .andromedaDreamEdge
        case .rem:         .andromedaDream
        case .deep:        .andromedaDreamDeep
        case .lucid:       .andromedaDreamLucid
        }
    }

    public var badge: String {
        switch self {
        case .awake:      "awake · capturing"
        case .hypnagogic: "hypnagogic · drifting"
        case .rem:        "REM · consolidating"
        case .deep:       "deep · pruning"
        case .lucid:      "lucid · directed"
        }
    }

    public var clock: String {
        switch self {
        case .awake:      "00:00 · day"
        case .hypnagogic: "23:41 · n1"
        case .rem:        "02:18 · n3"
        case .deep:       "03:52 · n4"
        case .lucid:      "05:07 · n2"
        }
    }

    public var log: String {
        switch self {
        case .awake:      "capture only · last dream 4h 12m ago"
        case .hypnagogic: "loosening 312 fragments from their source turns…"
        case .rem:        "merging “instrument-drift” with “site-split”…"
        case .deep:       "pruning 1,204 fragments below salience 0.08"
        case .lucid:      "replaying “pooled-estimate” under your counterfactual"
        }
    }

    public var note: String {
        switch self {
        case .awake:
            "While you work, Andromida only captures. Reorganising memory in front of you would change its answers mid-conversation — so the dream waits."
        case .hypnagogic:
            "The threshold state. Fragments let go of the conversation they arrived in, so a thing you said in a standup can later be found by someone asking about a paper."
        case .rem:
            "REM reconciles. Two fragments that disagreed become one belief with a stated exception — never a silent overwrite, and never an average of the two."
        case .deep:
            "Deep sleep prunes. What was never recalled decays, and the decay is written down: forgetting is a decision Andromida can be asked to justify."
        case .lucid:
            "You steer this one. A lucid pass replays a specific memory under a premise you supply, and files the result as a hypothetical — tagged, never as fact."
        }
    }

    /// The band that leads the montage in this state.
    public var leadBand: EEGBand {
        switch self {
        case .awake:      .alpha
        case .hypnagogic: .theta
        case .rem:        .rem
        case .deep:       .delta
        case .lucid:      .spindle
        }
    }

    /// How far consolidation has progressed, 0…1.
    public var consolidation: Double {
        switch self {
        case .awake: 0.12; case .hypnagogic: 0.38; case .rem: 0.74; case .deep: 0.96; case .lucid: 0.56
        }
    }

    public var fragments: [DreamFragment] {
        switch self {
        case .awake:
            [.init("site-split", .captured), .init("standup", .captured), .init("drift", .captured)]
        case .hypnagogic:
            [.init("site-split", .loose), .init("pooling", .loose), .init("drift", .loose)]
        case .rem:
            [.init("instrument-drift", .merging), .init("site-split", .merging)]
        case .deep:
            [.init("tab-order·2019", .pruning), .init("stale-link", .pruning), .init("dup-quote", .pruning)]
        case .lucid:
            [.init("pooled-estimate", .replaying)]
        }
    }

    public var event: String? {
        switch self {
        case .rem:   "one belief · exception kept"
        case .deep:  "1,204 pruned"
        case .lucid: "↺ replay"
        default:     nil
        }
    }

    public var ledger: [LedgerLine] {
        switch self {
        case .awake:
            [.init("0x41f2", "APPEND  trace/site-split", .held),
             .init("0x41f3", "APPEND  trace/standup", .held),
             .init("—", "dream queue: 3 waiting", .idle)]
        case .hypnagogic:
            [.init("0x4a01", "DETACH  312 fragments", .ok),
             .init("0x4a02", "PROPOSE 41 links", .pending),
             .init("—", "no commits in n1", .idle)]
        case .rem:
            [.init("0x4b17", "MERGE   drift + site-split", .ok),
             .init("0x4b18", "EXCEPT  “unless pooled”", .held),
             .init("0x4b19", "RESOLVE 1 conflict", .ok)]
        case .deep:
            [.init("0x4c02", "PRUNE   1,204 fragments", .ok),
             .init("0x4c03", "RECEIPT written to log", .ok),
             .init("0x4c04", "RECALL latency −31%", .ok)]
        case .lucid:
            [.init("0x4d11", "REPLAY  pooled-estimate", .ok),
             .init("0x4d12", "PREMISE user-supplied", .held),
             .init("0x4d13", "FILE    as hypothetical", .ok)]
        }
    }

    /// What this dream state does to the memory lattice.
    public var coupling: String {
        switch self {
        case .awake:
            "Nothing moves. New traces stack in the write log with their witnesses, and the lattice you queried this morning is the lattice you query tonight."
        case .hypnagogic:
            "Edges go soft. Traces detach from their source turn and become reachable by resemblance — new links get proposed, none committed yet."
        case .rem:
            "Two contradicting traces collapse into one belief with an exception attached. The lattice loses a node and gains a qualification."
        case .deep:
            "The weakest nodes go dark and their edges are cut. Counts drop, recall gets faster, and the prune is appended to the log as its own trace."
        case .lucid:
            "One path is walked deliberately and lit end to end. Salience on that path rises; everything off it is left exactly as it was."
        }
    }
}

public struct DreamFragment: Identifiable, Hashable, Sendable {
    public enum Treatment: Sendable { case captured, loose, merging, pruning, replaying }
    public var id: String { name }
    public let name: String
    public let treatment: Treatment
    public init(_ name: String, _ treatment: Treatment) {
        self.name = name; self.treatment = treatment
    }
}

public struct LedgerLine: Identifiable, Hashable, Sendable {
    public enum Status: Sendable { case ok, held, pending, idle }
    public var id: String { addr + body }
    public let addr: String
    public let body: String
    public let status: Status
    public init(_ addr: String, _ body: String, _ status: Status) {
        self.addr = addr; self.body = body; self.status = status
    }
    public var tint: Color {
        switch status {
        case .ok, .held: .andromedaDreamLucid
        case .pending:   .andromedaAmber
        case .idle:      .andromedaDim
        }
    }
    public var text: String { "\(addr)   \(body)" }
}

// MARK: - EEG bands

/// The six channels of the Dreaming montage. Each is a pure function of
/// position and time, sampled by `EEGMontage` inside a single `Canvas`.
public enum EEGBand: String, CaseIterable, Identifiable, Sendable {
    case delta, theta, alpha, beta, rem, spindle

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .delta: "δ"; case .theta: "θ"; case .alpha: "α"
        case .beta: "β"; case .rem: "REM"; case .spindle: "σ"
        }
    }

    public var tag: String {
        switch self {
        case .delta:   "0.5–4 · slow-wave"
        case .theta:   "4–8 · threshold"
        case .alpha:   "8–12 · resting"
        case .beta:    "12–30 · directed"
        case .rem:     "sawtooth · merge"
        case .spindle: "burst · replay"
        }
    }

    /// Scroll rate in widths per second when this band leads / trails.
    var leadRate: Double {
        switch self {
        case .delta: 0.12; case .theta: 0.18; case .alpha: 0.14
        case .beta: 0.24; case .rem: 0.31; case .spindle: 0.22
        }
    }
    var trailRate: Double { leadRate * 0.42 }

    /// Signal value in −1…1 at normalised position `u` (0…1 across two widths).
    func value(at u: Double) -> Double {
        switch self {
        case .delta:
            return sin(u * .pi * 2 * 3)
        case .theta:
            return sin(u * .pi * 2 * 7) * 0.86 + sin(u * .pi * 2 * 13) * 0.14
        case .alpha:
            return sin(u * .pi * 2 * 13)
        case .beta:
            return sin(u * .pi * 2 * 27) * 0.72
        case .rem:
            // Sawtooth: slow ramp, fast fall — the REM signature.
            let p = (u * 9).truncatingRemainder(dividingBy: 1)
            return p < 0.72 ? (p / 0.72) * 2 - 1 : 1 - ((p - 0.72) / 0.28) * 2
        case .spindle:
            // 12–14 Hz bursts inside a slow envelope.
            let envelope = max(0, sin(u * .pi * 2 * 3.5))
            return sin(u * .pi * 2 * 46) * pow(envelope, 2.2)
        }
    }
}
