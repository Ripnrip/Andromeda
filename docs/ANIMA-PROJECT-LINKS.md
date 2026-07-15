# Anima Memory / Andromeda — Project Links

Short link map for the Anima memory + Andromeda control-plane workstream.
Updated: 2026-07-15 (Anima stopgap consolidation). No secrets in this file.

## Linear

- **Project:** [Anima Memory / Andromeda](https://linear.app/binary-bros/project/anima-memory-andromeda-24f49e6f052c)
- **Project ID:** `df11aac0-8284-48ac-b2b8-b85838123938`
- **Team:** Binary-bros (`BIN`)
- **Issues:** BIN-21 … BIN-27 (canonical tracker)

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
- `docs/FLEET.md`
- `docs/MEMORY-ONEPAGER.md`
