import type { Status } from "./pillars"

export type LessonKind = "canon" | "gate" | "template" | "ui" | "diagram"

export type LessonDownload = {
  label: string
  href: string
  filename?: string
}

export type Lesson = {
  slug: string
  title: string
  eyebrow: string
  summary: string
  kind: LessonKind
  status: Status
  github?: string
  downloads: LessonDownload[]
}

export const KIND_LABEL: Record<LessonKind, string> = {
  canon: "Canon",
  gate: "Review gate",
  template: "Template",
  ui: "UI",
  diagram: "Diagram",
}

export const LESSONS: Lesson[] = [
  {
    slug: "review-gate",
    title: "15-question review gate",
    eyebrow: "Merge contract",
    summary:
      "The fleet questionnaire. Six questions are merge blockers. The rest need an explicit answer or N/A. Use it while you work, then again on the PR.",
    kind: "gate",
    status: "partial",
    github: "https://github.com/Ripnrip/Andromeda/pull/76",
    downloads: [
      { label: "SKILL.md", href: "/api/lessons/download?artifact=swift-review-gate", filename: "swift-review-gate.tar" },
    ],
  },
  {
    slug: "swift-canon",
    title: "Swift Canon",
    eyebrow: "Implementation law",
    summary:
      "Project-agnostic Swift 6 craft: concurrency, enums, logging, SwiftUI, snapshots, TCA, Hummingbird, review discipline. References live next to the skill.",
    kind: "canon",
    status: "shipped",
    github: "https://github.com/Ripnrip/Andromeda/tree/main/.claude/skills/swift-canon",
    downloads: [
      { label: "SKILL.md", href: "/api/lessons/download?artifact=swift-canon", filename: "swift-canon.tar" },
    ],
  },
  {
    slug: "anti-patterns",
    title: "Anti-patterns",
    eyebrow: "Normative exhibits",
    summary:
      "Real code that shipped or nearly shipped. Each exhibit is the failing shape, why it fails review, and the replacement. Numbers continue as scars land.",
    kind: "canon",
    status: "shipped",
    github:
      "https://github.com/Ripnrip/Andromeda/blob/main/.claude/skills/swift-canon/references/anti-patterns.md",
    downloads: [
      {
        label: "anti-patterns.md",
        href: "/api/lessons/download?artifact=swift-canon",
        filename: "swift-canon.tar",
      },
    ],
  },
  {
    slug: "pr-template",
    title: "PR template",
    eyebrow: "What every PR opens with",
    summary:
      "Sequence/flow diagram is law. Visual evidence is law. The six merge-blocker boxes from the review gate belong on the template so authors see them at PR-open time.",
    kind: "template",
    status: "partial",
    github: "https://github.com/Ripnrip/Andromeda/blob/main/.github/PULL_REQUEST_TEMPLATE.md",
    downloads: [
      {
        label: "PULL_REQUEST_TEMPLATE.md",
        href: "/api/lessons/download?artifact=PR%20template",
        filename: "pull-request-template.md",
      },
    ],
  },
  {
    slug: "andromedaui",
    title: "AndromedaUI",
    eyebrow: "Component library",
    summary:
      "Instrumentable primitives, not smart widgets. Caller-supplied identifiers, no networking inside GlassCard. Previews and snapshots already exist — App Control is the headed-drive half.",
    kind: "ui",
    status: "partial",
    github: "https://github.com/Ripnrip/Andromeda/tree/main/Packages/AndromedaUI",
    downloads: [],
  },
  {
    slug: "app-control",
    title: "App Control",
    eyebrow: "Drivable UI",
    summary:
      "Not the product Control Plane. A debug/test adapter: identifiers, GET /state, POST /action, GET /screenshot. Same methods the buttons call. Loopback, env-gated, typed enum — never a second HTTP host.",
    kind: "ui",
    status: "spec",
    downloads: [
      { label: "app-control.md", href: "/lessons/pack/app-control.md", filename: "app-control.md" },
    ],
  },
  {
    slug: "diagrams",
    title: "Sequence diagrams",
    eyebrow: "Behavioral proof",
    summary:
      "Every behavioral PR carries a mermaid sequence/flow/state diagram of what it does, rendered to an image for review. Snapshots prove look. Diagrams prove drive.",
    kind: "diagram",
    status: "shipped",
    downloads: [
      {
        label: "sequence-diagram.mmd",
        href: "/lessons/pack/sequence-diagram.mmd",
        filename: "sequence-diagram.mmd",
      },
    ],
  },
]

export function lessonBySlug(slug: string): Lesson | undefined {
  return LESSONS.find((l) => l.slug === slug)
}

export const GATE_QUESTIONS: {
  id: string
  title: string
  body: string
  blocker: boolean
  tier: "pre-commit" | "review"
  group: string
}[] = [
  {
    id: "Q1",
    group: "Type & expression",
    title: "Enums over magic strings",
    blocker: true,
    tier: "pre-commit",
    body: "Every string that is really a finite set (states, labels, error kinds, allowlists, lanes, list markers) is an enum with exhaustive switches; CaseIterable where tests should iterate.",
  },
  {
    id: "Q2",
    group: "Type & expression",
    title: "Codable on the wire",
    blocker: true,
    tier: "pre-commit",
    body: "No hand-built JSON string literals in production code. Error frames, DTOs, and happy-path fixtures encode from types. Byte-equality where wire shape matters. macOS 26 JSONEncoder randomizes key order per-process — stable bytes need a canonical writer (Exhibit 13).",
  },
  {
    id: "Q3",
    group: "Type & expression",
    title: "Smallest clear expression",
    blocker: false,
    tier: "review",
    body: "Function vs computed property — honest about cost. Prefer switch over chained ifs; guard let for early exit, if let for local branch, for case let for filtered pattern-matching.",
  },
  {
    id: "Q4",
    group: "Type & expression",
    title: "Protocol vs enum",
    blocker: false,
    tier: "review",
    body: "Protocols only where implementations genuinely vary. Finite variation = enum, not a protocol hierarchy.",
  },
  {
    id: "Q5",
    group: "Type & expression",
    title: "Functional Swift where it fits",
    blocker: false,
    tier: "review",
    body: "map/compactMap/flatMap/reduce when the source is a collection and the transform is pure. Keep streaming loops when collecting would allocate, delay results, or hide side effects.",
  },
  {
    id: "Q6",
    group: "Concurrency & streams",
    title: "Actors / Sendable",
    blocker: true,
    tier: "pre-commit",
    body: "Shared mutable state is actor-isolated or value-typed Sendable. Every @unchecked Sendable carries a written justification. Cross-boundary values conform to Sendable.",
  },
  {
    id: "Q7",
    group: "Concurrency & streams",
    title: "Smallest honest lifetime model",
    blocker: false,
    tier: "review",
    body: "Value, one-shot async function, or AsyncSequence? Choose the smallest model that represents the real lifetime. Combine only at real publisher boundaries.",
  },
  {
    id: "Q8",
    group: "Observability & security",
    title: "Emoji telemetry at every decision point",
    blocker: true,
    tier: "pre-commit",
    body: "Each meaningful branch emits a typed event with a glyph through one enum surface. A new decision point without an event fails the gate.",
  },
  {
    id: "Q9",
    group: "Observability & security",
    title: "Secrets & data posture",
    blocker: true,
    tier: "pre-commit",
    body: "No ambient environment inheritance. Auth before privileged side effects. No PII in logs. Brokered secrets, never embedded. App Control /state never dumps Keychain.",
  },
  {
    id: "Q10",
    group: "UI",
    title: "Xcode Previews",
    blocker: false,
    tier: "review",
    body: "Every new UI state covered: loading / empty / error / long content / Dynamic Type / dark mode. Preview-parity suites where the repo has them.",
  },
  {
    id: "Q11",
    group: "UI",
    title: "Snapshot tests",
    blocker: false,
    tier: "review",
    body: "Layout/rendering regressions that matter have snapshots — baselines are CI-recorded, never studio-recorded. A green suite against a void baseline proves nothing (Exhibit 7).",
  },
  {
    id: "Q12",
    group: "UI",
    title: "Interaction feedback",
    blocker: false,
    tier: "review",
    body: "Intentional haptics for meaningful taps; a11y labels; identifiers for control vs labels for humans. No fake live states.",
  },
  {
    id: "Q13",
    group: "Quality",
    title: "Performance",
    blocker: false,
    tier: "review",
    body: "Hot path allocation-conscious. No sync work on the main/timeline thread. No accidental O(n²).",
  },
  {
    id: "Q14",
    group: "Quality",
    title: "Exhaustive proof",
    blocker: true,
    tier: "pre-commit",
    body: "CaseIterable drives tests. Behavioral changes carry a rendered sequence/flow diagram; UI changes carry a snapshot gallery. E2E paths proven by running them — receipts posted, not vibes.",
  },
  {
    id: "Q15",
    group: "Quality",
    title: "Better shape?",
    blocker: false,
    tier: "review",
    body: "Is there a simpler API — fewer types, less indirection — that still keeps Q1–Q14? If not, say why in the PR.",
  },
]

export const EXHIBITS: { id: string; title: string; note?: string }[] = [
  { id: "1", title: "Hand-rolled dynamic JSON where the protocol is closed" },
  { id: "2", title: "Ad-hoc child-process plumbing around Process" },
  { id: "3", title: "Awaiting exit before draining child pipes" },
  { id: "4", title: "Per-byte AsyncBytes iteration for bulk pipe reads" },
  { id: "5", title: "Hand-rolled encode(to:) to keep one key null" },
  { id: "6", title: "Enum labels built by rawValue concatenation" },
  { id: "7", title: "A .task-gated “settled” state that renders void" },
  { id: "8", title: "Lazy containers for fixed, small collections" },
  { id: "9", title: "@_nonSendable(_assumed) types crossing isolation" },
  { id: "10", title: "A tolerant record lane re-shipping committed files as fresh" },
  { id: "11", title: "The Go-shaped actor — porting another language’s structure" },
  {
    id: "13",
    title: "JSONEncoder on macOS 26 randomizes key order per-process",
    note: "Rides PR #75 — canonical writer + ≥5 suite runs before trusting format-sensitive green.",
  },
  {
    id: "14",
    title: "xcodegen regen wipes hand-edited entitlements",
    note: "Author generated files in project.yml. sim-green ≠ device-green for entitlement-class bugs.",
  },
]

export const CANON_REFERENCES = [
  { file: "anti-patterns.md", use: "Read before writing" },
  { file: "functional-swift.md", use: "Pure core, effect shell" },
  { file: "concurrency.md", use: "Sendable, actors, streams" },
  { file: "enum-design.md", use: "Exhaustive switch discipline" },
  { file: "logging.md", use: "os.Logger + emoji events" },
  { file: "typography.md", use: "SF Pro, native hierarchy" },
  { file: "tca.md", use: "Complex state" },
  { file: "swiftui-state.md", use: "@Observable clients" },
  { file: "swiftui-views.md", use: "Compose views" },
  { file: "previews.md", use: "State matrix before full builds" },
  { file: "testing.md", use: "Unit + snapshot + TestStore" },
  { file: "review-canon.md", use: "PR / scope / merge law" },
  { file: "dependency-injection.md", use: "Protocol boundaries" },
  { file: "accessibility.md", use: "VoiceOver, Dynamic Type" },
  { file: "animations.md", use: "Motion, transitions" },
  { file: "motion-haptics.md", use: "Haptics + Reduce Motion" },
  { file: "macos-patterns.md", use: "MenuBarExtra, HUD windows" },
  { file: "hummingbird.md", use: "Server routes" },
  { file: "openapi-server.md", use: "Generated boundaries" },
]

export const NAMING_SPLIT = [
  {
    name: "Product Control Plane",
    meaning: "The six-pillar Andromeda window / capability curtain. Real product surface.",
  },
  {
    name: "App Control",
    meaning:
      "Debug/test drivability: identifiers + /state /action /screenshot. Env-gated, loopback, not a second product server.",
  },
]
