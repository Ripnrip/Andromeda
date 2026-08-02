## Workspace / repo home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`; this repo is the Swift product/control-plane home (dual-home OK). Do not force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see stable IDs only (`memory.*`, `infer.write`, `project.state.*`) — never Linear/Multica, providers, or n8n. Andromeda owns provider selection behind the curtain.

## Project tracking

**Operator/meta-agent only** (not client tool menus): Linear (`BIN-*`) ∪ Multica Habitat (`HAB-*`) ∪ Slack `#projects` (`C0BHYQQDETA`). Cross-link, don't triple-duplicate. Canonical map + **routing permutation guide**: `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide). App clients use `project.state.*` CRUD instead.

Examples: Andromeda overall → Multica+Linear; Slack issue → Linear first then Multica; macOS OS update → Linear only.

## Session Start

- State the active model version at the start of each session.
- Check available MCP resources/tools before assuming external context exists.
- Inspect `git status --short` and recent commits before editing.
- Read `ANDROMEDA-CHARTER.md` (gateway / product charter) and only the docs needed for the task.

## Repository Rules

- **Swift-first / No Bash surface (enforced):** Do not add project-maintained Bash automation files (`.sh`, `.bash`, or bash-shebang scripts). Shell is allowed only via paths listed in `config/shell-allowlist.txt` (empty by default). Prefer Swift modules, typed CLIs, or GitHub Actions YAML. Never add a new `.sh` to enforce or work around this rule. See `docs/NO-BASH-SURFACE.md`. Local gate: `python3 Tools/no_bash_surface_gate.py` or `swift test --filter NoBashSurfacePolicy`.
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
