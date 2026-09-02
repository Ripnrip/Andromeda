# Process Guardian — product brief

**Status:** spec (engine shipped, PR #62) · **Date:** 2026-08-26
**Audience:** design (HUD surfaces) + operators
**Engine:** `Packages/AndromedaGuardian` · **Tickets:** HAB-369/370/371/372/375/376

## 1. What it is, in one breath

**The Guardian is Andromeda's immune system for its own host.** Every agent
session on the fleet spawns helper processes — MCP children, xcodebuild
runs, Xcode SourceControl daemons — and macOS never cleans up after them.
Left alone, they accumulate until the machine drowns (the 2026-08-25 peak:
~30 GB of duplicate Xcode daemons + 45 MCP clones → 61.86 GB swap →
everything Not Responding). The Guardian watches the process table, knows
what each process *is*, and reaps the ones that are recoverable by
construction — while being structurally incapable of touching anything that
isn't.

It is not a task manager. It's a **policy engine with a conscience**: every
kill is typed, justified, logged, and auditable; every protection is
structural, not conventional.

## 2. Where it sits in Andromeda (the six pillars)

Andromeda is **Memory + MCP host + Skills + LLM proxy + Secrets broker +
Fleet runtime**. The Guardian is the **Fleet runtime** pillar's mutation
surface made real:

- **Fleet observe** already exists: `LaunchEntity` / `FleetObserveReport`
  (what's supposed to be running). The Guardian adds the census of what's
  *actually* running — and the delta is the failure mode.
- **Fleet mutate** is the BIN-101 law: typed Swift installs/mutations, never
  bash. The Guardian is the second mutation surface (after the typed
  installer): process lifecycle decisions executed by policy, in Swift, with
  telemetry.

Product-side, it also *feeds* the other pillars' reliability: the Memory
and MCP-host pillars die first when the host swaps to death — the Guardian
is what keeps the floor under them.

## 3. Surfaces — where you see, access, and set it up

| Surface | What it does | Who it's for | Status |
|---|---|---|---|
| **LaunchAgent** (`com.andromeda.process-guardian`) | Autonomous sweep every 10 min + on load. The default mode: nobody thinks about it, the host stays healthy. | everyone (zero-touch) | HAB-370/375 |
| **CLI** (`andromeda guardian sweep [--dry-run]`, `guardian status`, `guardian install/uninstall`) | Manual sweeps, last-sweep view, install control | operators | HAB-370 |
| **HTTP** (`GET /guardian/status`, `/census`, `/telemetry`, `POST /guardian/sweep`) | Programmatic control from other services | fleet tooling | spec shipped (guardian.yaml) |
| **SSE** (`GET /guardian/events`) | Live sweep events — one frame per sweep | dashboards, HUD | spec + broadcaster shipped |
| **MCP** (`guardian.status` / `guardian.census` / `guardian.sweep`) | Agent-visible tools (capability-hiding law: stable IDs, no internals) | agents | spec shipped |
| **HUD** | See §4 — the visual home | humans glancing at the machine | **design — this brief** |

Setup (once HAB-370 lands): `andromeda guardian install` → typed Swift
launchd install (no launchctl-by-hand, per BIN-101) → the guardian runs
autonomously. `guardian uninstall` removes it cleanly. Everything it does
lands in `~/.andromeda/logs/guardian.jsonl`.

## 4. The HUD question — where the Guardian should live

**Recommendation: both tiers — a docked chip + an expanded panel — matching
the existing HUD grammar (companion HUD docked HUDPanel → detached/expansion).**

### Tier 1: docked HUD chip (always visible)

A single compact row in the existing docked HUDPanel, next to gateway/req-min:

- **Pressure glyph** (status vocabulary: ● healthy / ◐ elevated) +
  swap GB
- **Last sweep**: `3m ago · 0 condemned` (or `2 reaped · 3.1 GB`)
- **Protected count** (user apps never touched — the trust signal)

One glance tells you: the machine is being minded, and by whom.

### Tier 2: expanded Guardian panel (detached / full screen)

The full picture, for when something's wrong or curiosity strikes:

1. **Pressure hero** — swap gauge with the 24 GB escalation line marked;
   current `Pressure` state (normal/elevated) in status vocabulary style.
2. **Family breakdown** — the census as ProcessFamily bars:
   sourceControlDaemon / mcpChild / agentHost / userApplication / other
   (counts + RSS). This is the "who's squatting" view — the 16-daemon horde
   would have been visible here as a red bar.
3. **Sweep timeline** — recent SweepReports (from the SSE stream / JSONL):
   timestamp, decisions, outcomes, reclaimed GB. Live-updates via
   `GET /guardian/events`.
4. **Decision rows** — each KillDecision with its Verdict reason
   ("cap 2/user exceeded for admin (rank 4 by age)") and outcome
   (sigterm/sigkill/alreadyDead). Auditable, not scary.
5. **Dry-run affordance** — "Preview a sweep" button → POST /guardian/sweep
   (dry_run default) → shows what *would* be reaped. The trust-builder:
   you can always look before the Guardian leaps.
6. **Rules card** — R1–R4 in plain language, current gates (cap, ages),
   and the never-touch list. The conscience, visible.

### Design language (AndromedaUI conventions — the previous-UI flow)

This follows the exact path the orchestrator console took
(HTML design → SwiftUI export → package):

- **Palette/type/motion**: obsidian/observatory, Space Grotesk / Instrument
  Serif / JetBrains Mono, one entrance curve, status = glyph + word + hue
  (never color alone), light mode as a peer.
- **Specimens**: each element (pressure chip, family bar, decision row,
  sweep timeline card, rules card) is a **gallery specimen** — the
  `AndromedaGallery`/catalogue convention — with `#Preview`s in both
  schemes and **preview-parity snapshot twins** (Pointfree,
  `SNAPSHOT_TESTING_RECORD`, `[record-snapshots]` CI flow).
- **Deterministic fixtures**: sweep/census demo data pinned
  (`SampleData`-style fixtures) so baselines are byte-stable — Exhibit 7
  law.
- **Reduce-motion**: still complete frames under
  `\._accessibilityReduceMotion` (macOS 26 SPI).
- **PR with visuals**: mermaid + rendered gallery in the PR body.

**Placement in the existing apps**: docked chip → `HUDPanel` (both the
orchestrator console HUD and the AndromedaUI floating bar can host it);
expanded panel → a `Guardian` screen/section (in the orchestrator console's
screen model, or a detached `NSPanel` like the companion HUD's detach).
The design brief for the HTML pass: one 16:9 hero (pressure + families),
one docked chip crop, one decision-row detail crop — the three frames a
designer needs.

## 5. What the user should feel

Nothing. The Guardian's best day is a boring one: pressure green, zero
condemned, machine fast. Its product value is the *absence* of the 2 AM
"everything is Not Responding" screenshot. The HUD's job is to make that
absence visible — a small, calm, always-on reassurance with a receipt.

## 6. Honest boundaries (product)

- The Guardian never kills user applications. Hung CapCut is a human's
  call — the HUD *shows* it (family breakdown, pressure), it does not act.
- It does not consolidate MCP architecture (that's the MCP-SPRAWL
  workstream); it contains the symptom while that work proceeds.
- Dry-run is the default posture everywhere: every surface asks before it
  reaps, except the autonomous LaunchAgent (whose rules, telemetry, and
  never-touch list make it safe by construction).
