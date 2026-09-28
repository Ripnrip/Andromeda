# MCP Sprawl — Ops Runbook

> Operator-only. No secrets. Clients never see this — they use stable capability IDs.

**Evidence pass:** [MCP-SPRAWL-BEFORE-AFTER.md](./MCP-SPRAWL-BEFORE-AFTER.md) (BIN-41 / HAB-64)  
**Problem inventory:** [MCP-SPRAWL-PROBLEM.md](./MCP-SPRAWL-PROBLEM.md)

---

## 1. Measure (Studio)

```bash
# Total npm-exec MCP parents
pgrep -lf 'npm exec' | wc -l

# Package breakdown
pgrep -lf 'npm exec' | sed -E 's/.*npm exec( -y)? //; s/ .*//' | sort | uniq -c | sort -rn

# Broker map (who owns the sprawl)
ps -o pid=,ppid=,tty=,etime=,pcpu=,command= -p "$(pgrep -f 'npm exec' | paste -sd, -)"
```

Record timestamp + totals into `docs/MCP-SPRAWL-BEFORE-AFTER.md` (or `PROOFS/`).

---

## 2. Safe config fixes (same file only)

| Check | Action |
|-------|--------|
| Missing `npx` `-y` | Add `-y` as first arg (avoids interactive prompts / stall zombies) |
| Duplicate server keys / twin entries | Remove the redundant one (e.g. Codex `cerebras-fixed` ≡ `cerebras-mcp`) |
| Firecrawl HTTP vs npm | Prefer **one** transport per host. Cursor: `npx` + `FIRECRAWL_API_KEY`. Codex: HTTP URL already. Do **not** copy URL-embedded keys into other hosts |
| Cross-file overlap (Claude `.mcp.json` vs `~/.claude.json`) | Drop the duplicate from `.mcp.json` if top-level already defines it |

Configs touched historically: `~/.cursor/mcp.json`, `~/.claude.json`, `~/.claude/.mcp.json`, `~/.codex/config.toml`, Claude Desktop.

---

## 3. Live process discipline

**Never**

- Blind `pkill -f claude` / wipe all TTYs
- Kill Cursor Helper MCP while an agent session is active
- Paste secrets into Linear / Multica / git

**May**

- Kill `npm exec` whose **broker ppid is dead** (true orphans)
- Trim MCP children of Claude CLI brokers that are idle with evidence: `pcpu == 0` and etime ≥ 24h (leave the Claude PID; document PIDs)

**Prefer**

- Config so **new** sessions spawn fewer
- User restarts of stale cmux/Claude panes for the remaining drop

---

## 4. Expected residual

Each live agent host that loads filesystem + memory + sequential-thinking costs **×3** `npm exec` parents. N Claude TTYs ⇒ ~3N of the trio alone. Andromeda `MCPServerRegistry` (`infra.mcp.scan`) is observe-only today — shared lifecycle / dedupe is the product fix.

For dead-broker zombies (claude-mem chroma/qdrant orphans), use the reaper:

```bash
andromeda mcp-hub reap            # dry-run: classify and report only
andromeda mcp-hub reap --apply    # SIGTERM → SIGKILL escalation on orphans only
```

Classification and evidence: [MCP-ORPHAN-EPIDEMIC-2026-09-27.md](./MCP-ORPHAN-EPIDEMIC-2026-09-27.md). Owned (live-broker) processes are never touched; `unknown` verdicts are never signaled.

---

## 5. Two classifiers, one boundary: MemoryKit reaper vs AndromedaGuardian

The process of "what counts as an orphan MCP server" is classified in **two
places**, and they are **intentionally different tools for different jobs** —
not a duplicate to be deduped this cycle:

- **MemoryKit `MCPOrphanReaper` (this PR)** is *MCP sprawl ops tooling*:
  one-shot or bounded `mcp-hub reap`/`watch` runs an operator invokes,
  command-shape based (what does the process look like, and is its broker
  chain dead?), with a dry-run default and a `--spare` allowlist. Its whole
  reason to exist is the dead-broker zombie epidemic
  ([wave 1](./MCP-ORPHAN-EPIDEMIC-2026-09-27.md), [wave 2](./MCP-ORPHAN-WAVE-2-2026-09-28.md)).
- **AndromedaGuardian** is *fleet policy*: a policy-rule engine
  (`PolicyRule`s over a process census) that classifies the whole
  `ProcessFamily` (SCM daemons, agent hosts, `mcpChild(marker:)` …) against
  an injectable `ClassificationCatalog`. Its `orphanedMCPChildRule` is one
  rule among several, gated on `mcpMaxAgeSeconds` and on the child not
  `reachesAgentHost`.

The boundary: **an operator tool for evidence-gathering + safe manual
reaping (MemoryKit) vs a standing automated policy for the whole fleet
(Guardian).** A process can be *classified orphaned by one and left alone by
the other* and that is acceptable while they serve different roles: the
reaper never fires unattended (dry-run default, bounded watch, explicit
`--apply`), Guardian is the one that fires automatically — so the dangerous
direction (auto-kill of a process the operator would have spared) is already
fenced off by the reaper's manual gating.

The **`node_modules/.bin` broker needle** specifically stays in the reaper
while HAB-731's root cause is open: wave 2 showed the 8×3.5GB node M wave was
spawner-side, and *any* `node_modules` script that owns an MCP child is a
live session broker in every case observed. Removing the needle now would
re-classify owned children as orphans during exactly the window we are still
capturing spawner evidence for. **Reconciliation target:** when the shared
broker catalog lands (ADR-0019 hub, per wave-2 "Open questions"), both
classifiers read the same ownership source and the reaper becomes a
presentational front end for one verdict — *that* is the dedupe, not deleting
either classifier now.

---

## 6. Tracker comments

After a measure+trim pass, comment **BIN-41** and **HAB-64** with before/after integers only (no env dumps).
