import type { Status } from "./pillars"

export type MemoryLayer = {
  n: string
  name: string
  intent: string
  status: Status
  differentiator?: boolean
}

// §3 — the eight layers of memory (Anima). Integrity / Awareness / Dream are the differentiators.
export const MEMORY_LAYERS: MemoryLayer[] = [
  { n: "01", name: "Episodic", intent: "\u201cWe talked Tuesday.\u201d Timed, ordered, compactable capture.", status: "shipped" },
  { n: "02", name: "Semantic", intent: "\u201cChapter 3 has the state machine.\u201d Structure-first recall.", status: "partial" },
  { n: "03", name: "Photographic", intent: "\u201cI\u2019ve seen that diagram.\u201d Vision recall over screenshots.", status: "spec" },
  { n: "04", name: "Integrity", intent: "\u201cCan I trust this memory?\u201d Merkle proofs over memory trees.", status: "partial", differentiator: true },
  { n: "05", name: "Meditation", intent: "Morning reflection that reads the dream journal and sets intention.", status: "partial" },
  { n: "06", name: "Soul", intent: "Presence, mood, relationship depth \u2014 context, not a chatbot.", status: "partial" },
  { n: "07", name: "Awareness", intent: "Speak only when it matters. Silence is a feature.", status: "partial", differentiator: true },
  { n: "08", name: "Dream", intent: "Night: Review \u2192 Shadow \u2192 Insight \u2192 Integration.", status: "partial", differentiator: true },
]

// §4 — one job per store. Ordered along the exact \u2192 meaning \u2192 relationship spectrum.
export type Store = {
  name: string
  style: string
  answers: string
}

export const STORES: Store[] = [
  { name: "memory.md", style: "document", answers: "What do I already know about X, in plain text?" },
  { name: "claude-mem", style: "relational + vector", answers: "What actually happened, in order, across sessions?" },
  { name: "Obsidian SecondBrain", style: "document vault", answers: "Let me read and browse my knowledge like a notebook." },
  { name: "qdrant", style: "vector", answers: "Find the note about X by meaning, not keywords." },
  { name: "graphify", style: "graph", answers: "What is connected to what?" },
  { name: "LadybugDB", style: "graph + vector", answers: "Query the whole vault analytically, fast." },
]

// Letta sits above the stores: the conversational layer that reads across every
// backing store on your behalf and drives the nightly Dream cycle.
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
  role: "The master librarian & dreamer",
  answers: "Ask, refine, follow up — recall that holds a thread.",
  duties: [
    "Reads across every backing store on your behalf, so one question fans out to all of them.",
    "Holds the thread across turns — context survives the follow-up, not just the first ask.",
    "Drives the nightly Dream cycle: Review → Shadow → Insight → Integration, so the morning is smarter.",
  ],
}

// §10 — honest status. No greenwashing.
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
      "MCP consolidate \u2014 one shared host",
      "SkillRegistry product surface",
      "Full multi-provider LLM router",
      "Fleet plist single-source-of-truth + typed mutate",
      "CloudKit end-to-end replication",
      "Photographic (CLIP) layer \u00b7 Swift dream runtime",
    ],
  },
]
