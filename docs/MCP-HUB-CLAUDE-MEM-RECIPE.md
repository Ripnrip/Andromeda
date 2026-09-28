# Hub Migration Recipe — claude-mem (chroma + qdrant)

> Parent-executed lane (subagent S4 was terminated by provider failover).
> Status: **recipe/proposal — not shipped behavior.** No live config changed.
> HAB-731 · context: [MCP-ORPHAN-EPIDEMIC-2026-09-27.md](./MCP-ORPHAN-EPIDEMIC-2026-09-27.md), [CLAUDE-MEM-HOOK-FIX-2026-09-28.md](./CLAUDE-MEM-HOOK-FIX-2026-09-28.md)

## Goal

Host the claude-mem backing stores behind the shared Andromeda MCP hub
(ADR-0019) so Claude Code sessions stop spawning per-session chroma/qdrant
stdio servers — the process class that produced the HAB-727 orphan epidemic.

## 1. servers.json entries (fixture validated)

Fixture: [`config/mcp-hub/examples/claude-mem-servers.example.json`](../config/mcp-hub/examples/claude-mem-servers.example.json)

- `chroma-mem` — derived verbatim from the real epidemic spawn command:
  `/opt/homebrew/bin/uv tool uvx --python 3.13 --with onnxruntime>=1.20 --with
  protobuf<7 --from chroma-mcp==0.2.6 chroma-mcp --client-type persistent
  --data-dir /Users/admin/.claude-mem/chroma`, placement `shared`,
  duplicateGroup `chroma-mcp`.
- `qdrant-mem` — `/Users/admin/.local/share/uv/tools/qdrant-mcp-server/bin/python3
  /Users/admin/.local/bin/qdrant-mcp-server`, placement `shared`,
  duplicateGroup `qdrant-mcp`.

Validate proof (real output, 2026-09-28):

```
$ andromeda mcp-hub validate --config config/mcp-hub/examples/claude-mem-servers.example.json
✅ chroma-mem — chroma-mcp [shared] → /opt/homebrew/bin/uv tool uvx --python 3.13 --with onnxruntime>=1.20 --with protobuf<7 --from chroma-mcp==0.2.6 chroma-mcp --client-type persistent --data-dir /Users/admin/.claude-mem/chroma
✅ qdrant-mem — qdrant-mcp-server [shared] → /Users/admin/.local/share/uv/tools/qdrant-mcp-server/bin/python3 /Users/admin/.local/bin/qdrant-mcp-server
```

## 2. What the hub implements today (honest)

- Spawns configured servers as long-lived children and exposes each at a
  unix socket under `socketDirectory` (per ADR-0019 and the AndromedaMCPHub
  sources; `andromeda mcp-hub run` is the launchd entry, `status` probes
  sockets).
- **Not implemented today:** a Claude-Code-side stdio→socket shim. Claude
  Code launches MCP servers by command; it does not natively speak a unix
  socket transport for `mcpServers`. Adoption therefore needs either (a) a
  tiny stdio-bridge command Claude Code can spawn that proxies to the hub
  socket, or (b) claude-mem upstream support for an external chroma HTTP
  endpoint (chroma also speaks HTTP — running chroma as a server and pointing
  claude-mem at it may be simpler than MCP proxying).

## 3. Hard blockers (call-outs)

1. **Single-writer chroma data-dir.** `~/.claude-mem/chroma` is written by
   claude-mem's own persistent client (the worker daemon's uvx chroma
   process, live as of 2026-09-28). A hub-hosted `chroma-mcp` on the same
   data-dir while claude-mem also holds a client risks sqlite/HNSW
   corruption. Resolve claude-mem's client ownership FIRST — this is the
   gate, not the wiring.
2. **Plugin lifecycle.** claude-mem spawns its stores itself per the MCP
  config inside the plugin; hub adoption requires a claude-mem config change
   (its `mcpServers` block) or the stdio bridge above. Plugin updates may
   reset it (same recurrence class as the hooks.json reset — see the
   launcher README re-apply discipline).

## 4. Rollout sketch

1. Stand up chroma as a durable HTTP server (or via hub `shared` placement).
2. Point ONE client at it (the claude-mem worker daemon), verify memory
   reads/writes for a day.
3. Only then remove per-session spawns from claude-mem's MCP config.
4. Keep `andromeda mcp-hub reap` dry-runs in the weekly pass; orphan count
   should drop to the intentional-daemon baseline (spared via `--spare`).

## 5. Rollback

The fixture is inert; nothing live changes until the servers.json entries are
merged into the operator config and the hub is (re)started. Rollback = remove
the entries + restart hub + restore claude-mem's own MCP config from its
plugin defaults.
