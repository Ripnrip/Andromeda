# Proof 30 — Observability Spine (OTLP / local JSONL)

**Status:** PASS (FileJSONL + mocked OTLP; collector optional)  
**Date:** 2026-07-15  
**Branch:** `feat/observability-spine`  
**Package:** `Packages/MemoryKit`  
**Entities:** `telemetry.otlp_local` · `telemetry.jsonl` · `health.snapshot.load`

## Studio recon (why this shape)

| Probe | Result |
|-------|--------|
| OTLP `:4317` / `:4318` | down |
| Grafana / Phoenix / Jaeger | not running; Phoenix CLI absent |
| Docker daemon | down during proof → collector curl **skipped** (optional) |
| Proven path | FileJSONL under temp / `~/.multibrain/telemetry/` |

Phoenix “optic” is **not** available — documented in `docs/OBSERVABILITY.md`. Day-1 path = OTLP HTTP stub → local collector **or** JSONL fallback.

## What was proven

1. **Emit N events** via `FileJSONLTelemetryClient` → file exists → `readAllEvents()` round-trips 5 ticks.
2. **Span lifecycle** → `span_start` + `span_end` share `spanId`; attrs include `mcp.duplicate_count`.
3. **OTLP mocked** → `OTLPHTTPExporter` posts JSON `resourceSpans` to `/v1/traces` via injected `postHandler` (no live collector).
4. **HealthSnapshotLoader** → with `TelemetryHub.install(FileJSONL…)`, `load(json:)` emits `health.snapshot.load`.

## Commands

```bash
cd ~/Developer/multibrain/Packages/MemoryKit
swift test --build-path /tmp/memorykit-obs-build --filter TelemetryClientTests
```

Optional collector (when Docker is up):

```bash
cd ~/Developer/multibrain/ops/observability
docker compose up -d
curl -sS http://127.0.0.1:13133/
curl -sS -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:4318/v1/traces \
  -H 'Content-Type: application/json' -d '{"resourceSpans":[]}'
```

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 4 |
| FAIL   | 0 |

Suite: `🔭 Observability Spine / TelemetryClient (day-1)` — **passed** (2026-07-15).

```
swift test --package-path Packages/MemoryKit --build-path /tmp/memorykit-obs-clean --filter TelemetryClientTests
# Test run with 4 tests in 1 suite passed
```

Also unblocked package compile: `AnimaStorageError: Equatable` (main could not synthesize `RetrievalServiceError` Equatable).

## Evidence artifacts

- Tests: `Tests/MemoryKitTests/TelemetryClientTests.swift`
- Sources:
  - `Sources/MemoryKit/Telemetry/TelemetryClient.swift`
  - `Sources/MemoryKit/Telemetry/HealthSnapshotLoader.swift` (emit on load)
- Ops: `ops/observability/{docker-compose.yml,otel-collector.yaml,README.md}`
- Canon: `docs/OBSERVABILITY.md`
- Surface: `docs/ANDROMEDA-SURFACE-AREA.md` §E

## Alpha SLOs wired as attrs (not yet scraped)

| SLO | Attr / span |
|-----|-------------|
| Registry scan latency | span `registry.scan` · `duration_ms` |
| health.json freshness | `health.age_seconds` on `health.snapshot.load` |
| MCP duplicate count | `mcp.duplicate_count` |

## Remaining gaps

- Docker was down → live OTLP curl not executed this run.
- Full OpenTelemetry Swift SDK not vendored (HTTP JSON stub only).
- LaunchAgent for collector not installed (compose/brew docs only).
