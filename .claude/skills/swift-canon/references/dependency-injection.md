# Dependency Injection (framework-free)

Protocol boundaries + constructor injection + **one composition root**. The
fleet runs zero DI containers (no Swinject / Factory / swift-dependencies) —
a package does not import a container for a handful of dependencies. The
pattern below is the canon shape; a container is the upgrade path, not the
default.

## Core rules

- **Side effects live behind protocols.** Every boundary that touches the
  world (process table, signals, disk, network, clock) is a protocol with a
  production implementation and a recording/fixture implementation.
- **Inject through the initializer.** Dependencies are `let` properties
  assigned in `init` — never resolved inside methods, never singletons
  reached through global state.
- **One composition root.** A single value (e.g. `Environment.production`)
  names every wiring in one place. If wiring a feature means reading more
  than one file, the root is missing.
- **Generics for the coordinator, erasers for the environment.** The engine
  stays generic over its providers (`Guardian<Census, Sampler, Signaler>`);
  small `Any*` boxes bridge existential environment values into it. Call
  sites stay declarative either way.
- **Tests never touch the real boundary.** Fixtures and recorders conform to
  the same protocols and flow through the same code path as production.

## The shape

```swift
// 1. Boundary as protocol
public protocol CensusProvider: Sendable {
    func sampleAll() throws -> [ProcessSample]
}

// 2. Production impl + fixture impl, both first-class
public struct LibprocCensus: CensusProvider { /* kill(2)-era real thing */ }
struct FixtureCensus: CensusProvider { let samples: [ProcessSample] }

// 3. Coordinator generic over boundaries
public struct Guardian<Census: CensusProvider, Sampler: PressureProvider>: Sendable { … }

// 4. Composition root names the wiring once
public struct GuardianEnvironment: Sendable {
    public var census: any CensusProvider
    public var sampler: any PressureProvider
    public static var production: GuardianEnvironment { … }
    public func makeGuardian() -> Guardian<AnyCensusProvider, AnyPressureProvider> { … }
}

// 5. Erasers bridge existentials into generics
public struct AnyCensusProvider: CensusProvider {
    private let _sampleAll: @Sendable () throws -> [ProcessSample]
    public init(_ base: any CensusProvider) { _sampleAll = { try base.sampleAll() } }
}
```

## When a container becomes worth it

Upgrade to pointfree `swift-dependencies` (maps 1:1 onto this shape —
`DependencyValues` instead of the environment struct) when:

- several packages resolve the SAME services and the roots start duplicating;
- overrides need to vary per test trait rather than per test type;
- the graph gets deep enough that manual threading is the bug source.

Swinject/Factory-style service locators are not the fleet shape: resolution
at the call site hides dependencies from the type signature.

## Anti-patterns

- **Singletons as the seam** (`Foo.shared`) — untestable without global
  mutation; the type signature lies about its needs.
- **Resolving inside methods** (`Container.resolve()` at the use site) —
  same lie, plus ordering hazards.
- **A DI container for one package** — machinery without a graph to justify it.
- **Mocks that bypass the protocol** (subclass overrides, swizzling) — the
  recording impl must flow through the SAME initializer as production.
- **Actor mocks for synchronous protocols** — an actor's sync methods are
  actor-isolated; the conformance crosses isolation. Use a locked final
  class (`NSLock.withLock`) for sync protocol mocks.
