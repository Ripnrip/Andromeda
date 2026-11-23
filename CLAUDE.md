# Andromeda

## Workspace home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`. This repo is the Swift product/control-plane home (dual-home OK). Don't force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see `memory.*`, `infer.write`, `project.state.*` only — never Linear/Multica/n8n/provider brands. Andromeda owns selection behind the curtain.

## Project tracking

**Operator/meta-agent only.** Track via Linear ∪ Multica ∪ Slack `#projects`. Cross-link `BIN-*` ↔ `HAB-*`. See `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide — operator routing vs client capabilities). App clients use `project.state.*`.

## Design system

`DESIGN.md` is the source of truth for anything visual — web (`web/`), SwiftUI, and the CLI/TUI. Read it before generating or changing UI. Use tokens only: Tailwind semantic utilities on the web, `AndromedaTheme` / `AndromedaPalette` in Swift (`DesignToken` inside `Packages/AndromedaUI` and `Packages/AndromedaOrchestrator`), `AndromedaChrome` in the terminal. A token change touches `DESIGN.md`, `web/app/globals.css`, `AndromedaPalette.swift`, and the `DesignToken.swift` copies in `Packages/AndromedaUI` and `Packages/AndromedaOrchestrator` together; the three `DesignTokenParityTests` suites enforce it, and `raw-color-literal` fails CI on any colour literal.

## Claude agent habits

1. Read `ANDROMEDA-CHARTER.md` for gateway/product charter when touching Hummingbird / Autocache.
2. Prefer Swift-native patterns and strict concurrency.
3. Update docs in the same change when behavior, schema, or ops expectations change.
4. Run targeted tests before broad tests.
5. Avoid Bash automation files or hidden launch/watchdog behavior.
6. Surface background operations through visible status plus telemetry.

## Public boundary (2026-11-22)

This repo is **public product surface only** — no fleet/ops specifics (real hostnames, home paths, workspace/channel IDs, internal ports, network-topology prose). The public surface is kept deliberately free of operational specifics — enforced at push time. Rules: `docs/PUBLIC-REPO-RULES.md`; pre-push checklist: the private workspace docs (`docs/PUBLIC-REPO-HYGIENE.md` in multibrain). Pushes are disabled by default — run the checklist before re-enabling any push.
