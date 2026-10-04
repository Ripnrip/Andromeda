# App Control — HUD (`AndromedaHUD`)

Programmatic app control for the HUD process (HAB-838), applying the same
pillar law as the runtime [`/control/*`](./CONTROL-PLANE-ROUTES.md) plane to
the glass: identifiers first, curated state, typed dispatch, one funnel.

## Routes

| Route | Method | Purpose |
|-------|--------|---------|
| `/state` | GET | Curated HUD snapshot (the contract) |
| `/action` | POST | Typed action dispatch — `{"action": "<verb>", "query": "…"}` |
| `/actions` | GET | Action catalogue (surfaces generate from this) |
| `/screenshot` | GET | The glass as PNG — `ImageRenderer`, never `screencapture` |

## Arming the plane

One gate, one moat:

```console
ANDROMEDA_APP_CONTROL=1 AndromedaHUD            # port 8791
ANDROMEDA_APP_CONTROL_PORT=8799 AndromedaHUD    # override (tests, parallel runs)
```

1. **`ANDROMEDA_APP_CONTROL=1`** at launch — off by default; the resting HUD
   opens no sockets.
2. **Bind address `127.0.0.1`** — hardcoded. Unlike the runtime control plane
   (which binds `0.0.0.0` on the tailnet and therefore demands the MCP
   bearer), this listener is loopback-only, so no bearer is minted. **If the
   posture ever broadens beyond loopback — bind change, port forward, SSH
   tunnel — a bearer becomes mandatory before merge.**

## Naming law

This is **App Control** (`ANDROMEDA_APP_CONTROL`, loopback, no bearer) — not
the **Control Plane** (`ANDROMEDA_CONTROL_PLANE` + MCP bearer, tailnet).
Different doors, different keys, on purpose.

## The state contract (v1)

```json
{
  "service": "AndromedaHUD",
  "version": "1",
  "isReady": true,
  "query": "recall fleet",
  "outcome": { "kind": "recalled", "summary": "Recalled 2 memory hits", "hits": 2 },
  "recentQueries": ["recall fleet", "project.state"],
  "fleetPulse": { "status": "green", "attentionCount": 0, "detail": "fleet idle" },
  "showsResultsPanel": false,
  "capturedAt": 1757600000.0
}
```

Curated, additive, behind the capability curtain — no hit narratives, no
provider brands, no secrets. Renames or removals are breaking; bump the
version.

## Actions

| Verb | Effect (the exact on-glass path) |
|------|----------------------------------|
| `hud.submit-query` | Mirror the field, then `HUDModel.submitQuery(query)` — the Enter path |
| `hud.focus-search` | Post `.andromedaHUDFocusSearch` — the status-item / hotkey path |
| `hud.dismiss-results` | `cancelInFlightWork()` + `dismissResults()` — the Escape path |
| `hud.refresh-fleet-pulse` | `refreshFleetPulse()` — the boot refresh |

Typed `AppControlVerb` (`CaseIterable`) + `AppControlAction` (payloads) — one
list; `GET /actions` and unknown-action responses generate from it. Unknown
action names are syntactically valid but semantically unprocessable, so they
get a loud **422** naming the whole catalogue. Missing/invalid JSON fields and
`hud.submit-query` without a non-empty `query` remain **400** payload errors.

## Identifiers (pillar 1 — the glass)

`hud.<pane>.<control>`, stamped via `.hudIdentifier(_:)` from the typed
`HUDIdentifier` catalogue (AndromedaHUDCore) — the single source of spelling.
Static surfaces use named constants. Data-backed rows use stable opaque
factories:

- `recentQuery(_:)` hashes the query and also supplies stable `ForEach`
  identity, so reordering recent queries does not retarget a row.
- `memoryHit(_:)` hashes `MemoryHit.ID`, so a row keeps its identity across
  re-render and reorder. **Bounded stability:** `RetrievalService` mints a
  fresh `MemoryHit.id` per vault recall, so a *vault* row's identifier changes
  when the query is re-run. Durable hot-store hits keep theirs. Making vault
  identity refresh-stable is a MemoryKit change, deliberately not smuggled
  into this slice.
- `projectItem(projectID:itemID:)` hashes the typed `ProjectState.ID` plus
  its project-scoped `ProjectStateItem.ID`.

The factories emit a namespaced 96-bit SHA-256 prefix; raw queries, memory
narratives/projects, project titles, and tracker IDs such as `HAB-*` never
enter AX identifiers. `HUDIdentifierTests` proves distinctness and reorder
stability, then walks the real AppKit AX tree over `NSHostingView` to prove
every identifier materializes. Its hygiene test rejects unregistered `hud*`
strings on glass. The resulting strings are the wire contract; renaming a
namespace migrates every client.

**macOS placement law** (empirical, macOS 26 hosted-AX tree): SwiftUI
identifiers under `NSHostingView` surface only to a real AX client (the
system AX server), never to in-process AppKit queries. A plain container
identifier shadows every descendant's `AXIdentifier` — a `.contain` group
preserves both parent and children at nesting level 1, but a level-2
`.contain` group's own id collapses. So `hud.root` and
`hud.results.container` ride `.contain` containers, while deeper pane ids
ride leaves: `hud.results.recent` sits on the "Recent" header `Text`, and
`hud.results.projects` on a zero-size marker leaf.

## Screenshots

`HUDViewAppControlScreenshotter` renders `HUDView(model:)` through
`ImageRenderer` at 2× — the app's own view tree, the app's own privileges.
Never `screencapture`: that path trips Screen-Recording TCC and can frame
strangers' windows alongside ours.

## Deferred (per HAB-838)

MCP tools over the dispatcher, a verify lane, and OSA/sdef exposure are
explicitly out of scope for this slice.
