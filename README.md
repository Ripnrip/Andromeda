# Andromeda

> A macOS-first, Swift-native control plane for visible, durable, graph-aware multi-agent engineering.

![Andromeda orbital command center](Documentation/Assets/andromeda-orbital-command-center.png)

Andromeda replaces fragmented scripts, hidden workers, ad-hoc memory stores, provider-specific model wiring, and silent background automation with one observable system.

## Mission Loop

```mermaid
flowchart LR
    Observe[Observe events and outcomes] --> Evolve[Evolve from evidence]
    Evolve --> Execute[Execute controlled capabilities]
    Execute --> Internalize[Internalize durable knowledge]
    Internalize --> Observe
```

## Architectural Shape

```mermaid
flowchart TD
    Clients[Agents, Apps, CLIs, MCP Clients] --> Gateway[Andromeda Gateway API]
    Gateway --> Router[Capability Router]
    Gateway --> Execution[Execution Engine]
    Gateway --> Knowledge[Knowledge API]
    Router --> Providers[Provider Adapters]
    Execution --> Tools[Tools and MCP]
    Knowledge --> Journal[Durable Event Journal]
    Journal --> Graph[Graph Projector]
    Journal --> Obsidian[Obsidian Projector]
    Graph --> Neo4j[Neo4j Projection]
    Obsidian --> Vault[Markdown Vault]
    Neo4j --> Search[Search and Retrieval]
    Vault --> Search
    Gateway --> Telemetry[OSLog, OTel, OpenInference, Phoenix]
    Router --> Telemetry
    Execution --> Telemetry
    Journal --> Telemetry
```

## Visibility Charter

- No project-maintained Bash automation files.
- No invisible `launchctl` jobs, hidden watchdogs, or mystery daemons.
- Every background job appears in a command-bar, menu-bar, console, or equivalent status surface.
- Every important action has structured logs, metrics, traces, ownership, privacy labels, and failure state.
- Acknowledged observations are written to a durable journal before downstream processing.

## Current Status

The founding architecture is being documented. The active plan is the Gateway spine: Hummingbird and SwiftNIO networking, a broad capability-gated LLM proxy, bidirectional MCP, encrypted evidence, privacy filters, and OpenTelemetry/OpenInference export to local Phoenix.

Implementation should begin with measurement and mocks, not assumptions: inventory the current system, verify failure modes, and prove cancellation, privacy, backpressure, and failure visibility before connecting live providers.

## Proposed Quick Start

```console
swift build
swift test
swift run andromeda status
```

These commands are aspirational until the Swift package is bootstrapped.

## Documentation

- [Charter](ANDROMEDA-CHARTER.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Agent guidance](AGENTS.md)
- [Claude guidance](CLAUDE.md)
- [Sequence diagrams](Documentation/Diagrams/README.md)
- [Gateway architecture](Documentation/Architecture/GATEWAY-ARCHITECTURE.md)
- [Gateway Swift stubs](Documentation/Architecture/GATEWAY-IMPLEMENTATION-STUBS.md)
- [Main Brain](Documentation/Brain/ANDROMEDA-MAIN-BRAIN.md)

## Safety Reminder

Andromeda is under active migration. Do not treat generated projections, model outputs, or retrieved notes as authoritative unless provenance and confidence support that claim.
