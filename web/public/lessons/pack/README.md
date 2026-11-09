# Andromeda lessons pack

Projection of fleet craft for agents and humans. **Git is the source of truth.** If these files disagree with the repo, the repo wins.

## Install

```
# Review gate skill
mkdir -p ~/.agents/skills/swift-review-gate
cp swift-review-gate.md ~/.agents/skills/swift-review-gate/SKILL.md

# Swift canon (full references still live in the Andromeda repo)
mkdir -p ~/.agents/skills/swift-canon/references
cp swift-canon.md ~/.agents/skills/swift-canon/SKILL.md
cp anti-patterns.md ~/.agents/skills/swift-canon/references/anti-patterns.md

# PR template
cp PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md
```

Canon references (concurrency, logging, snapshots, …) are not all in this pack — clone:

https://github.com/Ripnrip/Andromeda/tree/main/.claude/skills/swift-canon

## Honesty (HAB-1437 refresh)

| Artifact | Status |
|----------|--------|
| Swift canon + anti-patterns | In Andromeda main — pack resynced from skills |
| Review gate skill | In Andromeda main (PR #76+) |
| claude-mem-for-all | Shipped — https://github.com/Ripnrip/claude-mem-for-all |
| PR template (sequence/flow + visual law) | In Andromeda main |
| App Control (HUD) | Partial → loopback plane + triple lock on main (HAB-838 / docs/APP-CONTROL-HUD.md). Not a universal App Control for every surface. |
| Swift & Apple UI design resource | Docs on main (`docs/SWIFT-UI-DESIGN-RESOURCE.md`) |
| DESIGN.md tokens | Shipped design-token parity wave (BIN-271) |

Site: `/lessons` on the Andromeda website (Vercel project `andromeda`).
