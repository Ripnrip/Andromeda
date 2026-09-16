# App Control — Andromeda UI drivability

Name this apart from the **product Control Plane** (six-pillar window).

App Control is the debug/test adapter so agents and CI drive the same path a human click takes.

## Contract

| Route | Job |
|-------|-----|
| `GET /state` | Curated JSON read model — not a memory dump. Honesty badges belong here. Never secrets. |
| `POST /action` | Typed `ControlAction` enum. Calls **exactly** the methods buttons call. Unknown = 422. |
| `GET /screenshot` | Off-screen render by identifier. Never `screencapture`. |

Env gate: `ANDROMEDA_APP_CONTROL=1`. Bind loopback (or reuse MCP bearer). Do **not** add a second HTTP host — extend the existing AndromedaHTTP router.

## Identifiers

`andromeda.<pane>.<control>` e.g. `andromeda.hud.search.field`.

Identifier ≠ accessibility label. Both required. Rows: stable data ids, never array index alone.

## Components

AndromedaUI primitives are instrumentable, not smart: caller-supplied IDs, no networking inside GlassCard/tabs/buttons. Decorative motion is screenshot-only unless interactive.

## Rollout

0. Doctor — gap list (almost no identifiers today).
1. Identifiers on Control Plane shell + HUD.
2. App Control MVP + Gate 1 curl proof (human click ≡ POST /action).
3. CLI / MCP translators. OSA deferred until Andromeda.app exists.
4. Verify lane: state ≡ AX ≡ screenshot.

Pin: do not expand “the log is the agent” in this workstream. Evidence dirs are already log-shaped.
