## Workspace / repo home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`; this repo is the Swift product/control-plane home (dual-home OK). Do not force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see stable IDs only (`memory.*`, `infer.write`, `project.state.*`, and later secrets/proxy IDs like `slack_proxy` / `github_proxy` / `write.too`) — never Linear/Multica, providers, n8n, or raw API keys in process env. Andromeda owns provider selection and secret injection behind the curtain.

## Six control-plane pillars (do not lose sight)

Andromeda is **Memory + MCP host + Skills + LLM proxy + Secrets broker + Fleet runtime** — not HUD/memory alone. Read `docs/ANDROMEDA-CONTROL-PLANE.md`. Mark 🚧/📐 honestly; do not claim secrets broker or MCP consolidate shipped. Fleet: observe via `LaunchEntity` / `FleetObserveReport`; mutate via typed Swift install (BIN-101), not bash.

Behind the curtain, fleet clocks, host/store ownership, privacy egress, graph/index
brands, Letta/Python services, trackers, and secrets are operator internals.
`infer.write` is currently an episodic-store alias, not LLM inference; SwiftData is
the only implemented hot store; missing visibility is private and cloak/credential
content is internal. Context7 has no repo implementation and may only be an optional
future MCP/skill adapter, never a core dependency.

## Project tracking

**Operator/meta-agent only** (not client tool menus): Linear (`BIN-*`) ∪ Multica Habitat (`HAB-*`) ∪ Slack `#projects` (`C0BHYQQDETA`). Cross-link, don't triple-duplicate. Canonical map + **routing permutation guide**: `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide). App clients use `project.state.*` CRUD instead.

Examples: Andromeda overall → Multica+Linear; Slack issue → Linear first then Multica; macOS OS update → Linear only.

## Session Start

- State the active model version at the start of each session.
- Check available MCP resources/tools before assuming external context exists.
- Inspect `git status --short` and recent commits before editing.
- Read `ANDROMEDA-CHARTER.md` (gateway / product charter) and only the docs needed for the task.

## Repository Rules

- Do not add project-maintained Bash automation files.
- Do not add invisible `launchctl` jobs, hidden watchdogs, or unsurfaced background daemons.
- Any background behavior must have visible status, telemetry, ownership, and controls.
- Do not overwrite unrelated work or reset the repository to hide conflicts.
- Never add personal signatures to commits or documentation.

## Build and Test Commands

Root Hummingbird / Autocache gateway:

```console
swift build
swift test
swift build -c release
```

Dual-home MemoryKit package:

```console
cd Packages/MemoryKit && swift test
```

## Engineering Rules

- Prefer Swift strict-concurrency correctness, typed identifiers, rich enums, protocol boundaries, actors for shared mutable state, initializer injection, and OSLog diagnostics.
- Add function-level comments for generated code and detailed comments for tests.
- Keep retries bounded, cancellation respected, operations idempotent where replay is possible, and failures observable.
- Never silently change schemas or configuration formats; add ADRs and migrations.
- Never generate destructive code such as dropping databases or wiping remote data without triple explicit confirmation and backups in a `legacy/` area.
