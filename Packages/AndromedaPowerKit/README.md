# AndromedaPowerKit

A tiny macOS runtime primitive for **supervisor-owned power leases**.

It exists so autonomous work can safely continue through display idle / sleep transitions without every agent reaching for `caffeinate`, changing global Energy settings, or directly owning macOS power state.

The core rule is simple:

> **Agents request a lease. The supervisor owns the power assertion.**

This keeps the behavior reference-counted, observable, testable, and visible in the Background Process HUD.

---

## Why this exists

The motivating failure was a macOS `WindowServer` watchdog event while the machine was transitioning its displays to sleep while autonomous work was active.

That does **not** mean "agents crash WindowServer." The useful architectural lesson is narrower:

- long-running render / build / upload / benchmark work should be able to declare that the **system must remain awake**;
- interactive UI-driving work may additionally require the **display to remain awake**;
- assertions should exist only while the work actually needs them;
- two simultaneous jobs must not accidentally release each other's protection;
- the HUD should show why the Mac is staying awake.

This package gives Andromeda that primitive.

---

# Where this belongs in Andromeda

## Recommended ownership

**Put this in the macOS supervisor/runtime layer, not Andromeda Core and not inside individual agents.**

If your current split is:

```text
Andromeda Core
├── memory / Anima
├── stable capabilities
├── project state
├── inference / proxy plumbing
└── cross-platform contracts

Background Process HUD / macOS Runtime
├── launchd lifecycle
├── Setup / Doctor / Cleanup
├── job supervision
├── event stream
├── process health
├── PowerAssertionManager      ← PUT IT HERE
└── HUD

Network Transport
├── Bonjour
├── LAN / mesh discovery
├── trust handshake
└── peer transport
```

then `AndromedaPowerKit` belongs in **Background Process HUD / macOS Runtime**.

### Why not Core?

Power assertions are macOS host policy. Memory, project state, inference, and transport should not need to know that `ProcessInfo.beginActivity` exists.

Core can define a portable concept such as:

```swift
struct JobExecutionRequirements {
    var requiresAwakeHost: Bool
    var requiresAwakeDisplay: Bool
}
```

The macOS supervisor translates those requirements into `PowerRequirement`.

That keeps the contract portable while the implementation remains platform-specific.

---

# Integration path

## 1. Add the package

During development, add it as a local Swift package dependency from Xcode or from your parent `Package.swift`.

Example:

```swift
.package(path: "../AndromedaPowerKit")
```

and then:

```swift
.product(
    name: "AndromedaPowerKit",
    package: "AndromedaPowerKit"
)
```

If you prefer, copy this package into something like:

```text
AndromedaBackgroundRuntime/
Packages/AndromedaPowerKit/
```

or make the package a target inside the Background Runtime repo later.

I would start with it as an isolated package because the boundary is extremely clean and it is easy to test.

---

## 2. The supervisor owns exactly one manager

```swift
import AndromedaPowerKit

actor JobSupervisor {
    private let powerManager: PowerAssertionManager

    init(powerEventSink: some PowerEventSink) {
        self.powerManager = PowerAssertionManager(
            eventSink: powerEventSink
        )
    }
}
```

Do **not** instantiate a new manager per agent.

The whole point is for one authority to understand all active leases.

---

## 3. Jobs declare requirements

Prefer declarative metadata:

```swift
struct JobDefinition: Sendable {
    let id: UUID
    let owner: String
    let name: String
    let requirements: JobRequirements
}

struct JobRequirements: Sendable {
    let preventSystemSleep: Bool
    let preventDisplaySleep: Bool
}
```

Mapping example:

| Job | System awake | Display awake |
|---|---:|---:|
| TestFlight archive/upload | yes | no |
| local video render/encode | yes | no |
| GEPA / benchmark run | yes | no |
| memory consolidation | yes | no |
| UI automation | yes | usually yes |
| Simulator screenshots | yes | yes |
| passive indexing | probably no | no |

Default aggressively toward **letting the display sleep**.

---

## 4. Acquire immediately before execution

```swift
let lease = await powerManager.acquire(
    owner: job.owner,
    reason: job.name,
    requirements: [.preventSystemSleep]
)

defer {
    Task {
        await powerManager.release(lease)
    }
}

try await executor.run(job)
```

Or use the convenience wrapper:

```swift
try await withPowerLease(
    manager: powerManager,
    owner: "testflight-agent",
    reason: "Archive + upload build",
    requirements: [.preventSystemSleep]
) {
    try await testFlightAgent.run()
}
```

---

## 5. Feed events into the existing runtime event bus

Implement:

```swift
struct AndromedaPowerEventSink: PowerEventSink {
    let events: RuntimeEventBus

    func emit(_ event: PowerEvent) async {
        // Translate PowerEvent → your canonical RuntimeEvent.
    }
}
```

Suggested canonical events:

```text
power.lease.acquired
power.lease.released
power.assertion.changed
```

Useful fields:

```text
leaseID
jobID
agentID
owner
reason
requirements
activeLeaseCount
timestamp
hostID
```

The power package should **emit facts**.

The HUD decides how to render them.

---

# HUD behavior

The HUD can now show:

```text
02:14:31  ⚡ Host sleep inhibited
          video-agent · Render Andromeda Demo

02:18:09  ⚡ Lease added
          testflight-agent · Archive + upload
          2 active leases

02:21:44  ✅ Render complete
          1 active lease remains

02:26:03  🚀 TestFlight upload complete

02:26:03  🌙 Host sleep permitted
          0 active leases
```

A tiny status surface could simply be:

```text
⚡ Awake · 2 jobs
```

and expand to show the reasons.

---

# Important agent rules

1. **Never run `caffeinate` directly if the Andromeda supervisor is available.**
2. **Never mutate global `pmset` preferences for a job.**
3. **Never own a raw ProcessInfo or IOKit assertion from agent code.**
4. Request a semantic execution requirement from the supervisor.
5. Prefer `preventSystemSleep`.
6. Add `preventDisplaySleep` only when visible screen state is actually required.
7. A lease must cover the smallest useful execution scope.
8. Job cancellation, failure, timeout, and success must all release the lease.
9. If the supervisor dies, macOS automatically loses the ProcessInfo activity with the process; it is not a permanent system setting.
10. Power state is **host infrastructure**, not model policy.

---

# Good first integrations

Start with the jobs most likely to run unattended:

```text
1. local video generation / encoding
2. Xcode archive + TestFlight upload
3. long benchmark / GEPA runs
4. nightly memory consolidation
```

That gives the feature real usage immediately without coupling it to every task type.

---

# Future upgrade: IOKit backend

The package intentionally hides the macOS assertion implementation behind:

```swift
PowerAssertionBackend
```

Today it uses `ProcessInfo.beginActivity`.

Later you can add an IOKit-backed implementation if you want:

- richer assertion names / reasons;
- deeper diagnostics;
- better parity with `pmset -g assertions`;
- assertion IDs for Doctor/HUD inspection.

The supervisor API does not need to change.

---

# Doctor

Add a power section to `andromeda doctor` / Background Runtime Doctor:

```text
Power Assertions
────────────────────────────────
Andromeda leases:       2
Prevent system sleep:   yes
Prevent display sleep:  no

Owners:
  video-agent           Render Andromeda Demo
  testflight-agent      Archive + upload

macOS assertion backend: ProcessInfo
```

If you later add IOKit inspection, Doctor can compare the supervisor's expected state with the host's observed state.

---

# Cleanup / shutdown

Before an intentional supervisor shutdown:

```swift
await powerManager.releaseAll()
```

This is mostly for clean event history and deterministic shutdown. Process-scoped assertions disappear when the owning process exits.

---

# Architecture in one sentence

**Core says what a job needs; the supervisor owns the host resource; PowerKit implements the macOS lease; the event bus records it; the HUD explains it to the human.**

That is the boundary.
