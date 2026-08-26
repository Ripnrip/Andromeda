# AndromedaGuardian

Fleet-pillar **process guardian**: reaps Xcode source-control daemon hordes
and orphaned MCP stdio children before they peak the host into swap death.
Typed Swift end to end (BIN-101) — never bash. Every sweep leaves a telemetry
record (AGENTS.md: visible status, telemetry, ownership, controls).

```swift
import AndromedaGuardian

let environment = GuardianEnvironment.production
let guardian = environment.makeGuardian()

// Decide only — nothing is signaled:
let report = await guardian.sweep(dryRun: true)

// Execute (SIGTERM → SIGKILL after 10s grace):
let report = await guardian.sweep()
```

## Why this exists (the crime scene, 2026-08-25)

Activity Monitor at the peak: **~16 `com.apple.dt.Xcode.sourcecontrol.Git`
daemons × 1.7–2.6 GB each (~30 GB)**, **~45 cloned `node` MCP children ×
~118 MB**, **61.86 GB swap on a 32 GB host**, four apps Not Responding as
collateral. The causal chain:

```
agent sessions (Claude Code / Codex / Cursor / Trae)
  → stdio MCP children per session (xcodebuildmcp ×6, memory ×4, …)
  → xcodebuildmcp invokes xcodebuild
  → Xcode SourceControl XPC spawns com.apple.dt.Xcode.sourcecontrol.Git
  → daemons leak (two Xcode installs amplify: 26.0 stale + 26.6)
  → daemon RSS + swap explosion → everything Not Responding
```

Two sprawl families, one chain. The guardian breaks it at both ends.

## Architecture

SWPM package, zero external dependencies. Canon Swift 6: strict concurrency,
typed identifiers, rich enums, protocol boundaries, initializer injection.

```
Sources/AndromedaGuardian/
├── GuardianDomain.swift     ProcessSample · ProcessFamily (rich enum) ·
│                            Pressure (rich enum: transformation, not flag) ·
│                            Verdict (typed evidence) · KillDecision · config
├── Policy.swift             PolicyContext · PolicyEngine · PolicyRule values
│                            (pure: census in, verdicts out; R4 never-touch is
│                            structural — enforced by the engine, not by rules)
├── Providers.swift          CensusProvider · PressureProvider ·
│                            ProcessSignaler · TelemetrySink protocols +
│                            production impls (libproc · sysctl swap ·
│                            kill(2) · JSONL)
├── Guardian.swift           Generic coordinator:
│                            Guardian<Census, Sampler, Signaler> — sweep =
│                            census → pressure → policy → execute → telemetry
├── Environment.swift        Composition root (DI, framework-free) +
│                            type erasers (Any* boxes for existentials)
├── EventBroadcaster.swift   GuardianEventBroadcaster actor (the SSE seam) +
│                            sseFrame/sseFrames (text/event-stream framing)
└── Resources/openapi/guardian.yaml   contract-first HTTP surface spec
```

### Dependency injection (why no container)

The repo has **zero DI frameworks** (no Swinject/Factory/swift-dependencies
anywhere), so one package does not import a container. The pattern IS the
canon shape: protocol boundaries + constructor injection + **one composition
root** (`GuardianEnvironment`) that names every wiring as a value.
`Environment.production` wires libproc + kill(2) + JSONL; tests wire
fixtures + recorders through the same `makeGuardian()` seam. Type erasers
(`AnyCensusProvider` etc.) bridge existential environment values into the
generic coordinator. Upgrade path if the graph outgrows this: pointfree
`swift-dependencies` — the shape maps 1:1 onto `DependencyValues`.
(Canon: `dependency-injection.md`.)

### The rules

- **R1 — source-control horde.** No Xcode alive → all daemons are residue
  (reap). Xcode alive → keep newest 2/user (reap the rest). Older than 6h →
  leak, reap regardless. Daemons are read-only SCM helpers Xcode respawns on
  demand — recoverable, no data loss.
- **R2 — orphaned MCP children.** Node process matching the MCP marker set
  with a dead parent and age > 4h → reap. **Never** when the parent chain
  reaches a live agent host (killing breaks a live session's tools).
- **R3 — pressure escalation.** Swap > 24 GB → gates tighten (cap 1, age 1h),
  applied as a typed `Pressure → EffectiveGates` transform.
- **R4 — never-touch (structural).** `ProcessFamily.userApplication` and
  `.agentHost` can never be condemned — enforced by the engine's filter over
  ALL rules, present and future. A rule literally cannot emit a decision
  against CapCut even if someone writes a buggy one.

## Transport surface (always options)

One spec, many doors — `Resources/openapi/guardian.yaml` is the contract
source of truth:

| Transport | Status | Shape |
|---|---|---|
| **HTTP/REST** | spec shipped | `GET /guardian/status` · `GET /guardian/census` · `POST /guardian/sweep` (dry-run default; `dry_run=false` executes) · `GET /guardian/telemetry` |
| **SSE** | spec + in-package broadcaster | `GET /guardian/events` — `text/event-stream`, one `event: sweep` frame per SweepReport. Server maps `GuardianEventBroadcaster.subscribe()` → `sseFrames` (GatewayRouter already serves SSE — same lane) |
| **MCP** | tools spec (`Resources/mcp/guardian-tools.json`) | `guardian.status` / `guardian.sweep` / `guardian.census` tools for agent runtimes — capability-hiding law: stable IDs only, no process internals |
| **GraphQL** | deliberately deferred | Three flat endpoints, no graph traversal — adds a schema layer for zero consumer. Revisit if the surface grows relationships (hosts → daemons → sessions) |

### Code generation (canon: openapi-server.md)

Contract-first: spec is truth, generated code is mechanical, adapters hold
the logic. The intended flow (HAB-370):

1. `swift-openapi-generator` plugin on `guardian.yaml` → client + server stubs
2. Hummingbird route registration stays thin; generated request/response
   types are translated at the edge
3. Business logic lives in handwritten adapters over this package — never in
   generated files
4. The MCP tool adapter reads `guardian-tools.json` and calls the same
   domain (one implementation, three doors)

## Learnings / anti-patterns this package encodes

Hard-won facts from the landing session (2026-08-26) — keep them close:

- **Reaping is recoverable only when the target is.** Source-control daemons
  respawn on demand; user apps do not. The kill list and the never-touch
  list come from the same analysis — never one without the other.
- **Grace before force.** SIGTERM, 10s window, SIGKILL. A reaper that leads
  with -9 teaches nothing and surprises everyone.
- **Grace windows for the freshly orphaned.** A parent that vanished *just
  now* may be mid-restart; age gates (not instant kills) separate corpses
  from convalescents.
- **Protect by ancestry, not by name.** A node MCP child is safe iff its
  parent chain reaches a live agent host — process trees, not process names.
  Bounded walk (8 hops): cycles exist in censuses.
- **Telemetry is not optional.** AGENTS.md law: background behavior must have
  visible status, telemetry, ownership, controls. Every sweep writes a
  SweepReport (JSONL + broadcast) — a reaper you can't audit is a poltergeist.
- **The flake was the data, not the motion** (sibling lesson from the
  orchestrator landing — canon anti-patterns Exhibit 7): pin the RNG source;
  don't just freeze the animation.
- **SDK-stable assumptions rot.** `accessibilityReduceMotion` went get-only
  in the macOS 26 SDK (write via `\._accessibilityReduceMotion`). Anything
  "stable for a decade" deserves a compile check, not a memory.
- **`static` stored properties are illegal in generic types** — put loggers
  at file scope (`GuardianLog`) or in a non-generic namespace enum.
- **Actor conformances to synchronous protocols cross isolation** — a mock
  for a sync protocol (like a signaler) should be a locked class
  (`NSLock.withLock`), not an actor.

## Tests

`swift test` — 19 tests: family classification totality, pressure gate
transform, R1 cap/age/residue matrices, R2 orphan/grace/ancestry protection,
R4 structural protection, idempotency, dry-run/live/already-dead sweeps
through recording boundaries, broadcast fan-out, SSE frame shape/round-trip.
No live process is ever sampled or signaled in tests.

## Out of scope (honest boundaries)

- Killing hung USER applications (destructive — human decision,
  AGENTS.md triple-confirmation law).
- Consolidating MCPs into shared network services (the qdrant precedent) —
  owned by the MCP-SPRAWL workstream in multibrain.
- macOS memory management itself (swap tuning, compressor behavior).
