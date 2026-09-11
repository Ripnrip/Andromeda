# The Log is the Contract

> The document is for the agent. The log is the truth. Everything else is a projection.

**Status:** 📐 principle — fleet-wide, effective on merge.
**Provenance:** the vault-widget thread (2026-09-09/11) + activegraph's
["The Log is the Agent"](https://arxiv.org/abs/2605.21997) naming what we
already practice. We built the practice first; this doc states it.

## The principle

Every durable thing in this fleet is an **append-only log** plus
**deterministic projections**. If an artifact can't be replayed, diffed,
or audited, it isn't durable — it's a cache pretending to be memory.

- **The log is the agent's memory.** Not the summary, not the README —
  the ordered record of what happened. Summaries are projections; they
  can be regenerated, and they can lie. The log can't.
- **Documents written for agents are log-shaped**: append-only history,
  dated entries, receipts — not mutable prose that silently overwrites
  the past. (Changelog-as-journal-of-record is the law because of this,
  not for aesthetics.)
- **Projections are rebuildable.** Working state, dashboards, galleries,
  indexes, this doc — all derived views. Losing a projection is an
  inconvenience; losing the log is amnesia.
- **The trace is the proof.** A claim without a log line behind it is a
  hypothesis. ("No vibes, please." — BofA)

## Where the fleet already runs on this

| Log (source of truth) | Projection (rebuildable) |
|---|---|
| Git history (every repo, incl. memory MemFS) | README, docs, galleries |
| Changelog.md (journal of record — twinkie law) | release notes, summaries |
| PR threads + review bodies | review decisions, approvals |
| Telemetry journals (typed emoji events) | HUD walls, dashboards |
| claude-mem observations / Ladybug index | graph views, recall surfaces |
| Event-sourced Andromeda runtime state | Qdrant projections, HUD |
| CI run logs + committed baselines (byte-diff proven) | PR green checkmarks |
| Slack threads themselves | anything we quote from them |

## Consequences (write these into behavior)

1. **Append, don't overwrite.** New facts = new entries with dates, not
   edits that erase the old world. Corrections append; they never retcon.
2. **Every claim carries its receipt.** PR bodies, review replies, status
   reports: cite the log line (commit, run id, test output) or don't claim it.
3. **Docs for agents get a log section** — a "what happened when" tail,
   not just current-state prose.
4. **Replay beats restore.** Prefer systems whose state can be rebuilt by
   replaying the log (git, event sourcing) over opaque snapshots.
5. **Fork-and-diff over rerun-and-hope.** When testing a change to a
   process, branch the log and diff — don't rerun blind and compare vibes.

## Related

- swift-review-gate Q14 (exhaustive proof / receipts) — the gate this
  principle enforces at review time.
- Canon logging law (emoji telemetry at decision points) — the log's
  write path.
- activegraph (yoheinakajima) — same thesis, independent runtime; their
  vocabulary (projection, fork-and-diff, per-error pages) is worth
  borrowing, their Python runtime is not ours to adopt (Swift-first law).
