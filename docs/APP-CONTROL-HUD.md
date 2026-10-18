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

One gate, one moat, three locks:

```console
ANDROMEDA_APP_CONTROL=1 AndromedaHUD            # port 8791
ANDROMEDA_APP_CONTROL_PORT=8799 AndromedaHUD    # override (tests, parallel runs)
```

1. **`ANDROMEDA_APP_CONTROL=1`** at launch — off by default; the resting HUD
   opens no sockets.
2. **Bind address `127.0.0.1`** — hardcoded, a placement constraint.
3. **The triple lock (HAB-866)** — the bind address is *not* an
   authentication boundary (DNS rebinding resolves foreign names to
   127.0.0.1; any local process can dial loopback), so every request must
   clear all three locks below before any handler runs.

## The triple lock (fail closed)

| Lock | Rule | Failure |
|------|------|---------|
| **Bearer** | Every route requires `Authorization: Bearer <token>` matching the token minted at arm time. | 401 + `WWW-Authenticate` |
| **Origin/Host** | A present `Origin` must be loopback (`127.0.0.1` / `localhost` / `[::1]`, any port); `Origin: null` is rejected; no `Origin` (curl, same-origin tooling) is allowed. The request's Host/authority must be a loopback literal with optional port. | 403 |
| **Content-Type** | `POST /action` must declare `application/json` — checked **before** the body is parsed. | 415 |

### The token flow

- At arm time the HUD loads-or-mints a 256-bit random token and persists it
  at **`~/.andromeda/app-control-token`** with `0600` permissions
  (directory `0700`).
- **Out-of-band distribution**: the loopback HUD client runs as the same
  user on the same machine and reads the file directly. The token never
  rides a socket.
- If the file cannot be read or written, an ephemeral token is minted
  instead — undiscoverable by any client, which fails closed (the door
  stays shut) rather than shipping an open listener.
- Token comparison is constant-time.

```console
TOKEN=$(cat ~/.andromeda/app-control-token)
curl -H "Authorization: Bearer $TOKEN" -H "Host: 127.0.0.1" \
     -H "Content-Type: application/json" \
     -d '{"action":"hud.focus-search"}' http://127.0.0.1:8791/action
```

## Naming law

This is **App Control** (`ANDROMEDA_APP_CONTROL`, loopback bind + bearer +
Origin/Host allowlist + content-type law) — not the **Control Plane**
(`ANDROMEDA_CONTROL_PLANE` + MCP bearer, tailnet). Different doors, both
keyed, on purpose.

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
| `hud.submit-query` | Mirror the field, then `HUDModel.submitQuery(query)` — the **text-submission branch** of Enter |
| `hud.focus-search` | Post `.andromedaHUDFocusSearch` — the status-item / hotkey path |
| `hud.dismiss-results` | `cancelInFlightWork()` + `dismissResults()` — the Escape path |
| `hud.refresh-fleet-pulse` | `refreshFleetPulse()` — the boot refresh |

Parity note: Enter's *row-activation* branches (recent-query fill,
memory-hit open/copy, project-item copy) are human selection gestures over
view-local selection state with clipboard/NSWorkspace side effects — they
are deliberately not remotable, so `hud.submit-query` is documented and
tested as the text-submission branch only (the parity test proves the
pasteboard is untouched).

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
