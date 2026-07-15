# Anima Memory / Andromeda — Project Links

Short link map for the Anima memory + Andromeda control-plane workstream.
Updated: 2026-07-15 (operator routing vs client capabilities). No secrets in this file.

> **Operator routing vs client capabilities (locked 2026-07-15)**  
> This file’s Linear ∪ Multica ∪ Slack routing tables are for **fabric operators and meta-agents** — humans and agents that maintain the hive tracker fabric.  
> **Andromeda app clients and satellite agents must NOT see this complexity.** They call stable capability IDs only: `project.state.list` / `get` / `create` / `update` (and `memory.*`, `infer.write`). Andromeda Observe→Evolve→Execute→Internalize owns Linear/Multica/Slack/n8n provider selection behind the curtain — same pattern as inference hiding Cerebras/OpenRouter. Never put Linear/Multica/n8n brands in end-user agent tool menus.

## Routing guide (what goes where)

**Stack roles (do not invent a fourth tracker) — operator-facing:**

| Layer | Role |
|-------|------|
| **Linear** (`BIN-*`) | Issue workflow, status, assignee, labels, agent proof comments, PR links |
| **Multica Habitat** (`HAB-*`) | Studio/hive project board, agent assignment in Habitat UI, portfolio view |
| **Slack `#projects`** (`C0BHYQQDETA`) | Human-visible kickoffs, milestones, reminders — not a ticket database |

### Routing order (default)

1. **Slack mention of a real / actionable issue** → create **Linear first** (status, assignee, labels, repo/PR links).
2. Then create/link a **Multica** issue that references the Linear ID (`BIN-*`).
3. Agent pickup: read **Linear + Multica + repo links** before starting work.
4. **Project-level portfolio / Habitat board** → Multica is primary (still cross-link Linear for engineering).
5. **Human-only / physical / App Store / macOS GUI** that agents cannot finish E2E → **Linear only** (optional Slack reminder); Multica optional note only.

Never triple-duplicate the same write-up across all three. Cross-link IDs.

### Permutation table

| Situation | Slack | Linear | Multica | Why | Agent pickup? |
|-----------|-------|--------|---------|-----|---------------|
| **Andromeda overall project** (fleet: Habitat VM, hosts, satellites) | Milestone / kickoff only | ✅ Manage + follow | ✅ Manage + follow | Portfolio spans hive; both boards stay aligned | Yes — both IDs + docs |
| **Issue mentioned in Slack** (user / friend / agent) | Origin thread; don't treat as SoT | ✅ **First** | ✅ Then, linked to `BIN-*` | Agents need status/labels/proof on Linear; Habitat needs assignable HAB | Yes — Linear then Multica |
| **macOS host OS update / App Store / GUI-only** | Optional human reminder | ✅ Likely **Linear only** | ❌ Usually skip (optional note) | Agent cannot finish E2E for the human | Partial — remind human |
| **MemoryKit / Anima proof or code PR** | When milestone ships | ✅ + link PR | ✅ + link PR / HAB | Proof ladder lives on Linear; Habitat tracks delivery | Yes |
| **Invisible LaunchAgent / MCP sprawl / infra fix agents *can* do** | Start + done in `#projects` | ✅ | ✅ | Agent-executable fleet work needs both boards | Yes |
| **Spend kill / secret rotation** | **Only if human action needed** — never paste secrets | ✅ Security / spend issue | ✅ If fleet-wide; else optional | Contain blast radius; no secret leakage in Slack | Yes (redact) |
| **Book / satellite-only ops** | Optional | ✅ | ✅ Tag `host=satellite` (or Book) | Hive-visible but scoped to satellite | Yes — respect host tag |
| **Mac Mini isolated lane** | ❌ No hive default | ✅ | ❌ Or Multica tagged `isolated` only | Mini stays off hive Multica default | Linear only (or isolated HAB) |
| **Pure docs / changelog "twinkie"** | Rarely | ✅ Optional / skip | ❌ Skip unless project milestone | Docs noise ≠ Habitat board clutter | Usually no |
| **"Thinking out loud" Slack chatter** | Stay in thread | ❌ Don't auto-create | ❌ Don't auto-create | Not an issue until someone marks actionable | No until promoted |
| **n8n workflow / Habitat orchestration** | Milestone optional | ✅ For engineering tasks | ✅ **Primary** | Orchestration is Habitat-native; eng still on Linear | Yes — Multica first |
| **Friend share / external visibility** | Careful public phrasing | ⚠️ Visibility careful | ❌ **Never** private internals | No hive internals outside; cloak Linear if needed | External: no Multica |

### Quick examples (encode these)

1. **Andromeda overall** → Multica **+** Linear (both); Slack for kickoffs/milestones.
2. **Slack raises a bug** → Linear first → Multica linked to `BIN-*` → agent picks up with full context.
3. **Studio needs a macOS update** → Linear only (human does the clicky bits); Slack reminder OK.

## Linear

- **Project:** [Anima Memory / Andromeda](https://linear.app/binary-bros/project/anima-memory-andromeda-24f49e6f052c)
- **Project ID:** `df11aac0-8284-48ac-b2b8-b85838123938`
- **Team:** Binary-bros (`BIN`)
- **Issues:** BIN-21 … BIN-27 (canonical tracker); **BIN-29** MCP sprawl registry/dedupe

## Multica (Studio-local)

- **Project:** [Anima Memory / Andromeda](https://studio.capybara-loggerhead.ts.net/habitat/projects/17237130-3eef-4562-89dd-9269caa371ba)
- **Local UI:** http://127.0.0.1:3636/habitat/projects/17237130-3eef-4562-89dd-9269caa371ba
- **API:** http://127.0.0.1:3637 (`/health` → `{"status":"ok"}`)
- **Project ID:** `17237130-3eef-4562-89dd-9269caa371ba`
- **Workspace:** Habitat (`5bc5bd70-8e83-41db-8a5b-46ccfc8b5422`, slug `habitat`)
- **CLI:** `multica project get 17237130` / `multica issue list --project 17237130`

### Multica issues (index → Linear, not duplicates)

| Multica | Role | Linear |
|---------|------|--------|
| HAB-34 | MemoryKit proven (hot/seal/capture/recall/cloak) | BIN-21…25 |
| HAB-35 | Surface area inventory | BIN-24 |
| HAB-36 | LaunchEntity registry | BIN-26 |
| HAB-37 | HealthSnapshot telemetry | BIN-27 |
| HAB-38 | CloudKit cold sync | BIN-22 |
| HAB-39 | NEXT: Skills / MCP / CLI registries | (follow-on) |
| HAB-40 | NEXT: n8n wiring | (follow-on BIN-27) |
| HAB-41 | NEXT: multibrain-bar integration | (follow-on) |
| HAB-43 | MCP sprawl: registry + dedupe invisible `npm exec` | **BIN-29** |

### Multica resources

- GitHub `Ripnrip/multibrain` @ `anima-memory` (stopgap → `main` via PR; Changelog conflict)
- GitHub `Ripnrip/Andromeda` @ `main` (Anima stopgap merged 2026-07-15, SHA `b968604`)
- Local directory: `/Users/admin/Developer/multibrain` (daemon-attached)

## Slack

- **Workspace:** agent-habitat.slack.com
- **Channel:** `#projects` (`C0BHYQQDETA`) — primary coordination (no dedicated Multica channel required)
- **Kickoff/progress:** already posted in `#projects`; Multica-link update posted 2026-07-15

### Multica ↔ Slack connection path

Multica supports **Slack BYO (bring-your-own) app install** for agent chat channels (not a Linear-style project sync). On this Studio host:

1. Multica API/UI: `http://127.0.0.1:3637` / `http://127.0.0.1:3636` (Tailscale: `https://studio.capybara-loggerhead.ts.net`)
2. Env: `MULTICA_SLACK_SECRET_KEY` in `~/Developer/multica/.env` (do not commit)
3. **Status (2026-07-15):** Habitat workspace Slack install is **already configured** (`GET /api/workspaces/{workspace_id}/slack/installations` → `configured: true`, Slack team `T0BCQQNF14P` / agent-habitat)
4. Re-install / BYO path: `POST /api/slack/install/byo` (via Multica UI workspace settings → Slack)
5. Human project updates stay in `#projects`; Multica issues are for Studio-local agent assignment

There is **no native Linear sync** in Multica on this stack — keep Linear as source of truth and Multica issues as linked indexes (HAB-34…38).

## GitHub

| Repo | Branch | Stopgap status (2026-07-15) |
|------|--------|-----------------------------|
| [Ripnrip/multibrain](https://github.com/Ripnrip/multibrain/tree/anima-memory) | `anima-memory` → `main` | PR fallback — merge blocked by `Changelog.md` conflict with `origin/main` |
| [Ripnrip/Andromeda](https://github.com/Ripnrip/Andromeda) | `main` | **Anima stopgap on `main`** at `b968604` (FF from `anima-memory`; branch kept) |

`anima-memory` retained in both repos for the next wave.

## Related docs

- `docs/ANDROMEDA-SURFACE-AREA.md`
- `docs/MCP-SPRAWL-PROBLEM.md` — Activity Monitor evidence + host inventory (THE MCP problem)
- `docs/assets/mcp-sprawl-activity-monitor-2026-07-15.png`
- `docs/FLEET.md`
- `docs/MEMORY-ONEPAGER.md`
