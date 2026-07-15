---
title: Gateway Implementation Stubs
date: 2026-07-14
status: planning
tags:
  - architecture/gateway
  - swift
  - api
aliases:
  - Gateway Stubs
---

# Gateway Implementation Stubs

> [!warning]
> These are contract sketches for design review, not compile-ready source files.

## Capabilities and Decisions

```swift
public enum ModelCapability: Hashable, Sendable {
    case responses
    case chatCompletions
    case legacyCompletions
    case embeddings
    case moderation
    case speech
    case transcription
    case imageGeneration
    case fileStorage
    case batchProcessing
    case streaming
    case toolCalling
}

public enum FilterDecision<Payload: Sendable>: Sendable {
    case proceed(Payload)
    case respond(GatewayResponse)
    case deny(PolicyViolation)
}
```

## Typed Filter Pipeline

```swift
public protocol GatewayFilter<Input, Output>: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func apply(
        _ input: Input,
        context: RequestContext
    ) async throws -> FilterDecision<Output>
}
```

In-process filters compose generically. External HTTP and MCP filters conform through typed adapters. Type erasure exists only at the compiled registry boundary.

## Provider Boundary

```swift
public protocol ModelProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: Set<ModelCapability> { get }

    func execute(
        _ request: ProviderRequest,
        context: RequestContext
    ) -> AsyncThrowingStream<ProviderEvent, Error>
}
```

Provider events distinguish content deltas, tool calls, usage, lifecycle changes, warnings, and terminal errors through a rich enum rather than untyped dictionaries.

## Evidence Boundary

```swift
public protocol EvidenceArchive: Sendable {
    func begin(_ context: RequestContext) async throws -> TraceSessionID

    func append(
        _ event: EncryptedEvidenceEvent,
        to session: TraceSessionID
    ) async throws

    func finalize(
        _ session: TraceSessionID,
        outcome: TraceOutcome
    ) async throws
}
```

## Telemetry Presentation

```swift
public enum TelemetryGlyph: String, Sendable {
    case network = "🌐"
    case model = "🧠"
    case trace = "🔭"
    case mcp = "🧰"
    case persistence = "💾"
    case warning = "⚠️"
    case failure = "❌"
}
```

Glyphs belong to the human renderer. Stable `event.code`, severity, subsystem, trace ID, and privacy fields remain the canonical machine contract.

## Documentation Standard

Every public type and function documents:

- Purpose and invariants.
- Concurrency ownership and `Sendable` expectations.
- Cancellation, deadline, retry, and idempotency behavior.
- Privacy classification and telemetry emitted.
- Failure modes and recovery behavior.
- A small usage example where the contract is not obvious.

Tests receive detailed comments explaining the risk being modeled, especially around concurrency, replay, cancellation, privacy, and wire compatibility.

## Related

- [[Gateway Plan]]
- [[ANDROMEDA-MAIN-BRAIN]]
