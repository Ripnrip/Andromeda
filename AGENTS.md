# Agent Operating Guide

## Session Start

- State the active model version at the start of each session.
- Check available MCP resources/tools before assuming external context exists.
- Inspect `git status --short` and recent commits before editing.
- Read `ANDROMEDA-CHARTER.md`, then only the docs and files needed for the task.

## Repository Rules

- Do not add project-maintained Bash automation files.
- Do not add invisible `launchctl` jobs, hidden watchdogs, or unsurfaced background daemons.
- Any background behavior must have visible status, telemetry, ownership, and controls.
- Do not overwrite unrelated work or reset the repository to hide conflicts.
- Never add personal signatures to commits or documentation.

## Build and Test Commands

Use these once implementation exists:

```console
swift build
swift test
swift build -c release
```

## Documentation Duties

- Update `CHANGELOG.md` for user-visible, operational, schema, configuration, or API behavior changes.
- Add new changelog entries at the top.
- Use the correct current date for journal/changelog entries.
- Include a rotating fun tone hat, a witty commit-message-of-the-day proposal, a reflection note, and one whimsical Easter egg line.
- Keep `README.md`, `ROADMAP.md`, and `ANDROMEDA-CHARTER.md` synchronized.

## Engineering Rules

- Prefer Swift strict-concurrency correctness, typed identifiers, rich enums, protocol boundaries, actors for shared mutable state, initializer injection, and OSLog diagnostics.
- Add function-level comments for generated code and detailed comments for tests.
- Keep retries bounded, cancellation respected, operations idempotent where replay is possible, and failures observable.
- Never silently change schemas or configuration formats; add ADRs and migrations.
- Never generate destructive code such as dropping databases or wiping remote data without triple explicit confirmation and backups in a `legacy/` area.

## Definition of Done

- Code compiles without avoidable warnings.
- Tests or checks are run and reported accurately.
- Telemetry, privacy, security, rollback, and docs are considered.
- Changelog and roadmap are updated when behavior or maturity changes.
