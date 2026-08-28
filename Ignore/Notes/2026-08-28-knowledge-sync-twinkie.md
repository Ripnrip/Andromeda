# 2026-08-28 — Knowledge sync (twinkie): Orchestrion status + canon law

Pure docs sync per routing table ("twinkie" row) — no trackers touched.

## Status snapshot (Fri 07:00 EDT)

- **Design round: NOT started.** Prompt is ready + in clipboard
  (`Plans/2026-08-26-orchestrion-design-agent-prompt.md`); no mockups in
  `docs/design/orchestrion/`, no `DataSection()`/`OrchestrionChip` in AndromedaUI.
- **Phase 1 (read-slice parity): pending green-light.** Go stack untouched, still on :3637.
- **Pool at rest confirmed**: Go server restarted 05:38 today, pool sits at **5 conns**
  (the `defaultMinConns` warm baseline) vs the incident-night's pinned 25 — exactly the
  model's predicted resting behavior. The 25-wall only appears under daemon burst load.

## New knowledge (durable lessons)

1. **Canon law (from casualty):** Exhibit 8 "Go-shaped actor" (HAB-374's review scar)
   was appended to the `~/.agents` *sync copy* on 2026-08-26 and **clobbered by the PR #63
   canon sync** on 2026-08-27. Restored as **Exhibit 11** in the git-tracked source
   (`.claude/skills/swift-canon/references/anti-patterns.md`) with the law written into
   its provenance: *canon edits land in the canonical repo file, never the synced copy.*
2. **Name collision alert:** Andromeda **Orchestrator** (PR #63 observability journal
   component, HAB-388) ≠ Multica **Orchestrion** (data-observability service, HAB-374).
   Visually near-identical, totally different components. Docs should always use the
   full product name + HAB ref on first mention.

## Fleet context this morning

Reminders wave shipped (HAB-379–388): RemindersBar, Siri AppIntents, RemindersWiki,
AnimaSync. Loose Ends spec landed (HAB-362/377). See Multica for details — not
duplicated here per no-triple-duplication rule.
