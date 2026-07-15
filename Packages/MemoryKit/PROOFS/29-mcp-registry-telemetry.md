# BIN-29 Proof — MCPServerRegistry + Day-1 Telemetry

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `feat/mcp-registry-telemetry`  
**Package:** `Packages/MemoryKit`  
**Observe-first:** mock / null process enumerator only — **no process killing** in tests  
**Capabilities (client-facing):** `infra.mcp.list` · `infra.mcp.scan`  
**Never expose:** Linear / Multica brand names in UI or capability IDs  
**Cross-links:** HAB-43 · `docs/MCP-SPRAWL-PROBLEM.md`

## What was proven

1. **Entity shape** — `MCPServerEntity` carries `id`, `packageName`, `command`, optional `pid` / `memoryMB`, `duplicateGroup`, `source` (cursor/claude/codex/hermes/…), plus live instance count + duplicate badge.
2. **Catalog seeds** — Cursor / Claude / Codex / Hermes config inventory from MCP sprawl doc (30+ seeds); config-only until scan attaches live pids.
3. **Live inventory** — injectable `MCPProcessEnumerating` (`Null` / `Mock` / `Shell` ps parser). Fixtures reproduce filesystem/memory/sequential **×15** + firecrawl ×2 (**47** processes).
4. **Dedupe grouping** — same `duplicateGroup` collapses sprawl; badge `×15` on live twins. Config seeds annotated with counts but stay `isLive == false`.
5. **Telemetry day-1** — emits `registry.scan`, `mcp.process_count`, `mcp.duplicate_detected` to OSLog + optional span hook (`Null` / `Recording` / `File` JSONL for observability agent).
6. **UI** — read-only `MCPRegistryView` + `#Preview` light/dark + empty/sprawl + large Dynamic Type; SnapshotTesting pixel catalog (4 images).
7. **No kill path** — registry / tests / shell enumerator never call kill/pkill/unload.

## Commands run

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
# Worktree isolation used during parallel-agent churn:
# /tmp/mcp-registry-wt/Packages/MemoryKit
swift test --build-path /tmp/memorykit-mcp-wt-build \
  --filter 'MCPServerRegistryTests|MCPRegistryViewTests|MCPRegistrySnapshotTests'
```

Swift: Apple Swift 6.2, target `arm64-apple-macosx14.0`.

## Test output summary

| Layer | Result | Count |
|-------|--------|------:|
| Swift Testing (`MCPServerRegistry` + view presentation) | PASS | **14** |
| XCTest SnapshotTesting (`MCPRegistrySnapshotTests`) | PASS | **4** |
| **Total** | **PASS** | **18** |
| FAIL | — | **0** |

### Swift Testing coverage

| Test | Proves |
|------|--------|
| Catalog seeds Cursor/Claude/Codex/Hermes | config inventory |
| Capability IDs `infra.mcp.list` / `infra.mcp.scan` | no tracker brands |
| Package normalizer | npm exec → duplicate group |
| Sprawl fixture ×15 grouping | filesystem×15 problem |
| Unique fixture no sprawl | badge absent |
| Null enumerator no fake live | fail-closed |
| list + immutable scan | capability sketch |
| Telemetry events | day-1 event names |
| File span hook JSONL | observability agent hook |
| Entity Codable | console/n8n serialization |
| ps parser | Shell enumerator without live shell |
| Empty / sprawl presentation | UI contract |
| Presentation titles | empty + sprawl headlines |

### Snapshot catalog

- `testEmptyLight.empty-light.png`
- `testEmptyDark.empty-dark.png`
- `testSprawlLight.sprawl-light.png`
- `testSprawlDark.sprawl-dark.png`

Path: `Tests/MemoryKitTests/__Snapshots__/MCPRegistrySnapshotTests/`

## Evidence artifacts

- Log: `/tmp/memorykit-mcp-registry-proof.log`
- Sources:
  - `Sources/MemoryKit/Registry/MCPServerEntity.swift`
  - `Sources/MemoryKit/Registry/MCPServerRegistry.swift`
  - `Sources/MemoryKit/Telemetry/MCPTelemetry.swift`
  - `Sources/MemoryKit/UI/MCPRegistryView.swift`
- Tests:
  - `Tests/MemoryKitTests/MCPServerRegistryTests.swift`
  - `Tests/MemoryKitTests/MCPRegistrySnapshotTests.swift`
- Collateral fix: `AnimaStorageError: Equatable` (unblocks `RetrievalServiceError` synthesize)

## Remaining gaps / stubs

- Live `ShellMCPProcessEnumerator` not wired into Andromeda console yet (Null/Mock proven).
- Dedupe **policy** (share one process / refuse spawn) is visibility-only — no kill / no lifecycle control in BIN-29.
- Config file parsers (read real `mcp.json` / Codex TOML) still seed-static; live truth comes from process scan.
- OTLP exporter not bundled — `MCPTelemetrySpanHooking` is the interface for the observability agent.

## Fixes applied during this proof

- Config seeds no longer flip `isLive` when a matching duplicate group has processes (pid rows only).
- SnapshotTesting via `NSHostingController` (macOS SwiftUI `.image` overload ambiguity).
- `AnimaStorageError` gained `Equatable` so the package emits.
