# Andromeda Roadmap

This roadmap is outcome-driven. Gates advance when exit criteria are met, not when a calendar says they should.

## Gate A — Measured Baseline

**Deliverables**
- Inventory scripts, workers, hooks, stores, launch surfaces, endpoints, and scheduled jobs.
- Verify historical line counts, integration counts, and failure modes.
- Create data-flow and runtime dependency maps.
- Identify silent-failure paths and current observability gaps.

**Exit criteria**
- Every critical existing capability has an owner and migration disposition.
- Every audit claim is marked verified, revised, or unverified.
- Invisible automation is cataloged and either removed, wrapped, or surfaced.

## Gate B — Swift Foundation

**Deliverables**
- Swift package, module boundaries, typed identifiers, typed errors, OSLog bootstrap, OpenTelemetry bootstrap, CLI skeleton, CI verification.
- No Bash implementation files.

**Progress**
- Package bootstrapped with `AndromedaCore`, `AndromedaAutoCache`, `AndromedaGateway`, and `andromeda` CLI.
- Typed configuration/errors and Autocache tests pass on Linux with Swift 6.1.
- Remaining: OSLog/OTel bootstrap, CI verification, Apple adapter packaging.

**Exit criteria**
- Debug and release builds are clean.
- Strict-concurrency warnings are resolved.
- Configuration failures are actionable.
- Local telemetry export works.

## Gate C — Durable Observation

**Deliverables**
- Append-only event journal, idempotent ingestion, replay, dead-letter handling, capture health metrics.

**Exit criteria**
- Acknowledged events survive forced termination.
- Duplicate events do not duplicate durable facts.
- Failed processing creates visible backlog.

## Gate D — Provider Gateway

**Deliverables**
- Hummingbird HTTP surface, SwiftNIO transport edges, compiled Swift topology, capability API, provider adapters, alias-based model catalog, OpenAI generation data-plane compatibility, streaming, health checks, circuit breakers, fallback policy, and usage telemetry.

**Progress**
- Hummingbird Autocache Anthropic proxy is live: `/v1/messages`, `/v1/models`, `/health`, `/metrics`, `/savings`, ROI headers, bypass headers, and heuristic token analysis.
- Remaining: compiled topology DSL, OpenAI-compatible surface, streaming flush path hardening, circuit breakers/fallback, provider registry.

**Exit criteria**
- Provider/model renames are handled centrally.
- Routing decisions are traceable.
- Clients survive tested alias migration unchanged.
- Cancellation and backpressure propagate through streamed responses.

## Gate D.1 — Evidence and Privacy Plane

**Deliverables**
- Encrypted local raw trace archive, PII and secret scrubbing, sanitized telemetry, session reconstruction, structural request diffs, transcript imports, and portable exports.
- OpenTelemetry and OpenInference mapping with local Phoenix as the default sanitized trace destination.

**Exit criteria**
- Sensitive raw payloads never reach normal exporters.
- Trace evidence survives interruption and exposes tamper or decryption failure.
- Exporter failure cannot block or crash the gateway.
- Retention, disk use, export, and deletion remain visible and user-controlled.

## Gate E — Graph and Knowledge Fabric

**Deliverables**
- Versioned graph schema, Neo4j projection, Obsidian sync, provenance, conflict representation, rebuildable search indexes.

**Exit criteria**
- Graph projection can be rebuilt from authoritative data.
- Notes and graph facts preserve provenance.
- Round-trip sync avoids loops and duplicates.

## Gate F — Controlled Execution and MCP

**Deliverables**
- Bidirectional MCP hub, stdio and Streamable HTTP transports, tool registry, deny-by-default permission policy, explicit expiring approvals, process supervision, timeouts, cancellation, trace propagation, and structured command results.

**Exit criteria**
- Tool failures cannot crash the control plane.
- Privileged actions require authorization.
- MCP instability is contained and visible.

## Gate G — Evidence-Based Evolution

**Deliverables**
- Evaluation datasets, prompt/skill versioning, experiments, baseline comparisons, approval gates, rollback.

**Exit criteria**
- Evolved artifacts trace to observations and evaluations.
- Rejected variants remain inspectable.
- Production activation is reversible.

## Gate H — Operational Console

**Deliverables**
- Health dashboard, provider catalog, backlog controls, trace links, graph explorer, config diagnostics, accessible SwiftUI UI.

**Exit criteria**
- Common incidents are diagnosable without manual log spelunking.
- Critical controls support keyboard and assistive technologies.

## Gate I — Migration and Legacy Retirement

**Deliverables**
- Shadow traffic, behavior comparison, cutover checklist, rollback rehearsal, legacy archive.

**Exit criteria**
- No critical capability depends solely on legacy stack.
- Data completeness is verified.
- Legacy retirement is explicitly approved.
