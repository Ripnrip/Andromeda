# PROOF 44 — Adversarial milestone + Swift-integrity audit (2026-07-19)

**Date:** 2026-07-19  
**Verdict:** **NO-GO** for Cursor workspace flip to Andromeda  
**Lane:** Feature readiness / proof validity (15-agent) + Swift integrity / install-and-sign (10-agent)  
**SoT:** multibrain `PROOFS/` (this file) · mirror Andromeda `PROOFS/44-adversarial-milestone-audit-2026-07-19.md` on `feat/andromeda-hud-core-promote` (PR #10)  
**Honesty rule:** overclaimed Done is worse than Todo. Do not invent green. Preserve tables below for re-audit diffs.

## Links

| Tracker | ID | Role |
|---------|-----|------|
| Linear | [BIN-55](https://linear.app/binary-bros/issue/BIN-55) | HUD epic — demoted In Review → In Progress |
| Linear | [BIN-39](https://linear.app/binary-bros/issue/BIN-39) | Workspace readiness / project.state lineage comment |
| Linear | [BIN-71](https://linear.app/binary-bros/issue/BIN-71) | Bars epic — demoted In Review → In Progress |
| Linear | [BIN-83](https://linear.app/binary-bros/issue/BIN-83) | Snapshots — demoted Done → In Review |
| Linear | [BIN-69](https://linear.app/binary-bros/issue/BIN-69) | Dogfood — soft demote Done → In Review |
| Linear | [BIN-79](https://linear.app/binary-bros/issue/BIN-79) | CloudKit — keep Todo (does not block flip) |
| Linear | [BIN-101](https://linear.app/binary-bros/issue/BIN-101) | **NEW** Swift-native `andromeda-install` (delete `.sh`) |
| Multica | HAB-76 | BIN-55 mirror — demoted in_progress |
| Multica | HAB-56 | BIN-39 mirror |
| Multica | HAB-83 | BIN-83 mirror — demoted in_review |
| Multica | HAB-84 | BIN-69 mirror — soft demoted in_review |
| Multica | HAB-104 | BIN-101 mirror (ALL SWIFT install) |
| PR | [Andromeda #10](https://github.com/Ripnrip/Andromeda/pull/10) | HUD SoT — do **not** merge until CI green |
| Codex P1 | [discussion_r3609132727](https://github.com/Ripnrip/Andromeda/pull/10#discussion_r3609132727) | install-and-sign.sh must become Swift/CLI or remove |

---

## Locked decision — ALL SWIFT installer (hybrid REJECTED)

The human rejected hybrid. **All Swift** for Andromeda install / sign / LaunchAgent deploy:

- Rewrite `scripts/install-and-sign.sh` as a typed Swift CLI (`andromeda-install` / `swift run andromeda-install`)
- Delete the Bash file after the Swift path works (thin shim only if needed for ≤1 release, then remove)
- Document in AGENTS.md / charter that install is Swift — **no Bash exception**

Implement: SPM product `andromeda-install`; template LaunchAgent `$HOME`; require `hud|home|both`; absolute `codesign`/`launchctl` paths; fail-closed kickstart; then delete `.sh`.

**This proof session is tracker + docs only — do not implement the Swift installer here.**

---

## A) Feature readiness / proof validity (15-agent milestone) — overall NO-GO

| # | Lane | Verdict |
|---|------|---------|
| 1 | Dual-home MemoryKit | PARTIAL — tip↔PR10 identical; main ~42 files behind |
| 2 | HUD e2e honesty | PARTIAL — hot hermetic only; not live vault/boot |
| 3 | Live-vault / stale binary | FAIL — local proof real; CI does not gate |
| 4 | CI e2e gates | FAIL — theater; soft-skips; not on main |
| 5 | Capability curtain | FAIL — Multica/habitat in fleet-pulse chrome |
| 6 | Secrets / spend | FAIL — stale Letta OpenRouter; Home Cursor-tainted |
| 7 | PR #10 merge | FAIL — GHA red (snapshots + flakes) |
| 8 | Snapshot hermeticity | PARTIAL — idle live-start; no RECORD=never |
| 9 | Planning docs | FAIL — premature greens / empty Task-7 proof |
| 10 | CloudKit BIN-79 | PARTIAL — honesty OK; does NOT block flip |
| 11 | PROOFS 39–43 | PARTIAL — cite 43/41-hang/40-bars only |
| 12 | Linear statuses | FAIL — Done overclaims vs unmerged SoT |
| 13 | Package.swift | PARTIAL — nested tests easy to miss |
| 14 | LaunchAgent deploy | PARTIAL — live OK; anti-stale deploy soft |
| 15 | Flip checklist | FAIL — missing gates #13–#20 |

### Hard blockers before flip

- Green PR #10 CI → merge
- Scrub Multica from client fleet-pulse
- Restart Letta + clean Home
- Harden live-vault gate
- Demote BIN-55 / BIN-71 / BIN-83
- Add checklist gates #13–#20

---

## B) Swift integrity / install-and-sign (10-agent) — ALL SWIFT (not hybrid)

| # | Focus | Verdict |
|---|------|---------|
| 1 | Policy (Charter/AGENTS) | FAIL — bash banned; install-and-sign.sh violates |
| 2 | Script contents | PARTIAL — footguns; Swiftable |
| 3 | Codex P1 on PR#10 | FAIL unresolved — Swift/CLI or remove |
| 4 | Scripts inventory | only .sh; Swift-only e2e fiction for ship |
| 5 | Rewrite feasibility | feasible ~250–400 LOC SPM executable |
| 6 | Bar precedents | bash was fleet pattern — Andromeda must break pattern toward Swift |
| 7 | Security of .sh | FAIL until hardened / replaced |
| 8 | Policy intent | was hybrid — **OVERRIDDEN by human: ALL SWIFT** |
| 9 | Rename break risk | need SPM product + doc sweep |
| 10 | swift-skill | skill allows bash; Charter does not — Charter wins |

**Decision:** implement `andromeda-install` (or similar) Swift CLI; template LaunchAgent `$HOME`; require hud|home|both; absolute codesign/launchctl paths; fail-closed kickstart; then delete `.sh`.

---

## Re-audit instructions

After fixes, re-run the **same 15+10 lanes** and mark each row **PASS/FAIL** against this table (diff row-by-row; do not invent new lane numbers without appending). Flip remains **NO-GO** until every hard blocker is cleared **and** the human says the word.

## Related readiness note

`docs/ANDROMEDA-WORKSPACE-READINESS.md` updated 2026-07-19: flip still NO-GO; install must be Swift (no bash exception).
