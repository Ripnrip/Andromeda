# ADR-0019 — Shared MCP hub config schema & runtime layout

- **Status:** accepted (Phase 1 MVP)
- **Date:** 2026-09-08
- **Context:** docs/plans/SHARED-MCP-HUB.md (Pillar 2 — MCP home)

## Decision

One JSON document at `~/.andromeda/mcp-hub/servers.json` describes every
hosted server; the hub's runtime layout is deterministic and auditable.

### Schema (typed: `MCPHubConfiguration` / `HubServerConfig`)

```json
{
  "socketDirectory": "~/.andromeda/mcp-hub/sockets",
  "logDirectory": "~/.andromeda/logs",
  "servers": [
    {
      "id": "filesystem",
      "packageName": "@modelcontextprotocol/server-filesystem",
      "command": "/usr/local/bin/node",
      "arguments": ["/Users/admin/.npm/.../server-filesystem/dist/index.js", "/Users/admin"],
      "environment": {},
      "placement": "shared",
      "duplicateGroup": "server-filesystem"
    }
  ]
}
```

### Invariants (enforced by `validated()`)

1. `id` is unique, non-empty, `[a-z0-9-]` — it names the socket
   (`<id>.sock`) and the shim binary (`andromeda-mcp-<id>`).
2. `command` resolves to a real executable — **never** `npm exec` at
   runtime; the entrypoint is resolved once, at config time.
3. `placement` is `shared` for wave 1 (`pooled`/`passthrough` exist in
   the taxonomy but are rejected until spike S3 classifies their servers).
4. `duplicateGroup` matches `MCPServerEntity.duplicateGroup` — hub rows
   and registry rows describe the same citizen.
5. `environment` keys must not be credential-shaped: keys containing
   `secret`/`token`/`key`/`api`/`credential`/`password` (case-insensitive)
   are **rejected at validation** — secrets-bearing servers join only via
   the SecretsBroker lane (plan §2.3: no raw keys in client env). Benign
   config keys (`MEMORY_FILE_PATH`-class) pass.

### Runtime layout

```
~/.andromeda/
  mcp-hub/
    servers.json                  # this schema
    sockets/<server-id>.sock      # ONE listening socket per server
  logs/
    mcp-hub.jsonl                 # telemetry (schema below)
    mcp-hub.launchd.log           # launchd stdout/stderr
```

**Simplification vs the plan doc:** one listening socket *per server*
(the plan sketched per-shim-instance sockets). The hub routes by
connection — a single endpoint per server keeps the socket directory
auditable and the shim's connect path trivial. Per-instance sockets
bought nothing the connection key doesn't already provide.

### Telemetry schema (JSONL)

`{"ts": "<iso8601>", "kind": "<event>", "f_<field>": ...}` — kinds:
`hub.started`, `upstream.spawned|spawn_failed|exited|exhausted`,
`shim.connected|disconnected`, `upstream.response_routed`,
`upstream.notification_broadcast`. Field names are stable contract
(prefix `f_` separates them from envelope keys).

### Id namespacing (relay contract)

One upstream serves N shims; JSON-RPC ids are per-client namespaces, so
the hub rewrites ids per connection both ways:

- client → upstream: `"id": 1` becomes `"id": "<conn>.1"` (string
  composite, numeric-suffix verbatim).
- upstream → client: composites split back; **purely numeric remainders
  restore bare** (the original id was a JSON number). String ids restore
  as strings. Edge case (documented): a *string* id whose content is
  purely numeric (`"5"`) restores as the number `5` — lossy for that
  shape; MCP clients use numeric counters or non-numeric strings, never
  numeric strings, in practice.
- `notifications/cancelled` params.requestId is rewritten with the same
  namespacing (it references a pending id).
- Server-initiated notifications broadcast to every connection verbatim.

## Consequences

- Agents keep per-session processes (shims, ~1-3 MB) but share upstreams
  (the ×15 `npm exec` rows collapse to one named `andromeda-mcpd-<id>`).
- No silent schema changes: this ADR is the contract; `andromeda mcp-hub
  validate` is the enforcement surface.
