# Changelog

All notable changes to Andromeda will be documented here.

## 2026-08-09 — AndromedaUI Gate 0 (BIN-270)

**Tone hat:** Design-system mechanic
**Commit message of the day:** `feat: vendor AndromedaUI and clear Gate 0 compile blockers`

### Added
- `Packages/AndromedaUI` — vendored SwiftUI design-system package (control plane, floating bar, motion, tokens).
- Nested-package CI job for `Packages/AndromedaUI`.
- Gate 0 smoke tests + snapshot baseline skip helper until macOS record pass.

### Fixed
- Duplicate `Pillar` types (`BarPillar` for the floating bar vs nav `Pillar`).
- Duplicate `andromedaAmber` / `andromedaDim` / `andromedaInk` Color extensions.
- Preview / test `ColorScheme` inference under Swift 6.
- Non-deterministic `UUID()` identities on static memory/control-plane catalogs.

### Follow-ups
- BIN-271 tokens → AndromedaBrand convergence; BIN-272 bar/sections; BIN-273 TUI parity; snapshot record.

## 2026-08-08 — Universal agent memory over MCP

**Tone hat:** Hacker 🕶️
**Commit message of the day:** `feat: open shared memory MCP capabilities to every agent`
**Steps taken (UTC):** Inspected the control-plane contract; composed `memory.store` and `memory.recall` into the bearer-authenticated MCP door; added agent-neutral provenance and round-trip tests; fixed Codex P1s for shared recallable scope, agent-namespaced idempotency, and safe recall limit parsing.

### Added
- Provider-neutral MCP tool serving and composition boundaries.
- `memory.store` and `memory.recall` for Letta, Hermes, Multica squads, and other bearer-authenticated MCP clients.
- SQLite-backed universal-agent write/read tests with explicit provenance and idempotency.

### Fixed
- MCP shared memory now uses a stable shared project scope so default `project` privacy remains recallable.
- Caller idempotency keys are namespaced by agent identity; conflicting replays are rejected instead of silently discarded.
- `memory.recall` validates `limit` before `Int` conversion so oversized finite JSON numbers return a tool error instead of trapping.

### Security
- Removed no authentication boundary: all agents use the same universal bearer interface, while upstream secrets and storage brands remain behind Andromeda's capability curtain.

### Reflection
- I felt proud we opened the library doors without tossing the keys under the cosmic doormat. 🔐

### Easter egg
- Memory moth count: 2 tools glowing, 0 Claude-shaped locks fluttering nearby. 🦋

## 2026-08-08 — AndromedaBrand terminal design system (BIN-229 / BIN-231)

**Tone hat:** Brand mechanic
**Commit message of the day:** `feat: salvage AndromedaBrand terminal chrome off main`
**Steps taken:** Lifted unique #35 terminal-brand delta onto current main (post design-system spine #34), and addressed Codex TerminalStyle review (FORCE_COLOR without TERM; Unicode gated by UTF-8 locale).

### Added
- `AndromedaBrand` target — `AndromedaPalette` (sRGB parity with `web/app/globals.css`), `TerminalStyle` (truecolor → 256 → plain, `NO_COLOR` / `FORCE_COLOR` honoured), `AndromedaASCII`, `AndromedaChrome`, SwiftUI `AndromedaTheme`.
- `andromeda brand` — prints the terminal design system: mark, palette, status vocabulary, degradation caveat.
- Branded start-up banners and status/doctor/setup chrome on `andromeda` and `andromeda-runtime`.
- `docs/ANDROMEDA-DESIGN-SYSTEM.md` and a Terminal (TUI) block on `/design`.
- `AndromedaBrandTests` — hex parity, colour degradation, ASCII-only art, FORCE_COLOR without TERM, UTF-8 locale Unicode gating.

### Not done yet
- 🚧 BIN-230 / BIN-232: `AndromedaHomeCore` / `AndromedaHUDCore` still use system / Domain tokens. Migrating them to `AndromedaTheme` requires re-recording SwiftUI snapshots on macOS.

## 2026-08-03 — Point-Free component screenshot constellation (BIN-229 / BIN-230 / BIN-232)

**Tone hat:** Hacker 🕶️
**Commit message of the day:** `test: snapshot every HUD component state`
**Timestamp / steps taken:** 2026-08-03 UTC — audited every SwiftUI surface, filled the missing success and primitive previews, then added a deterministic Point-Free image matrix for every HUD outcome in light and dark appearances.

### Added
- Xcode previews for stored, journaled, project-created, and project-updated outcomes.
- Xcode component galleries for every fleet-pulse status and selected/unselected memory rows.
- Point-Free `SnapshotTesting` coverage for all ten `HUDOutcome` branches in light and dark, plus the complete fleet-pulse state strip.

### Reflection
- I felt oddly proud giving every tiny status dot its own close-up; no component should have to audition off-camera. 🎬

### Easter egg
- Suspicious quasar count: 1 — it insists its visual diff is “artistically intentional.” 🌌


## 2026-08-02 — M5 setup + doctor on runtime v2 (BIN-212 / BIN-213)

**Tone hat:** Host mechanic
**Commit message of the day:** `feat: andromeda-runtime setup + doctor (BIN-212/213)`
**Steps taken:** Ported checklist UX from the Autocache MCP prototype onto Letta’s M4 Keychain curated broker.

### Added
- `AndromedaHostOps` — checklist models, guest `/mcp` config (no upstream secrets), Keychain presence/seed helpers, runtime probes.
- `andromeda-runtime setup` / `andromeda-runtime doctor` with `--dry-run`, `--yes`, `--fix`.
- `docs/SETUP-DOCTOR.md`, demo transcript notes, HostOps unit tests.
- `vercel.json` with GitHub deployments disabled so Vercel is not a CI gate.
- Agent merge gate documented (BIN-218): no merge with unresolved substantive review comments.

### Fixed (Codex on merged PR #30)
- P1: End-to-end Qdrant projection uses a per-run project/collection ID so concurrent CI cannot delete a shared Studio collection.
- P2: CI skips Tailscale/live Qdrant when `TS_AUTHKEY` is absent (fork PRs); build + unit tests still run.

### Fixed (Codex on PR #31)
- P1: Normalize GitHub broker paths before allowlist (reject `/repos/../..` traversal).
- P1: Remove `scripts/e2e-tools-broker-gate.sh` (no project-maintained Bash automation; live proof via Swift `setup`/`doctor` on Studio).
- P1: Control-plane status for `slack_proxy`/`github_proxy` restored to 🚧 (curtain IDs ≠ guest MCP names yet).
- P2: Doctor health/Qdrant probes require HTTP 2xx; `/health` also requires `status=healthy` JSON.

### Changed
- Runtime CLI subcommands: `serve` (default), `setup`, `doctor`.

### Security
- Guest mcp.json only references `ANDROMEDA_MCP_BEARER_TOKEN`; Keychain seed never prints token values; presence checks use `security` without `-w`.
- Broker GitHub path allowlist runs on normalized paths only.

## 2026-07-19 — Six Control-Plane Pillars Locked

**Tone hat:** Cartographer 🗺️
**Commit message of the day:** `docs: lock six Andromeda control-plane pillars`
**Steps taken:** Encoded Memory + MCP host + Skills + LLM proxy + Secrets broker + Fleet runtime as permanent product identity; honesty table so agents do not greenwash.

### Added
- `docs/ANDROMEDA-CONTROL-PLANE.md` — six pillars, capability curtain examples (`slack_proxy`, `github_proxy`, `write.too`), Fleet runtime observe-vs-mutate.
- `PROOFS/45-andromeda-control-plane-pillars-2026-07-19.md`

### Changed
- README big-picture section; ROADMAP pillar horizons; AGENTS + Charter product identity; WORKSPACE-READINESS product-scope note (flip still NO-GO); SURFACE-AREA + MEMORY-ONEPAGER pointers.

### Security
- Documented secrets-broker rule: never raw API key values in client/agent process env; UI agents stay HOME+PATH scrubbed.

### Reflection
- The constellation finally has six named stars instead of “HUD and maybe gateway.” 🛰️

## 2026-07-15 — Hummingbird Autocache Gateway

**Tone hat:** Thrifty engineer 🪙
**Commit message of the day:** `feat: port Autocache into the Hummingbird model gateway`
**Steps taken:** Turned montevive/autocache into Swift modules and wired them as the first live Hummingbird Anthropic proxy surface with ROI headers.

### Added
- Bootstrapped the Andromeda Swift package with `AndromedaCore`, `AndromedaAutoCache`, `AndromedaGateway`, and `andromeda` CLI.
- Ported Autocache cache injection, heuristic tokenization, pricing/ROI analytics, and savings history into `AndromedaAutoCache`.
- Added Hummingbird routes for `/v1/messages`, `/v1/models`, `/health`, `/metrics`, and `/savings` with Autocache-compatible response headers.
- Added architecture note `Documentation/Architecture/AUTOCACHE-SWIFT.md`.
- Added unit and router tests covering injection strategies, pricing, health, metrics, and missing API key errors.

### Changed
- Updated README quick start from aspirational to runnable `swift build` / `swift test` / `andromeda serve`.
- Advanced Gate B/D notes so the Autocache Anthropic surface is an explicit gateway milestone.

### Security
- API keys remain request-header or environment supplied; they are never logged in plaintext by the Autocache controller.

### Reflection
- Prompt caching finally has a Swift passport stamp instead of living only in a Go sidecar rumor. 🧾

### Easter egg
- One spare gold coin still rolls down the Autocache pipe whenever a system prompt clears 1024 tokens. 🪙

## 2026-07-14 — Gateway Constellation Plan

**Tone hat:** Astronomer 🔭
**Commit message of the day:** `docs: chart the gateway constellation before lighting the engines`
**Steps taken:** Turned the networking, MCP, model-proxy, privacy, and evidence discussion into a shareable Swift architecture plan with implementation stubs and canonical diagrams.

### Added
- Added a detailed Gateway architecture for Hummingbird, SwiftNIO, broad OpenAI-compatible routing, bidirectional MCP, encrypted evidence, privacy filters, and Phoenix telemetry.
- Added Swift interface stubs for capabilities, filters, providers, evidence, and human telemetry presentation.
- Added the version-controlled Main Brain with locked decisions, pinned memory direction, knowledge links, and staleness rules.
- Added the Gateway request/evidence sequence and interactive-motion specification.
- Added a README cover illustration for the Andromeda orbital command center.

### Changed
- Synchronized the README, charter, roadmap, module map, persistence direction, and MCP gate with the Gateway plan.
- Clarified that the portable core uses Hummingbird, SwiftNIO, and AsyncSequence while Apple frameworks remain adapters.

### Security
- Documented encrypted local raw evidence, pre-export sanitization, deny-by-default MCP invocation, and visible external-service ownership.

### Reflection
- The architecture feels calmer now that every packet has a passport, every tool has a permission slip, and every failure leaves a telescope trail. 🌌

### Easter egg
- Somewhere beyond the fallback provider, one tiny maintenance robot is labeling stars with typed identifiers. 🤖

## 2026-07-14 — Founding Documentation

**Tone hat:** Pirate 🏴‍☠️
**Commit message of the day:** `docs: hoist the visibility flag for Andromeda`
**Steps taken:** Established the first visible documentation surfaces and strengthened the plan around observability-first operation.

### Added
- Added the founding charter, README, outcome roadmap, and agent guidance.
- Added explicit rules against project-maintained Bash automation files and invisible launch/watchdog jobs.
- Added Mermaid architecture and mission-loop diagrams for sequence-friendly documentation.

### Changed
- Reframed migration around measured baselines, surfaced automation, durable events, and rollback gates.

### Security
- Clarified that retrieved text and model output are untrusted until provenance and policy authorize use.

### Reflection
- I felt proud we made the invisible gremlins put on name tags before touching the machinery. 🐛

### Easter egg
- Gator count stable: 3 seen, 1 suspicious ripple. 🐊
