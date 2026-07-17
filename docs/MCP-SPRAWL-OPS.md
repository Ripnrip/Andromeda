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

---

## 5. Tracker comments

After a measure+trim pass, comment **BIN-41** and **HAB-64** with before/after integers only (no env dumps).
