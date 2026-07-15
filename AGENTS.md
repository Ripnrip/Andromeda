## Workspace / repo home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`; this repo is the Swift product/control-plane home (dual-home OK). Do not force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see stable IDs only (`memory.*`, `infer.write`, `project.state.*`) — never Linear/Multica, providers, or n8n. Andromeda owns provider selection behind the curtain.

## Project tracking

**Operator/meta-agent only** (not client tool menus): Linear (`BIN-*`) ∪ Multica Habitat (`HAB-*`) ∪ Slack `#projects` (`C0BHYQQDETA`). Cross-link, don't triple-duplicate. Canonical map + **routing permutation guide**: `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide). App clients use `project.state.*` CRUD instead.

Examples: Andromeda overall → Multica+Linear; Slack issue → Linear first then Multica; macOS OS update → Linear only.
