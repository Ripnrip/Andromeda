# Andromeda Charter

**Status:** Founding charter
**Platform:** macOS-first, Swift-native, graph-optimized
**Mission loop:** Observe → Evolve → Execute → Internalize
**Session model:** GPT-5.5

Andromeda is a local-first, Swift-native control plane for multi-agent engineering work. It exists to replace fragile, invisible, script-heavy automation with a coherent, observable, permission-aware system.

## Core Promise

> No silent loss. No invisible automation. No provider lock-in disguised as configuration. No knowledge without provenance. No automation without visibility. No migration without rollback.

## Non-Negotiables

1. **No Bash implementation surface.** Operational behavior must live in Swift modules, typed CLIs, launchable app components, or explicitly documented external tools. Shell snippets may appear only as documentation examples, not as project-maintained automation files.
2. **No invisible launch agents, watchdogs, or hidden daemons.** Background work must be represented in the command bar, menu bar, console, or another observable control surface.
3. **Everything important is observable.** Every meaningful operation must produce structured logs, metrics, trace/span context, status, owner, failure classification, and privacy classification.
4. **Append before processing.** Accepted observations are durably journaled before enrichment, projection, embedding, routing, or remote delivery.
5. **Human authority remains explicit.** The system distinguishes observation, suggestion, reversible action, destructive action, privileged action, and policy change.
6. **Evidence drives evolution.** Prompt, skill, model, policy, and workflow changes require a hypothesis, baseline comparison, evaluation data, provenance, review where appropriate, and rollback.
7. **Local-first, not local-only.** Local state remains useful when providers, hosted graph stores, MCP servers, or telemetry exporters fail.
8. **Capability names beat provider names.** Clients ask for capabilities such as `fast-reasoning`, `code-review`, or `graph-query`; Andromeda resolves providers centrally.

## Product Identity

Andromeda is a gateway, graph-native memory fabric, orchestration engine, and macOS control plane connecting agents, tools, models, MCP servers, Obsidian notes, event journals, graph stores, and human decisions.

**Six pillars (locked 2026-07-19):** (1) Memory / Anima, (2) MCP host, (3) Agent skills home, (4) LLM proxy, (5) Secrets vault/broker, (6) Fleet runtime (LaunchAgents + observability). Canonical detail: `docs/ANDROMEDA-CONTROL-PLANE.md`. Clients call stable capability IDs; Andromeda resolves providers, secrets, and processes behind the curtain.

| Loop stage | Responsibility |
| --- | --- |
| Observe | Capture events, outcomes, documents, tool calls, diagnostics, and decisions. |
| Evolve | Evaluate outcomes and improve prompts, skills, policies, routing, and workflows. |
| Execute | Dispatch controlled work to agents, tools, providers, local processes, and MCP services. |
| Internalize | Convert useful outcomes into durable knowledge, graph relationships, lessons, and reusable capabilities. |

## Architecture Principles

- Keep a single deployable executable early, but preserve internal module boundaries.
- Put volatile providers, SDKs, databases, command execution, filesystems, and MCP transports behind typed interfaces.
- Treat Realm as the Apple runtime's append-first local authority, CloudKit as logical-event synchronization rather than live-file synchronization, Obsidian as the human knowledge projection, Neo4j as a graph projection, and telemetry stores as observability surfaces.
- Make every derived projection replayable from authoritative sources.
- Treat retrieved text and model output as untrusted input, never executable policy.
- Keep Hummingbird, SwiftNIO, AsyncSequence pipelines, protocol contracts, and wire models portable; isolate Combine, Realm, CloudKit, Keychain, OSLog, and Apple Container behind Apple adapters.

## Initial Module Map

| Module | Responsibility |
| --- | --- |
| `AndromedaCore` | IDs, clocks, typed errors, health states, policies, provenance, idempotency, privacy. |
| `AndromedaConfig` | Layered config, validation, last-known-good activation, schema migration, Keychain-backed secrets. |
| `AndromedaEvents` | Append-only journal, ingestion, replay, idempotency, dead-letter handling. |
| `AndromedaGateway` | Stable entry point for agents, CLIs, local apps, MCP clients, and automation. |
| `AndromedaProviders` | Provider adapters, auth, model aliases, streaming, tool calling, health, usage. |
| `AndromedaPipeline` | Typed filters, lifecycle stages, privacy gates, functional stream operators, routing decisions. |
| `AndromedaPrivacy` | PII and secret classification, scrubbing, disclosure policy, export controls. |
| `AndromedaEvidence` | Encrypted raw traces, sanitized derivatives, diffs, transcript imports, portable exports. |
| `AndromedaExecution` | Policy-controlled direct process execution, timeouts, cancellation, audit metadata. |
| `AndromedaMCP` | MCP client/server roles, registry, health monitor, subprocess containment. |
| `AndromedaGraph` | Database-neutral graph model, Neo4j projection, provenance-rich edges. |
| `AndromedaKnowledge` | Markdown/Obsidian sync, frontmatter, search, embeddings, conflict detection. |
| `AndromedaObservability` | OSLog, OpenTelemetry, OpenInference, Phoenix, local JSONL export. |
| `AndromedaScheduling` | Durable jobs, retry queues, leases, backoff, dead letters, idempotency. |
| `AndromedaConsole` | SwiftUI command/menu-bar/console visibility and approvals. |
| `AndromedaApple` | Realm, CloudKit, Keychain, Combine, OSLog, and optional Apple Container adapters. |

## Definition of Done

A change is done only when relevant code compiles cleanly, strict concurrency issues are resolved, tests cover behavior, errors are typed and observable, telemetry is privacy-aware, schemas include migrations, docs are updated, and rollback is possible for operational changes.
