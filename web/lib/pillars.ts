import {
  Brain,
  Server,
  Boxes,
  Waypoints,
  KeyRound,
  Radar,
  type LucideIcon,
} from "lucide-react"

export type Status = "shipped" | "partial" | "spec"

export const STATUS_LABEL: Record<Status, string> = {
  shipped: "Shipped",
  partial: "Partial",
  spec: "Specified",
}

export const STATUS_GLYPH: Record<Status, string> = {
  shipped: "●",
  partial: "◐",
  spec: "○",
}

export type Pillar = {
  index: number
  key: string
  name: string
  short: string
  icon: LucideIcon
  status: Status
  tagline: string
  description: string
  capabilities: string[]
}

export const PILLARS: Pillar[] = [
  {
    index: 1,
    key: "memory",
    name: "Memory",
    short: "Anima",
    icon: Brain,
    status: "partial",
    tagline: "Graph-native memory fabric",
    description:
      "Append-first episodic capture with a curated semantic vault. Recall and store resolve across hot store, vault, and rebuildable indexes — provenance preserved.",
    capabilities: ["memory.recall", "memory.store", "memory.journal", "infer.write", "project.state.*"],
  },
  {
    index: 2,
    key: "mcp",
    name: "MCP Host",
    short: "Consolidate",
    icon: Server,
    status: "partial",
    tagline: "One host, not 50 subprocesses",
    description:
      "A single supervised MCP host replacing per-terminal npm sprawl. Registry, health monitor, and subprocess containment bend the tool surface back into view.",
    capabilities: ["mcp.registry", "mcp.scan", "mcp.health"],
  },
  {
    index: 3,
    key: "skills",
    name: "Skills",
    short: "Registry",
    icon: Boxes,
    status: "spec",
    tagline: "A home for agent skills",
    description:
      "One registry surface for skill discovery and invocation — no more tribal hunting through scattered skill directories across machines.",
    capabilities: ["skill.list", "skill.invoke"],
  },
  {
    index: 4,
    key: "llm",
    name: "LLM Proxy",
    short: "Router",
    icon: Waypoints,
    status: "partial",
    tagline: "Capabilities in, providers out",
    description:
      "Clients ask for capabilities, never provider brands. The live Autocache Anthropic surface injects prompt-cache breakpoints and returns ROI analytics.",
    capabilities: ["infer.write", "route.capability", "usage.metrics"],
  },
  {
    index: 5,
    key: "secrets",
    name: "Secrets Broker",
    short: "Vault",
    icon: KeyRound,
    status: "spec",
    tagline: "Keys never touch client env",
    description:
      "Stable proxy IDs resolve to Keychain-backed secrets server-side. Satellite agents run env-scrubbed; the broker injects credentials at call time.",
    capabilities: ["slack_proxy", "github_proxy", "write.tool"],
  },
  {
    index: 6,
    key: "fleet",
    name: "Fleet Runtime",
    short: "Observe",
    icon: Radar,
    status: "partial",
    tagline: "Every daemon on the record",
    description:
      "LaunchAgents, plists, and launchd become first-class entities with a health pulse and telemetry. Observe now; typed Swift mutation lands with the installer.",
    capabilities: ["fleet.roster", "fleet.health", "fleet.telemetry"],
  },
]

export type CurtainRow = {
  id: string
  hides: string
  neverSees: string
}

export const CURTAIN: CurtainRow[] = [
  {
    id: "memory.recall",
    hides: "SwiftData hot store, vault, Ladybug, Qdrant",
    neverSees: "Store paths, index brands",
  },
  {
    id: "infer.write",
    hides: "Autocache, gateway, model registry, fallbacks",
    neverSees: "Anthropic, Cerebras, OpenRouter, API keys",
  },
  {
    id: "project.state.*",
    hides: "Linear ∪ Multica ∪ Slack fanout",
    neverSees: "Tracker brand names in menus",
  },
  {
    id: "slack_proxy",
    hides: "Slack Web API via broker; token from Keychain",
    neverSees: "SLACK_BOT_TOKEN, raw env",
  },
  {
    id: "github_proxy",
    hides: "GitHub API via broker",
    neverSees: "GITHUB_TOKEN, gh auth dumps",
  },
  {
    id: "write.tool",
    hides: "Fast codegen inference via proxy",
    neverSees: "Provider brand + API key in env",
  },
]

export const MISSION_LOOP = [
  { stage: "Observe", detail: "Capture events, outcomes, tool calls, and decisions." },
  { stage: "Evolve", detail: "Evaluate outcomes; improve prompts, skills, routing." },
  { stage: "Execute", detail: "Dispatch controlled work to agents, tools, providers." },
  { stage: "Internalize", detail: "Convert outcomes into durable graph knowledge." },
]
