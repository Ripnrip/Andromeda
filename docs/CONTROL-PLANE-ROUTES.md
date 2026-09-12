# Control-Plane Routes — `/control/*`

Loopback control plane on the existing Hummingbird runtime listener
(programmatic-app-control pillar 3). One plane, many surfaces: HTTP (curl),
CLI (`andromeda-runtime control`), and future MCP tools all drive the same
typed dispatcher. No surface holds logic of its own.

## Routes

| Route | Method | Purpose |
|-------|--------|---------|
| `/control/state` | GET | Curated runtime snapshot (the contract) |
| `/control/action` | POST | Typed action dispatch — `{"action": "<name>"}` |
| `/control/actions` | GET | Action catalogue (surfaces generate from this) |

## Arming the plane

Two gates, both required:

```console
ANDROMEDA_CONTROL_PLANE=1 \
ANDROMEDA_MCP_BEARER_TOKEN=<token> \
andromeda-runtime serve --journal-path ... --mcp-bearer-token <token>
```

1. **`ANDROMEDA_CONTROL_PLANE=1`** at serve time — off by default. No env
   gate, no routes.
2. **`Authorization: Bearer <ANDROMEDA_MCP_BEARER_TOKEN>`** per request. The
   runtime binds `0.0.0.0` (tailnet-served), so a bare env gate would expose
   a mutation route to every tailnet peer. The MCP bearer is reused
   deliberately: one credential per door, no new secret to mint.

Without a bearer configured, the plane refuses to register even when the env
gate is set (fail-closed, logged).

## The state contract

```json
{
  "service": "Andromeda Runtime",
  "version": "0.3.0-runtime-v2-m3",
  "surfaces": ["http", "mcp", "control"],
  "counts": { "memories": 12, "projectionBacklog": 0 },
  "capturedAt": 1757600000.0
}
```

Curated, additive, honest — counts the surfaces already expose through
`/health`, `/power`, and the dashboard. No secrets, no provider brands
(capability curtain). Renames or removals are breaking; bump the version.

## Actions

| Action | Effect |
|--------|--------|
| `drain-projections` | Re-drive pending projection retries now — the same `ProjectionRuntime.retryPending()` the periodic serve loop runs |

Typed `ControlAction` enum — one list, `CaseIterable`, no string switch.
Adding a case automatically extends the catalogue endpoint and the 400
message.

## CLI surface

```console
andromeda-runtime control state
andromeda-runtime control actions
andromeda-runtime control run drain-projections
```

`--url` / `--token` options; env fallbacks `ANDROMEDA_RUNTIME_URL` /
`ANDROMEDA_MCP_BEARER_TOKEN`.

## Identifiers (pillar 1 — console)

The Orchestrator console controls are addressable via
`.accessibilityIdentifier()` under the `console.*` domain:
`console.sidebar.<screen>`, `console.onboarding.skip|continue`,
`console.sheet.close|back|commit`, `console.sheet.scope.<chip>`,
`console.registry.add-mcp-server`, `console.providers.add-model`,
`console.overview.stream-toggle`. Scheme: `<domain>.<pane>.<control>`,
lowercase, dotted, stable across refactors.

## What this is NOT (honesty law)

- Not a screenshot route yet — `/control/screenshot` (pillar 2) is a future
  addition once the console ships as a bundled app with a window to capture.
- Not bound loopback-only: the listener is the shared runtime listener. The
  bearer gate is the security boundary; the env gate is the feature flag.
