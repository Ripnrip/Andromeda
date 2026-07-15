# Andromeda

## Workspace home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`. This repo is the Swift product/control-plane home (dual-home OK). Don't force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see `memory.*`, `infer.write`, `project.state.*` only — never Linear/Multica/n8n/provider brands. Andromeda owns selection behind the curtain.

## Project tracking

**Operator/meta-agent only.** Track via Linear ∪ Multica ∪ Slack `#projects`. Cross-link `BIN-*` ↔ `HAB-*`. See `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide — operator routing vs client capabilities). App clients use `project.state.*`.
