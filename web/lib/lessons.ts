export type GateQuestion = {
  n: number
  short: string
  question: string
  from: string
  blocker: boolean
}

export const GATE: GateQuestion[] = [
  { n: 1, short: "Enums over magic", question: "Every closed set of strings (states, labels, error kinds, allowlists, markers) is an enum with exhaustive switches — CaseIterable where tests iterate.", from: "PR #75 hub refactor · PR #27 ListItemMarker", blocker: true },
  { n: 2, short: "Codable on the wire", question: "No hand-built JSON literals in production code. Error frames, DTOs, and fixtures encode from types. Byte-equality where wire shape matters — null must be a present member. Deliberately-malformed frames stay raw.", from: "HubJSONRPCError + the JSONEncoder key-order trap (Exhibit 13)", blocker: true },
  { n: 3, short: "Smallest clear expression", question: "Function vs computed property, honest about I/O cost. Switch over chained ifs; guard let for early exit, if let for local branch, for case let for filtered matching. Failures typed, never silently zeroed.", from: "diskSpace() — 'no storage' must differ from 'could not inspect'", blocker: false },
  { n: 4, short: "Protocol vs enum", question: "Protocols only where implementations genuinely vary. Finite variation is an enum, not a protocol hierarchy.", from: "Fleet design review canon", blocker: false },
  { n: 5, short: "Functional where it fits", question: "map/compactMap/reduce for pure collection transforms. Streaming loops stay streaming when collecting would allocate or hide side effects.", from: "File-enumerator debate — don't materialize to look functional", blocker: false },
  { n: 6, short: "Actors / Sendable", question: "Shared mutable state is actor-isolated or value-typed Sendable. Every @unchecked Sendable carries a written justification.", from: "Swift 6 strict concurrency", blocker: true },
  { n: 7, short: "Smallest honest lifetime", question: "Value, one-shot async, or AsyncSequence — choose the smallest model for the real lifetime. Combine only at real publisher boundaries.", from: "Streams/reactive design question", blocker: false },
  { n: 8, short: "Emoji telemetry at decisions", question: "Every meaningful branch emits a typed event with a glyph through one surface. A new decision point without an event fails review.", from: "HubEvent 🚀🐣💥👋🛑🔌📬📡 + 🚫⚠️🏷️✂️🧹🔁", blocker: true },
  { n: 9, short: "Secrets & data posture", question: "Enum env allowlists — no ambient environment inheritance. Auth before privileged side effects. No PII in logs or mirrors.", from: "Codex P1 allowlist · Cursor lock-screen intent catch", blocker: true },
  { n: 10, short: "Xcode previews", question: "Every new UI state covered: loading, empty, error, long content, Dynamic Type, dark mode.", from: "Preview-parity suites (PR #50)", blocker: false },
  { n: 11, short: "Snapshot tests", question: "Layout/rendering regressions get snapshots — CI-recorded baselines only. A green suite against a void baseline proves nothing.", from: "Void-gallery incident (Exhibit 7)", blocker: false },
  { n: 12, short: "Interaction feedback", question: "Intentional haptics for meaningful taps. A11y labels. No fake live states.", from: "UI questions wave", blocker: false },
  { n: 13, short: "Performance", question: "Hot path allocation-conscious — bytes not strings, deltas over full copies. Nothing synchronous on the main/timeline thread.", from: "56s full-vault pull → 0.03s delta pull", blocker: false },
  { n: 14, short: "Exhaustive proof", question: "CaseIterable drives tests. Codable fixture builders. Diagrams for behavior, galleries for UI. E2E paths run with receipts — not asserted.", from: "'Run it yourself' — real code, real process, receipts posted", blocker: true },
  { n: 15, short: "Better shape?", question: "Is there a simpler API that still keeps 1–14? If not, say why in the PR.", from: "Every review, forever", blocker: false },
]

export type Exhibit = {
  n: number
  title: string
  symptom: string
  rule: string
  provenance: string
}

export const EXHIBITS: Exhibit[] = [
  {
    n: 7,
    title: "Vacuously green snapshot suites",
    symptom: "Every test green. Every image blank.",
    rule: "Derive settled state from the environment, not async task completion. Visually inspect a baseline before trusting it.",
    provenance: "Void-gallery incident, Andromeda PR #61",
  },
  {
    n: 13,
    title: "Trusting JSONEncoder for stable wire bytes",
    symptom: "A Codable rewrite passes tests — sometimes. 2/8 processes by luck.",
    rule: "macOS 26 JSONEncoder randomizes key order per-process. Stable wire bytes need a canonical writer + byte-equality oracle + ≥5 runs.",
    provenance: "Andromeda PR #75, error-frame rewrite",
  },
  {
    n: 14,
    title: "xcodegen regen wipes hand edits",
    symptom: "Entitlements you wrote are empty dicts at review. App dead on device, green in simulator.",
    rule: "Generated files are authored in project.yml (entitlements.properties), never by hand. Sim-green ≠ device-green for capability classes.",
    provenance: "multibrain PR #27, Codex review catch",
  },
]

export const PRINCIPLE = {
  title: "The Log is the Contract",
  lines: [
    "The document is for the agent. The log is the truth. Everything else is a projection.",
    "Append, don't overwrite — corrections append, they never retcon.",
    "Every claim carries its receipt — cite the log line or don't claim it.",
    "Docs for agents get log-shaped tails, not just current-state prose.",
    "Replay beats restore. Fork-and-diff over rerun-and-hope.",
  ],
  provenance: "Named for activegraph's 'The Log is the Agent' (arXiv 2605.21997); we built the practice first.",
}

export const DOWNLOADS = [
  { name: "swift-review-gate", what: "The 15-question gate as a loadable skill", path: "swift-review-gate/SKILL.md" },
  { name: "swift-canon", what: "Full canon — 30 reference files + anti-patterns (Exhibits 1–14)", path: "swift-canon/" },
  { name: "PR template", what: "Andromeda PR template with the 6 merge blockers", path: "PULL_REQUEST_TEMPLATE.md" },
  { name: "app-control", what: "Programmatic app-control skills (doctor · core · verify · showcase)", path: "app-control/" },
]
