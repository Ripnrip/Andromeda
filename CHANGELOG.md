# Changelog

All notable changes to Andromeda will be documented here.

## 2026-07-20 — Self-hosted macOS CI (billing bypass)

### Changed
- `.github/workflows/ci.yml` runs on `[self-hosted, macOS, andromeda]` instead of billed `macos-15`.
- Added `docs/CI-SELF-HOSTED.md` + visible LaunchAgent template `ops/com.andromeda.github-actions-runner.plist`.

### Notes
- Root package is macOS-only — Linux hosted runners cannot replace AppKit CI.
- Operator must register the Studio runner once (token + labels).

## 2026-07-20 — Swift-native `andromeda-install` (BIN-101)

### Added
- SPM library `AndromedaInstall` + executable product `andromeda-install` (build → `~/Applications` → adhoc codesign → HUD LaunchAgent mutate).
- Required target `home|hud|both`; Studio-home plist rewrite to `$HOME`; absolute `/usr/bin/codesign` + `/bin/launchctl`; fail-closed kickstart.
- `AndromedaInstallTests` covering parse, plist render, plan, and kickstart fail-closed.

### Removed
- `scripts/install-and-sign.sh` (Charter/AGENTS ban; Codex P1 on PR #10).

### Changed
- RUNBOOK / CONTROL-PLANE / WORKSPACE-READINESS / `ops/com.andromeda.hud.plist` point at `swift run andromeda-install` only.

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
