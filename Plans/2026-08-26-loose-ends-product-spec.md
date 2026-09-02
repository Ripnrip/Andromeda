# Loose Ends — Product Spec (Terminal Sweep → Recap → Filing)

**Status:** SPEC v1 (2026-08-26) · **Owner:** Gurinder · **Tracking:** HAB-362/HAB-377 · **Built:** herd-gather v1.1 + `--nightly` (live) · **Design refs:** `docs/ANDROMEDA-DESIGN-SYSTEM.md` · `andromeda-ui` skill · designsystem tokens in `AndromedaDomain`

## The one-liner

**Every night (or on demand), Andromeda notices everything you left open — every terminal, every unfinished agent session, every lingering project — gathers it into one place, recaps it in plain language, and files what matters. Nothing evaporates.**

## Product sense

Terminals are where work *actually* happens, and they're invisible to every todo system. A window titled "ScrollTracker · fix/social-hud-forwarding" is a thought; "why is multica down?" is an open loop; 22 Herd workspaces with agent_status=done are completed thoughts nobody closed. Loose Ends turns the desktop's terminal sprawl into a **triage queue with evidence** — the "catch all lingering thoughts" surface of the personal OS.

Three product moments:

1. **Sweep (automatic, zero-touch)** — 02:30 nightly: terminals → one fresh Herd workspace (never fuses existing), OpenLoopTracker loops digested, recap note to Andromeda `Ignore/Notes` + `~/.multibrain/logs/sweep-<date>.md`. Currently live via `herd-gather --nightly`.
2. **Recap (readable)** — one markdown page: external terminals by app, open loops with age, Herd workspace statuses (✅/💤/🟡), Multica filings with evidence. This is the *morning paper*.
3. **File (optional)** — unique lingering projects → Multica issues (deduped against open issues, evidence-cited). Today manual `--multica`; product end-state: one-tap from the recap.

**Non-goals:** reading terminal *contents* (titles/metadata only — privacy stance shared with OpenLoopTracker); auto-closing anything; fusing existing Herd workspaces.

## Where it lives in Andromeda

Loose Ends is a **capture-river + UI-surface pair** (per SURFACE-AREA §3 B/H):

| Surface | What | Status |
|---|---|---|
| **HUD ticker** (FleetObserveBar / multibrain-bar) | `🧵 N loose ends · oldest 3d` — one line, click → Home | 📐 spec |
| **AndromedaHome — Loose Ends (expanded)** | The recap, rendered: grouped cards (Terminals / Open Loops / Herd / Filings), each card = evidence chips + action row (Open in Herd · File to Multica · Done) | 📐 spec |
| **Recap artifact** | The nightly markdown note (durable, greppable, already landing in Ignore/Notes) | ✅ live |
| **Sweep engine** | `herd-gather` (Swift, zero-dep) + herdr API + OpenLoopTracker | ✅ live |

Phasing: **P0 (now)** artifact only → **P1** HUD ticker reading the sweep JSON (`herd-gather --json` output cached at `~/.multibrain/logs/sweep.json`) → **P2** Home expanded view with actions (filing via `multica issue create`, opening via `herdr workspace focus`).

## Access & setup

- **See:** latest recap = `ls -t ~/Developer/Andromeda/Ignore/Notes/*terminal-sweep.md | head -1` (or the HUD line, P1). Herd: workspace `◈ Gather <ts>`.
- **Run now:** `herd-gather` (add `--digest --multica --max 3 --andromeda-note` for the full pass). Agents: the `herd-gather` skill.
- **Setup (already done on studio.ian):** herdr 0.8+ running · `~/.local/bin/herd-gather` · OpenLoopTracker wrappers (claude/pi/hermes) · nightly launchd `com.multibrain.nightly` (02:30) · disable via multibrain config `terminal_sweep=off`.
- **Data flow:** CGWindowList + herdr snapshot + OpenLoopTracker export → recap md/json → (P2) Home API → filings.

## Design notes (for the design pass)

- Use `AndromedaColor` semantic tokens (`ink`, `muted`, `live`, `alert`, `glow`) already in Domain; status flags ✅/💤/🟡 map to `live`/`muted`/`alert`.
- Card anatomy: **title (project guess) · age · evidence chips (app icons/workspace id/agent status) · action row**. Evidence-first is the product's honesty law — never show a loose end without its proof.
- Empty state is a *feature*: "Nothing left open 🌙" with last-sweep timestamp.
- Motion: minimal — new-items-in sweep only; per Reduce Motion fallbacks (canon).

## Related

- Roadmap: `Plans/2026-08-26-herd-gather-roadmap.md` · Bridge: `Plans/2026-08-26-memory-bridge-plan.md` (sweep recaps become `.retain` events in P3 — the recap is a derivative, the event log is the truth)
- Audit: `Ignore/Notes/2026-08-26-crash-quarantine-audit.md` (nightly restore)
