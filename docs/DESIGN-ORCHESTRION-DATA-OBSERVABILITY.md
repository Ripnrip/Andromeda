# Orchestrion — Data Observability · Design Doc

**Status**: ready for design · **Tracker**: HAB-374 (Phase 0 shipped) · **Pillar**: `data.observe`
**Brief**: `Plans/2026-08-26-orchestrion-observability-design-brief.md` (product story)
**Design system**: `ANDROMEDA-DESIGN-SYSTEM.md` + `Packages/AndromedaUI` (source of truth for tokens)

---

## 1. The product in one line

> *"Who is connected to my database, under what name, and is anyone drowning — at a glance."*

Orchestrion productizes the 2026-08-26 postgres-naming incident: a Swift/Hummingbird
service (already live on `:3640`) that names every connection at birth and exposes pool
health, a connection census, and live pressure telemetry. This doc specifies its UI
across Andromeda's three zoom levels.

**What it is NOT**: a database admin tool. No query editor, no table browser, no DDL.
Observation only — the Control Plane answers "data" the way it answers "memory" and "fleet".

## 2. Users & jobs

| User | Job | Surface |
|---|---|---|
| Operator (Tom, daily) | "Is the hive's data layer healthy right now?" | HUD chip glance |
| Operator (investigating) | "An app feels slow — is its pool pinned?" | HUD expanded → census |
| Agent / meta-operator | "What changed in connection pressure?" | Control Plane DataSection, history |
| Future (Phase 1+) | Read-slice API parity monitoring | same surfaces, new feeds |

## 3. The three surfaces

### 3.1 HUD chip — the glance (compact)

Follows the **`HUDFleetPulse`** chip pattern (`Sources/AndromedaHUDCore/HUDModel.swift`):
headline only, one line, no roster.

```
┌──────────────────────────────────┐
│ 🌊 multica-pg17 · 27/35 · gathering │   ← sigil · instance · conns · mood word
└──────────────────────────────────┘
```

- **Serene** (`🌙`): `andromedaTeal` tint — default state.
- **Gathering** (`🌊`): `andromedaGlow` — waiters > 0 or empty-acquires rising.
- **Pinned** (`🌩️`): `andromedaAmber` + `Motion.pulse` — pool at max with a line formed.
  Promotes to attention semantics exactly like FleetPulse's `attentionCount`.
- Numerals: `AndromedaFont.mono`, tabular. Instance name in `.cpMeta()`.
- Data: poll `GET :3640/hud.json` (5s) or subscribe `GET :3640/api/events` (SSE).
- Expand gesture → surface 3.2.

### 3.2 HUD expanded panel — the census (medium)

Frosted results panel below search (the `HUDResultsView` pattern).

```
┌─ ORCHESTRION · CENSUS ──────────────────┐
│  ▁▂▂▃▃▄▅▅▆▆▅▄▃▃  total conns, 30 ticks  │  ← sparkline (ring samples)
│                                          │
│  multica-server        25  ● on stage 1  │  ← census row: name · souls · state
│  multica-swift-server   2  ● dreaming 2  │
│  (unnamed)              5  ⚠ flag amber  │  ← the incident's villain, forever visible
│                                          │
│  ping 1.4ms · high water 9 · Δ 27 acq    │  ← meta line, .cpMeta()
└──────────────────────────────────────────┘
```

- Census rows grouped by `application_name` (source: `/api/census`).
- `(unnamed)` rows tinted `andromedaAmber` — a naming-convention violation is a
  first-class visual event, not noise.
- Sparkline: `Motion.sweep` ingress on new sample; no animation loop on static display.
- Row tap → detail drawer (acquire deltas, empty-acquire count, ping history) — Phase 1.

### 3.3 Control Plane `DataSection()` — the dashboard (full)

A routed section in `ControlPlaneView`, sibling of `MemorySection()` / `ModelsSection()`.

```
┌─ DATA ─────────────────────────────────────────────────┐
│ Eyebrow: POOL OF SOULS · ORCHESTRION                    │
│                                                         │
│ ┌─ PRESSURE ──────────┐  ┌─ POOL ────────────────────┐  │
│ │  🌙 SERENE          │  │  total      2 / 8         │  │
│ │  (big enum state)   │  │  dreaming   2   on stage 0│  │
│ │  teal field,        │  │  in line    0   high water│  │
│ │  Motion.breathe     │  │  empty acquires  0        │  │
│ └─────────────────────┘  └───────────────────────────┘  │
│                                                         │
│ ┌─ CENSUS ───────────────────────────────────────────┐  │
│ │ name                souls    state       trend      │  │
│ │ multica-server        25    pinned ⚠    ▂▃▄▅▆▆     │  │
│ │ multica-swift-server   2    serene       ▁▁▁▁▁      │  │
│ │ (unnamed)              5    —           ▁▁▁▁▁  ⚠   │  │
│ └───────────────────────────────────────────────────┘  │
│  [ live · SSE ]  ·  latency 1.4ms  ·  120-sample ring  │
└─────────────────────────────────────────────────────────┘
```

- **Pressure card**: the hero. `DataState` rendered as a big PillarState (see §5).
- **Pool card**: `cpDisplay` numerals, mono, tabular.
- **Census table**: sortable by souls; per-row 8-tick micro-spark (from ring samples).
- Live badge: dot + `andromedaLive` when SSE connected; gray + "polling" fallback.
- Full history (120 samples) with day-scrub is Phase 1; ship 30-tick now.

## 4. Data contracts (live, stable)

`GET /hud.json` →
```json
{ "service": "orchestrion", "generatedAt": "…",
  "tile": { "app": "multica-swift-server", "status": "ok",
            "pressure": "serene", "pressureSigil": "🌙",
            "totalConns": 2, "maxConns": 8, "spark": [2,2,2] } }
```

`GET /api/census` →
```json
[ { "applicationName": "multica-server", "souls": 25 },
  { "applicationName": "(unnamed)", "souls": 5 },
  { "applicationName": "multica-swift-server", "souls": 2 } ]
```

`GET /api/events` (SSE) → `event: pool-sample` / `data: {stats, delta, pressure,
pressureSigil, pingMs}` every 15s (configurable).

`GET /api/pool-stats` → envelope with `current` + full `samples[]` ring (120).

## 5. State model

Model after `MemoryState` in `Pillars/Dreaming/PillarStates.swift` — enum with exhaustive
switches for color/caption/detail (canon Exhibit 6: no rawValue concatenation):

```swift
public enum DataState: String, PillarState, CaseIterable {
    case serene, gathering, pinnedAtMax     // mirrors server Pressure verbatim
    // color: teal / glow / amber · caption per case · detail carries numbers
}
```

Derived client-side from `pressure` + `waiters`/`totalConns` in the payloads — the server
is the single source of truth for the verdict; the client never re-computes it.

## 6. Tokens (exact)

| Token | Value here |
|---|---|
| `Color.andromedaTeal` | serene / healthy rows |
| `Color.andromedaGlow`, `.andromedaLive` | gathering, live SSE badge |
| `Color.andromedaAmber` | pinned, `(unnamed)` rows, attention |
| `Color.andromedaPanel`, `.andromedaInk` | cards, text |
| `Motion.breathe` | Pressure card ambient life |
| `Motion.pulse` | pinned chip attention |
| `Motion.sweep` | sparkline ingress |
| `AndromedaFont.mono` + `.cpMeta()` / `.cpDisplay()` | all numerals & meta |
| `Eyebrow("POOL OF SOULS · ORCHESTRION")` | section header |
| `AndromedaSurface()` | card container |

## 7. States & edge cases

| Case | Treatment |
|---|---|
| Service down (no :3640) | chip grays out: `◇ orchestrion offline`; panel shows retry, never fabricates zeros |
| SSE drop | live badge → "polling" fallback; reconnect with backoff; no data gap flash |
| Empty ring (fresh boot) | sparkline area shows `✨ warming up` until first sample |
| `(unnamed)` present | amber row + count in chip attention (the convention's alarm bell) |
| Many apps (>8 rows) | census virtualizes; "…+N more" in HUD panel |
| Pressure pinned | amber + pulse; panel auto-orders pinned rows first |

Accessibility: sigils always paired with text mood word (never emoji-only state);
numerals `accessibilityLabel`ed ("27 of 35 connections, pressure gathering");
`accessibilityReduceMotion` honored (canon: no ambient motion when reduced).

## 8. Acceptance criteria

1. All three surfaces render from the live contracts in §4 with zero stubs.
2. `DataState` derivations are exhaustive switches; no stringly-typed pressure.
3. Snapshot suite: two back-to-back runs byte-stable — pinned sample data (canon
   Exhibit 7: no RNG fixtures, no unpinned `.task` reveals).
4. `(unnamed)` census rows are visually distinct in light+dark, 100% zoom, and
   accessibility audit.
5. HUD chip ≤ 1 line at compact width (HUD constraints); Control Plane section
   navigable via sidebar `Data`.

## 9. Out of scope (this round)

Query editor · schema browser · multi-instance federation (design the card so a
second instance can join the census later) · per-user authz (loopback-only per canon).

## 10. References

- Live service: `multica/server-swift` (run `swift run multica-server`, PORT=3640)
- Incident: `multibrain/docs/POSTGRES-PROCESS-NAMING-2026-08-26.md`
- Patterns: `HUDFleetPulse` · `HUDResultsView` · `MemorySection` · `PillarStates.swift`
- Code graph: `multica/server-swift/graphify-out/graph.html`
