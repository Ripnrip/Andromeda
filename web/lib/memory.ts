import type { Status } from "./pillars"

export type MemoryLayer = {
  n: string
  name: string
  intent: string
  status: Status
  differentiator?: boolean
}

// §3 — the eight layers of memory (Anima). Integrity / Awareness / Dreaming are the differentiators.
export const MEMORY_LAYERS: MemoryLayer[] = [
  { n: "01", name: "Episodic", intent: "\u201cWe talked Tuesday.\u201d Timed, ordered, compactable capture.", status: "shipped" },
  { n: "02", name: "Semantic", intent: "\u201cChapter 3 has the state machine.\u201d Structure-first recall.", status: "partial" },
  { n: "03", name: "Photographic", intent: "\u201cI\u2019ve seen that diagram.\u201d Vision recall over screenshots.", status: "spec" },
  { n: "04", name: "Integrity", intent: "\u201cCan I trust this memory?\u201d Merkle proofs over memory trees.", status: "partial", differentiator: true },
  { n: "05", name: "Meditation", intent: "Morning reflection that reads the dream journal and sets intention.", status: "partial" },
  { n: "06", name: "Soul", intent: "Presence, mood, relationship depth \u2014 context, not a chatbot.", status: "partial" },
  { n: "07", name: "Awareness", intent: "Speak only when it matters. Silence is a feature.", status: "partial", differentiator: true },
  { n: "08", name: "Dreaming", intent: "Night: Review \u2192 Shadow \u2192 Insight \u2192 Integration.", status: "partial", differentiator: true },
]

// §4 — one job per store. Hot (SwiftData today) → curated vault → rebuildable indexes.
// SoT = source of truth — the durable record that wins when caches disagree.
// Indexes are rebuildable. Index failure never erases the source.
export type Store = {
  name: string
  style: string
  answers: string
  isHot?: boolean   // live on-device today
  isSoT?: boolean  // source of truth
  isIndex?: boolean // rebuildable; never SoT
}

export const STORES: Store[] = [
  {
    name: "SwiftData",
    style: "hot episodic",
    answers: "On-device, append-first capture. Instant and local before any index catches up.",
    isHot: true,
    isSoT: true,
  },
  {
    name: "Realm",
    style: "live fanout",
    answers: "Real-time multi-device local spine so peers share one hot truth \u2014 without assuming iCloud. Still one write: memory.store.",
  },
  {
    name: "Obsidian SecondBrain",
    style: "document vault",
    answers: "Human-readable markdown \u2014 curated semantic SoT, git-auditable. Hot episodes materialize here; indexes rebuild from here.",
    isSoT: true,
  },
  {
    name: "memory.md",
    style: "document",
    answers: "Fast-recall fact files + pointer index for session context. Sometimes plain text in the prompt beats a vector hunt.",
  },
  {
    name: "claude-mem",
    style: "capture river",
    answers: "Auto-ingest of what happened, in order. Feeds Observe \u2014 not a client pick, not a second SoT.",
  },
  {
    name: "qdrant",
    style: "vector",
    answers: "Meaning search over knowledge-sync facts. Rebuildable similarity tier \u2014 not SoT, never client-visible.",
    isIndex: true,
  },
  {
    name: "graphify",
    style: "graph",
    answers: "Analytical graph of entities and relations \u2014 similar \u2260 related. Rebuild from curated inputs.",
    isIndex: true,
  },
  {
    name: "LadybugDB",
    style: "graph + vector",
    answers: "Hub graph + vector query over the vault. Different job from Qdrant. Rebuildable cache \u2014 sacred split: Ladybug \u2260 Qdrant.",
    isIndex: true,
  },
  {
    name: "PageIndex",
    style: "reasoning tree",
    answers: "Structure / TOC navigation over long docs \u2014 this section with provenance, not only fuzzy similarity.",
    isIndex: true,
  },
]

// Letta sits above the stores: the conversational librarian.
// The night (Dream / fleet consolidation) has its own conductor \u2014 not Letta.
export type Librarian = {
  name: string
  style: string
  role: string
  answers: string
  duties: string[]
}

export const LIBRARIAN: Librarian = {
  name: "Letta",
  style: "conversational",
  role: "The master librarian",
  answers: "Ask, refine, follow up \u2014 recall that holds a thread.",
  duties: [
    "Reads across every backing store on your behalf \u2014 one question fans out to all of them.",
    "Holds the thread across turns: context survives the follow-up, not just the first ask.",
    "The thread survives. The night belongs to Dream.",
  ],
}

// §5 \u2014 sequence diagrams rendered as animated flows on the site.
export type SeqParticipant = { id: string; label: string; sub?: string }
export type SeqStep = {
  from: string
  to: string
  label: string
  style?: "solid" | "dashed"
}
export type SeqDiagram = {
  id: string
  title: string
  subtitle: string
  participants: SeqParticipant[]
  steps: SeqStep[]
  note?: string
}

export const SEQUENCES: SeqDiagram[] = [
  {
    id: "curtain",
    title: "One write. One recall.",
    subtitle: "The curtain handles everything else.",
    participants: [
      { id: "client", label: "Client" },
      { id: "curtain", label: "Andromeda", sub: "curtain" },
      { id: "hot", label: "Hot memory" },
      { id: "dream", label: "Dream", sub: "materialize" },
    ],
    steps: [
      { from: "client",   to: "curtain", label: "memory.store",                        style: "solid"  },
      { from: "curtain",  to: "hot",     label: "seal and keep",                        style: "solid"  },
      { from: "hot",      to: "curtain", label: "id",                                   style: "dashed" },
      { from: "curtain",  to: "client",  label: "ok",                                   style: "dashed" },
      { from: "curtain",  to: "dream",   label: "project when ready",                   style: "dashed" },
      { from: "client",   to: "curtain", label: "memory.recall",                        style: "solid"  },
      { from: "curtain",  to: "hot",     label: "recent truth",                         style: "solid"  },
      { from: "curtain",  to: "curtain", label: "route \u00b7 structure \u00b7 graph \u00b7 meaning", style: "solid" },
      { from: "curtain",  to: "client",  label: "what matters \u00b7 provenance kept",  style: "dashed" },
    ],
  },
  {
    id: "vault",
    title: "Indexes may fail.",
    subtitle: "Sources must not vanish.",
    participants: [
      { id: "hot",   label: "Hot episodic" },
      { id: "vault", label: "SecondBrain" },
      { id: "graph", label: "graphify" },
      { id: "page",  label: "PageIndex" },
      { id: "vec",   label: "Qdrant", sub: "Ladybug" },
    ],
    steps: [
      { from: "hot",   to: "vault", label: "materialize curated note", style: "solid" },
      { from: "vault", to: "graph", label: "relations",                style: "solid" },
      { from: "vault", to: "page",  label: "structure",               style: "solid" },
      { from: "vault", to: "vec",   label: "meaning indexes",         style: "solid" },
    ],
    note: "indexes may fail \u00b7 sources must not vanish",
  },
]

// §10 \u2014 honest status. No greenwashing.
export const STATUS_BOARD: { status: Status; heading: string; items: string[] }[] = [
  {
    status: "shipped",
    heading: "Shipped",
    items: [
      "memory.recall / memory.store \u2014 SwiftData hot store + vault fallback",
      "memory.journal / session_dump",
      "project.state.* CRUD",
      "/checkpoint \u2192 /knowledge-sync \u2192 /close ritual",
      "The multibrain nightly conductor",
      "Autocache Anthropic LLM-proxy surface",
      "The capability curtain + MemoryKit",
      "AndromedaMCP \u2014 Swift-native MCP server for ast-grep tools",
      "Curtain standard adopted across capability surfaces",
      "AndromedaUI compiles standalone as its own module",
    ],
  },
  {
    status: "partial",
    heading: "Partial",
    items: [
      "MCP sprawl bent 55 \u2192 37 (shared dedupe host not shipped)",
      "HUD journal + visibility on a promotion branch",
      "Letta / Ladybug / Qdrant live on the Studio hub only",
    ],
  },
  {
    status: "spec",
    heading: "Specified, not built",
    items: [
      "Secrets broker runtime (slack_proxy / github_proxy)",
      "write.too \u2014 Cerebras-backed write capability (infer.write is only a deprecated alias into memory.store)",
      "MCP consolidate \u2014 one shared host",
      "SkillRegistry product surface",
      "Full multi-provider LLM router",
      "Fleet plist single-source-of-truth + typed mutate",
      "CloudKit end-to-end replication",
      "Photographic (CLIP) layer \u00b7 Swift dream runtime",
    ],
  },
]
