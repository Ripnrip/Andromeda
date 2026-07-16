# Andromeda Diagrams

These Mermaid diagrams are source-controlled so future rendered GIFs, presentations, and README visuals can be generated from canonical text instead of hand-maintained screenshots.

## Observation Capture Sequence

```mermaid
sequenceDiagram
    autonumber
    participant Agent
    participant Gateway as Andromeda Gateway
    participant Journal as Durable Journal
    participant Projector as Projection Workers
    participant Console as Console/Menu Bar
    participant Telemetry as OTel/Phoenix/OSLog

    Agent->>Gateway: Submit observation with context
    Gateway->>Telemetry: Start trace and classify privacy
    Gateway->>Journal: Append event transactionally
    Journal-->>Gateway: Durable acknowledgment
    Gateway-->>Agent: Accepted eventID
    Journal->>Projector: Notify backlog item
    Projector->>Telemetry: Emit projection span
    Projector->>Console: Update visible backlog/status
    Projector-->>Journal: Mark projected or dead-lettered
    Console->>Telemetry: Expose health and operator action trail
```

## Capability Routing Sequence

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Gateway
    participant Router as Capability Router
    participant Catalog as Model Catalog
    participant Provider
    participant Telemetry

    Client->>Gateway: Request capability code-review
    Gateway->>Router: Resolve capability plus constraints
    Router->>Catalog: Read aliases, health, policy, quotas
    Catalog-->>Router: Candidate providers
    Router->>Telemetry: Record routing decision
    Router->>Provider: Invoke selected adapter
    Provider-->>Router: Stream/result or typed failure
    alt provider healthy
        Router-->>Gateway: Result with usage metadata
    else provider degraded
        Router->>Telemetry: Circuit-breaker/fallback span
        Router->>Provider: Invoke fallback adapter
        Provider-->>Router: Fallback result
    end
    Gateway-->>Client: Stable capability response
```

## Gateway Request and Evidence Sequence

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Gateway as Hummingbird Gateway
    participant Archive as Encrypted Evidence
    participant Privacy as Privacy Pipeline
    participant Policy
    participant Router
    participant Provider
    participant Telemetry
    participant Phoenix

    Client->>Gateway: POST /v1/responses
    Gateway->>Telemetry: Start span and correlation context
    Gateway->>Archive: Append encrypted raw request
    Gateway->>Privacy: Classify and sanitize
    Privacy-->>Gateway: Sanitized request and findings
    Gateway->>Policy: Evaluate filters and permission

    alt denied by policy
        Policy-->>Gateway: Typed policy violation
        Gateway->>Archive: Append denial outcome
        Gateway->>Telemetry: Record sanitized reason
        Gateway-->>Client: Compatible structured error
    else allowed
        Policy->>Router: Resolve capability and affinity
        Router->>Telemetry: Record candidates and reason
        Router->>Provider: Execute with deadline and cancellation
        loop streamed events with backpressure
            Provider-->>Gateway: Provider event
            Gateway->>Archive: Append encrypted event
            Gateway->>Telemetry: Emit sanitized timing and usage
            Gateway-->>Client: SSE event
        end
        Gateway->>Archive: Finalize trace and request diff
        Gateway->>Telemetry: Close spans and usage metrics
        Telemetry-->>Phoenix: Sanitized OTLP/OpenInference export
    end
```

## Motion Specification

The future interactive atlas renders these canonical actors as SVG nodes and edges. Small particles travel along active edges to show request, evidence, and telemetry flow. Motion must include play, pause, step, scrub, keyboard operation, reduced-motion behavior, and a static screen-reader-friendly fallback.
