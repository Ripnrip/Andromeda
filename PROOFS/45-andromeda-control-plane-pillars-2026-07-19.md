# PROOF 45 — Andromeda six control-plane pillars locked (docs)

**Date:** 2026-07-19  
**Type:** Knowledge / product-identity lock (file-based; no paid LLM knowledge-sync)  
**Homes:** multibrain `main` @ `fde8b6b` + Andromeda `feat/andromeda-hud-core-promote` @ `d42953c` (PR #10)  
**Does not claim:** secrets broker, MCP consolidate, SkillRegistry, or full fleet mutate shipped. Flip still NO-GO.
**Trackers:** Linear [BIN-102](https://linear.app/binary-bros/issue/BIN-102) · Multica HAB-105 · comments on BIN-101 / BIN-55

## Locked six pillars

1. **Memory (Anima)** — `memory.recall`, `memory.store`, `infer.write`, `project.state.*` (🚧)
2. **MCP home** — host/consolidate MCPs; end Studio ~50 npm sprawl (🚧 observe / 📐 consolidate)
3. **Agent skills home** — `SkillRegistry` (📐)
4. **LLM proxy** — Andromeda-owned routing; clients don't pick providers (🚧 Autocache)
5. **Secrets vault / broker** — `slack_proxy`, `github_proxy`, `write.too`, …; never raw keys in client env (📐)
6. **Fleet runtime** — LaunchAgents/plists/launchd + observability/telemetry; observe vs typed Swift mutate (🚧 observe / 📐 BIN-101)

## Canonical doc

- `docs/ANDROMEDA-CONTROL-PLANE.md` (dual-home)

## Also updated

- Andromeda: README, ROADMAP, AGENTS, CHARTER, WORKSPACE-READINESS, SURFACE-AREA, MEMORY-ONEPAGER, CHANGELOG
- Multibrain: Roadmap, Features, TODO, AGENTS, README, MEMORY-ONEPAGER, WORKSPACE-READINESS, SURFACE-AREA, Changelog
- SecondBrain: `01-Permanent/Systems/Andromeda Control Plane.md` (file sync)
- Linear + Multica: control-plane pillars issue / comments

## Explicit non-claims

Workspace flip remains gated (PROOF 44). Pillars are product scope documentation only.
