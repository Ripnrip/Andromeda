# Changelog

All notable changes to Andromeda will be documented here.

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
