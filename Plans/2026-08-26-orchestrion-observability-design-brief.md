# Orchestrion — Data Observability Surface · Design Brief (2026-08-26)

> For design work on the Orchestrion feature (Multica server-swift Phase 0, HAB-374).
> Product+engineering context: `multibrain/docs/POSTGRES-PROCESS-NAMING-2026-08-26.md`,
> `multica/server-swift/PLAN.md`. Graph: `multica/server-swift/graphify-out/graph.html`.

## What Orchestrion is (product sense)

The hive's **data-layer observability pillar**: a Swift/Hummingbird service that watches
the Postgres fleet (today: `multica-pg17` on the Studio host), enforces the naming
convention born from the 2026-08-26 incident (every instance `cluster_name`-named, every
connection `application_name`-stamped), and exposes the answer to *"who is connected to
my database, under what name, and is anyone drowning?"* — in one glance.

It is **not** a DB admin tool (no query editor). It is the Control Plane's answer to
"data" the way MemorySection answers "memory" and FleetPulse answers "fleet".

## The three surfaces (where it lives)

### 1. HUD chip (compact) — the glance
Pattern: `HUDFleetPulse` chip in `AndromedaHUDCore/HUDModel.swift` — headline only.
Orchestrion chip = `🌙 serene · 27/35 conns` with the Pressure sigil
(`🌙 serene / 🌊 gathering / 🌧️ pinned`). Tap/expand → full panel. Data source:
`GET :3640/hud.json` (already shipping, stable keys: app, status, pressure, sigil,
totalConns, maxConns, spark[30]).

### 2. HUD expanded panel (medium) — the census
While holding the HUD open on the chip: connection census rows
(`application_name → souls`, exactly `/api/census`: multica-server 25, unnamed 5,
multica-swift-server 2), sparkline of total conns, high-water marker, ping ms.
One-alert rule: `pinnedAtMax` promotes the chip to `andromedaAmber` + attention count,
matching FleetPulse's attention semantics.

### 3. Control Plane section (full) — the dashboard
`ControlPlaneView` gains a `DataSection()` alongside Memory/Models/Search (capability
list pillar: **Data**). Contents = the shipped `/dashboard` redesigned in AndromedaUI:

- **Pressure card** — big `PillarState`-style enum treatment (serene/gathering/pinned)
  with exhaustive-switch colors: teal / glow / amber (`AndromedaBrand` palette).
- **Pool card** — total/max, dreaming (idle), on stage, in line, high water
  (`cpDisplay` numerals, `AndromedaFont.mono`).
- **Census table** — grouped by application_name; `(unnamed)` rows flagged amber
  (the incident's villain, forever visible).
- **Live sparkline** — `Motion.sweep`/`wave` over the 30-sample ring; SSE-fed
  (`/api/events`), no polling.
- **Detail drawer** — per-app expand: acquire deltas, empty-acquire counter, ping.

## Design tokens (AndromedaUI, exact references)

| Token | Source | Use |
|---|---|---|
| `Color.andromedaTeal` | AndromedaTheme | serene |
| `Color.andromedaGlow` / `.andromedaLive` | AndromedaTheme | gathering |
| `Color.andromedaAmber` | AndromedaTheme | pinned-at-max, `(unnamed)` census rows |
| `Motion.breathe` / `.pulse` | AndromedaUI Motion | chip alive-ness; pinned = pulse |
| `AndromedaFont.mono` + `.cpMeta()` | typography | all numerals (tabular) |
| `Eyebrow` | typography | section labels ("POOL OF SOULS · ORCHESTRION") |
| `PillarState` protocol | `Pillars/Dreaming/PillarStates.swift` | model `DataState` enum after `MemoryState` (color/caption/detail per case, exhaustive switches — Exhibit 6 discipline) |

SnapshotTesting note (Exhibit 7): pin the spark sample data — never random fixtures.

## Access & setup (operators)

- Run: `cd multica/server-swift && swift run multica-server` with
  `DATABASE_URL` (+ optional `PORT=3640`, `DATABASE_MAX_CONNS`, `TELEMETRY_INTERVAL_SECONDS`).
- Endpoints: `/health` `/api/pool-stats` `/api/census` `/api/events` (SSE) `/metrics`
  `/hud.json` `/dashboard`. Bind 127.0.0.1 only (canon security rule).
- Phase 1+ wiring: HUD chips poll `/hud.json` (or subscribe `/api/events`);
  Control Plane `DataSection` embeds; `andromeda-runtime` health checks adopt `/health`.

## Naming

Product name stays **Orchestrion** (mechanical organ — many voices, one conductor;
fits Andromeda's instrument metaphors). Pillar id: `data.observe`. Capability string
for HUD: extend `HUDCapabilityID` with `dataPulse = "data.pulse"` when wiring.

## Tracker

HAB-374 (Phase 0 done) · Phase 1 read-slice next · design work: this brief.
