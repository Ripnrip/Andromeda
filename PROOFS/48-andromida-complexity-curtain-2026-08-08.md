# Proof 48 — Andromida complexity curtain (BIN-246–252)

> **Date:** 2026-08-08  
> **Status:** 🚧 code + unit tests landed; macOS CI must green the suite  
> **Scope:** MemoryKit curtain core + HUD/Home verb shims + Companion UI shell

## Claims

| Claim | Evidence |
|-------|----------|
| Locked verbs `memory_recall/retain/forget/health` | `MemoryVerbSurface.swift` + HUD/Home parsers |
| JSON outbox is retain authority | `JSONOutboxAuthority.swift` + `AndromidaCurtainTests` |
| Live projection fail-open | `RealmOutboxLiveProjection` forced-fail test |
| Fused recall + tombstones | `RankFusion` + forget suppression test |
| Health / drift / replay | `MemoryComplexityCurtain.health` / `replayPending` tests |
| Companion surface | `AndromidaCompanionView.swift` |
| Backend brands hidden | No Graphiti/Qdrant/Ladybug/RealmSwift in client capability IDs |

## Non-claims (honest)

- Apple `RealmSwift` dependency not added — projection is Realm-**shaped** behind `OutboxLiveProjection` (📐 native Realm adapter).
- HUD forget/health still surface operator messages until HUD session owns a shared `MemoryComplexityCurtain` instance.
- Long-doc / code-graph / synthesis adapters are fail-open stubs.
- LAN canonical markdown (`andromida-complexity-curtain.md`) was unreachable from the cloud agent; implementation follows BIN-246–252 + Linear architecture review + this ADR.

## Test commands

```console
cd Packages/MemoryKit && swift test --filter Andromida
swift test --filter HUDCommand
swift test --filter AndromedaMemoryCommand
```
