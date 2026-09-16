# Andromeda lessons pack

Projection of fleet craft for agents and humans. **Git is the source of truth.** If these files disagree with the repo, the repo wins.

## Install

```
# Review gate skill
mkdir -p ~/.agents/skills/swift-review-gate
cp swift-review-gate.md ~/.agents/skills/swift-review-gate/SKILL.md

# Swift canon (full references still live in the Andromeda repo)
mkdir -p ~/.agents/skills/swift-canon
cp swift-canon.md ~/.agents/skills/swift-canon/SKILL.md
cp anti-patterns.md ~/.agents/skills/swift-canon/references/anti-patterns.md

# PR template
cp PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md
```

Canon references (concurrency, logging, snapshots, …) are not all in this pack — clone:

https://github.com/Ripnrip/Andromeda/tree/main/.claude/skills/swift-canon

## Honesty

| Artifact | Status |
|----------|--------|
| Swift canon + anti-patterns | In Andromeda main |
| Review gate skill | PR #76 |
| PR template merge-blocker boxes | Intended latest (this pack); sequence-diagram law already on main |
| App Control | Specified — not implemented |

Site: `/lessons` on the Andromeda website.
