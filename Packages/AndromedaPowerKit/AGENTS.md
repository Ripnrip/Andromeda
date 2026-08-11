# AGENTS.md — Power Lease Integration Contract

This package is host infrastructure for Andromeda's macOS supervisor.

## Prime directive

Do not let individual agents own macOS sleep policy.

Agents declare execution requirements. The supervisor grants and releases leases.

## Integration target

Place `AndromedaPowerKit` in the **Background Process HUD / macOS Runtime** repo or package group.

Do not place macOS `ProcessInfo` / IOKit code in portable Andromeda Core.

## Required execution pattern

For any unattended job that can be harmed by host sleep:

```swift
let lease = await powerManager.acquire(
    owner: agentID,
    reason: humanReadableJobName,
    requirements: [.preventSystemSleep]
)

defer {
    Task { await powerManager.release(lease) }
}

try await executeJob()
```

Interactive display-driving jobs may request:

```swift
[.preventSystemSleep, .preventDisplaySleep]
```

Do not request display wakefulness for normal render/build/upload work.

## Never

- call `caffeinate` from agent implementations when supervisor APIs exist;
- run `sudo pmset ...` to make temporary jobs work;
- create one `PowerAssertionManager` per agent;
- release another job's lease;
- hold a lease across unrelated idle time;
- treat a power lease as an excuse to ignore cancellation.

## Events

Translate `PowerEvent` into the canonical Andromeda runtime event stream.

Minimum event coverage:

```text
power.lease.acquired
power.lease.released
power.assertion.changed
```

Preserve owner, reason, lease ID, active lease count, and requirements.

## Tests required for changes

Maintain coverage for:

- multiple simultaneous system-sleep leases;
- display lease aggregation;
- releasing one lease while another remains;
- duplicate release safety;
- release-all behavior;
- cancellation/error-path release in supervisor integration tests.

## Design boundary

Portable layer:

```text
JobExecutionRequirements
```

macOS supervisor layer:

```text
PowerAssertionManager
PowerAssertionBackend
ProcessInfoPowerAssertionBackend
```

HUD:

```text
presentation only
```

## Desired runtime flow

```text
Agent
  ↓ declares requirement
Job Supervisor
  ↓ acquires lease
PowerAssertionManager
  ↓ aggregate assertion
macOS
  ↓ event facts
Runtime Event Bus
  ↓
Background Process HUD
```

Keep it boring, scoped, reference-counted, and observable.
