# Changelog

All notable changes to Andromeda will be documented here.

## 2026-07-18 — Andromeda HUD Pop-inspired motion

**Tone hat:** Paper physicist 📄
**Commit message of the day:** `feat: add Pop-inspired spring and decay motion to AndromedaHUD`
**Steps taken:** Ported Pop’s spring/decay interaction model into portable Swift (`HUDPopMotion`) — no ObjC Pop dependency — and wired it into HUD expand + drag-release snap.

### Added
- `HUDPopMotion` spring/decay tokens and `HUDSnapEngine.settleWithDecay`.
- Drag velocity sampling in `AndromedaHUDWindowController` for decay coast on mouse-up.
- SwiftUI spring expand/collapse (reduce-motion safe) + Pop motion unit tests.

### Changed
- HUD drag end now coasts with exponential decay before Ice-style menu-bar snap.

## 2026-07-18 — Andromeda HUD modern SwiftUI foundation

**Tone hat:** Glass cutter 🪟
**Commit message of the day:** `feat: add AndromedaHUD modern floating control surface`
**Steps taken:** Landed BIN-55 foundation — `@Observable` pill model, Ice-style snap math, Ask AI capability router, latency budgets, AppKit borderless panel, and SnapshotTesting scaffolding.

### Added
- New `AndromedaHUD` library target with portable snap/search/budget logic and macOS SwiftUI + `NSPanel` chrome.
- Expandable Ask AI field routing to `memory.recall` / `memory.store` / `memory.journal` / `infer.write` (capability curtain).
- Unit tests for snap, search, model, and sub-frame performance budgets; macOS-gated Point-Free snapshot catalog path.
- Docs: `docs/ANDROMEDA-HUD.md`, updated `docs/UI.md`, Gate H progress, charter module map.

### Changed
- Root `Package.swift` exports `AndromedaHUD` and depends on `swift-snapshot-testing` for HUD visual proofs.

### Security
- HUD chrome and search tips never surface Linear/Multica/provider brands; clients see stable capability IDs only.

### Reflection
- The floating bar finally put on a tailored glass suit instead of borrowing last decade's toolbar leftovers. ✨

### Easter egg
- If you drag the pill into the menu bar just right, it clicks into place like Ice sealing a rink. 🏒

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
