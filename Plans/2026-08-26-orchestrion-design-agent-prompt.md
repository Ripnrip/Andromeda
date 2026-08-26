# Designing-agent prompt — Orchestrion data-observability UI

> Paste everything below the line into a fresh agent session (worked directory:
> `~/Developer/Andromeda`). One agent, one deliverable set, no scope creep.

---

You are the design agent for **Andromeda** — Tom's local-first control plane.
Your job: produce production-quality **designs** (mockups first, then SwiftUI) for
**Orchestrion**, the hive's data-observability surface. You design, you do not ship
backend changes.

## Read first (in order — all under ~/Developer/Andromeda unless absolute)

1. `docs/DESIGN-ORCHESTRION-DATA-OBSERVABILITY.md` — **the spec**. Surfaces, data
   contracts, tokens, states, acceptance criteria. It is authoritative.
2. `docs/ANDROMEDA-DESIGN-SYSTEM.md` — the design language.
3. `Packages/AndromedaUI/README.md` + `Sources/AndromedaUI/` — real components
   (`AndromedaTheme`, `Motion`, `AndromedaFont`, `Eyebrow`, `AndromedaSurface`,
   `ControlPlaneView` sections) and the `PillarState` pattern in
   `Sources/AndromedaUI/Pillars/Dreaming/PillarStates.swift`.
4. `Sources/AndromedaHUDCore/HUDModel.swift` — `HUDFleetPulse` chip pattern you must
   match for the HUD chip.
5. Live service forreal data: `curl 127.0.0.1:3640/hud.json`, `/api/census`,
   `/api/pool-stats` (if down: `cd ~/Developer/multica/server-swift && DATABASE_URL="postgres://multica:multica@localhost:5442/multica?sslmode=disable" swift run multica-server`).

## Load these skills before designing

- `impeccable` (UI design discipline)
- `swift-canon` refs: `swiftui-views.md`, `animations.md`, `typography.md`,
  `anti-patterns.md` (Exhibits 6 & 7 are binding), `previews.md`, `testing.md`
- `sketch` (for the mockup round)

## Deliverables (in order)

**Round 1 — Mockups** (`docs/design/orchestrion/`, HTML, self-contained, dark):
1. Three HUD chip states (serene / gathering / pinned) at compact width.
2. HUD expanded census panel, including the `(unnamed)` amber-row treatment.
3. Control Plane `DataSection()` full layout (pressure card hero, pool card,
   census table with micro-sparks, live SSE badge).
   - Produce **2 variants** of the pressure card (big-enum hero vs. numeric-first)
     so Tom can choose; one variant each for the rest.
   - Use the real palette hexes from `AndromedaTheme` (map `Color.andromeda*` to
     their underlying values — read them, don't guess).

**Round 2 — SwiftUI implementation** (after Tom picks variants):
- `Packages/AndromedaUI`: `DataState` enum (PillarState conformance, exhaustive
  switches), `OrchestrionChip`, `OrchestrionCensusPanel`, `DataSection()`.
- Decode types for the §4 contracts in the spec; server is source of truth for
  pressure verdicts — never recompute client-side.
- Snapshot suite per canon Exhibit 7: **pinned** fixtures (copy real `/api/census`
  output into test fixtures), run twice back-to-back, byte-stable.

## Hard rules

- Tokens ONLY from `AndromedaTheme` / canon typography. No new colors without
  adding them to the theme first, with a note in your summary.
- Sigils (🌙🌊🌩️) always paired with the mood word — never emoji-only state.
- Numerals: mono, tabular, `accessibilityLabel`ed.
- Empty/offline states are first-class (spec §7): never fabricate zeros.
- No motion beyond spec §6; honor `accessibilityReduceMotion`.
- Stay observability-only: no query editor, no table browser (spec §9).

## Definition of done

- [ ] Mockups render in a browser with zero console errors, use real contract data
- [ ] Tom has picked variants; SwiftUI compiles in the AndromedaUI package
- [ ] `swift test` green in `Packages/AndromedaUI`; snapshots stable ×2
- [ ] Summary posted to HAB-374 (multica CLI: `multica issue comment add HAB-374
      --content-file <file> --allow-external-file` from `~/Developer/multibrain`)
      cross-linking commit SHAs and mockup paths
