# Herd-Gather Roadmap — Terminal Sweep, Recap & Filing

**Status:** v1 SHIPPED (2026-08-26) · **Owner:** Gurinder · **Tracking:** HAB-362 (Multica) · **Code:** `~/Developer/Closure/herd-gather/` (repo pending — see v1.1)

## The itch

Terminals metastasize: iTerm2 windows, Terminal.app panes, cmux grids — each holding a lingering thought ("ScrollTracker", "why is multica down?", "Loose Ends"). The desktop *is* the todo list, and nothing reads it. Herd already organizes agent workspaces; the rest of the terminal fleet stays invisible to every recap system.

## The move

One command sweeps every on-screen terminal window into a **fresh Herd workspace** — never fusing or mutating existing ones — and files the evidence wherever the day's thinking is tracked (recap md, Andromeda notes, Multica issues). Combined with OpenLoopTracker (open loops) it becomes the *catch-all recap*: lingering thoughts surface as tickets, not entropy.

## Design laws

1. **Never fuse.** Existing Herd workspaces are read for context, never written. Gather creates exactly one new workspace; rollback is one `herdr workspace close`.
2. **Originals untouched by default.** v1 never closes source windows; `--close-originals` is explicit opt-in with per-window result reporting.
3. **Evidence or it didn't linger.** Every filed issue cites its evidence (which window, which workspace, which agent status). Same law as the memory bridge: recaps are derivatives over observable events.
4. **Dedup before filing.** `--multica` searches existing issues first; a project already tracked is *skipped with a pointer*, never double-filed.

## Shipped (v1, 2026-08-26)

- CGWindowList sweep of terminal apps (iTerm2, Terminal, cmux, Ghostty, Warp, kitty, WezTerm, …), Herd itself excluded
- `herdr api snapshot` → recap of all existing workspaces w/ agent status (✅/💤/🟡)
- Fresh workspace + one labeled tab per window; labels cleaned from titles (dir · branch); rotating color-dot ink (herdr 0.8.0 lacks a color API — emoji ink until it exists)
- `--dry-run` `--json` `--label` `--output`
- Verified live: workspace `◈ Gather 2026-08-26 00.53` (wZ), 8 tabs

## v1.1 (in flight)

- `--digest` — include OpenLoopTracker open loops (collector revived same day: rpath bug fixed, installer patched)
- `--multica [--max N]` — one issue per unique lingering project, deduped, evidence-cited
- `--andromeda-note` — recap lands in `Andromeda/Ignore/Notes/`
- `--close-originals` — opt-in best-effort close of swept windows

## v2 candidates

- [x] **Repo + agent skills** — done 2026-08-26: `~/Developer/Closure/herd-gather` (Swift package, README, `skills/herd-gather/SKILL.md` installed to claude/pi/agents harness dirs). herdr plugin deferred until herdr opens a plugin surface (0.8.0 `integration install` covers agent binaries only)
- **Nightly digest** — `run-nightly.sh` step: sweep + open loops + (post-Phase-1) Andromeda pull → one daily recap note
- **Color properly** — swap emoji ink for herdr's display metadata the day it exposes color tokens
- **Sweep→bridge integration** — daily sweep recaps become `.retain` events (per the memory-bridge plan) so the terminal fleet feeds Anima's event log with agent attribution (`agent: herd-gather`)

## Non-goals

Reading terminal *contents* (titles/metadata only — same privacy stance as OpenLoopTracker). Auto-closing Herd's own workspaces. Filing without evidence.

## Decision log

- **2026-08-26** Emoji ink over waiting for a color API; labels carry dir·branch for grep-ability.
- **2026-08-26** Multica filing dedupes by open-issue search, not local cache — the server is the truth.
- **2026-08-26** Recaps cite evidence windows; keeps the "agent is the log / recaps are derivatives" law aligned with the memory bridge plan.
