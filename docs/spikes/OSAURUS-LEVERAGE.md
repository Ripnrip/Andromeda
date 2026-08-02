# Spike: Osaurus leverage for Andromeda MCP

**Status:** Closed — learn, do not port into BIN-207 MVP  
**Linear:** [BIN-216](https://linear.app/binary-bros/issue/BIN-216/spike-leverage-osaurus-tools-osauruscorenetworking-for-andromeda-mcp)  
**Asked:** Admin (2026-08-02) — evaluate [osaurus-tools](https://github.com/osaurus-ai/osaurus-tools) and [OsaurusCore/Networking](https://github.com/osaurus-ai/osaurus/tree/main/Packages/OsaurusCore/Networking)  
**Related asks:** Recouse/EventSource, Swinject (thread + BIN-207)

Andromeda's gateway charter already cites Osaurus as an *idea source* (native serving, SSE, MCP bridging) — not a port target. This spike checks whether the two linked trees change that for the Slack/GitHub MCP shim.

## Verdict

| Source | Ship into BIN-207? | Why |
|--------|--------------------|-----|
| osaurus-tools | **No** | Plugin registry + `.dylib` ABI for Osaurus host — different product surface |
| OsaurusCore/Networking | **No port** | Useful *patterns* (host bridge, egress identity, tool deny list, secret scrub). Implementation is raw NIO + 500KB+ `HTTPHandler`; we use Hummingbird + `AndromedaMCP` |
| EventSource | **Defer** | Osaurus uses **`mattt/eventsource`** transitively via [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) — not Recouse. Adopt with official MCP SDK when we leave buffered JSON-RPC |
| Swinject | **No** | Neither tree argues for it; stay initializer injection + protocols + actors |

## 1. osaurus-tools

### What it is

Central registry for community Osaurus plugins. Official core today: `osaurus.fetch`, `osaurus.browser`. Plugins ship as signed `.dylib` zips with embedded manifests, optional `SKILL.md` / `web/`, and JSON registry specs under `plugins/*.json`.

Filesystem/Git were removed from plugins (host first-class). Time/search/macos-use retired in favor of host built-ins.

### What to steal (ideas only)

- **Curated capability menus** — each plugin declares a small, named tool set. Same direction as Andromeda option-1 slim allowlists after the option-2 wrapper.
- **`osaurus.fetch` SSRF + size limits** — reserved CIDR denylist, redirect checks, bounded downloads. Relevant *if* we broker a `fetch` capability later; irrelevant to Slack/GitHub shim auth injection.
- **SKILL.md beside tools** — agent guidance colocated with the tool surface (discovery hygiene).

### What not to steal

- Plugin C ABI / out-of-process plugin host
- Minisign artifact pipeline and registry CI
- WebKit browser session model (Osaurus-specific)

## 2. OsaurusCore/Networking

Inspected files include `HostAPIBridgeServer`, `SandboxEgressProxy`, `SharedEventLoopGroups`, `RequestValidator`, `HTTPProtocolErrors`, `SecureChannelResponseEncryptor`, `RelayTunnelManager`, and MCP routes inside `HTTPHandler`.

### Patterns that rhyme with Andromeda

| Osaurus | Andromeda today | Takeaway |
|---------|-----------------|----------|
| `HostAPIBridgeServer` — Unix socket (vsock-relayed); guest identity via bridge token | `/v1/mcp` + `ANDROMEDA_BROKER_TOKEN` | Same *shape*: host is authority; guest carries a broker credential |
| `GET /api/secrets/{name}` returns secret value to plugin | Host injects upstream; guest never receives Slack/GitHub tokens | **Do not copy their API.** Our curtain is stricter (and correct for VM agents) |
| `SandboxEgressProxy` — `Proxy-Authorization` token → agent allowlist; DNS rebinding checks | Tool allowlists + host-only upstream URLs | Steal the *identity-from-token-only* rule and “never trust guest-claimed identity” |
| `/mcp/health`, `GET /mcp/tools`, `POST /mcp/call` + external deny list | `GET /v1/mcp/health`, JSON-RPC `tools/list` / `tools/call` + allowlists | Their surface is simpler REST; ours is closer to MCP JSON-RPC clients. Keep ours; borrow deny/allow discipline |
| `SecretArgumentScrubber` | `SecretScrubber` in `AndromedaMCP` | Already covered for MVP |
| SSE keepalive `: ping`, in-band SSE errors after 200 | Autocache hand-rolled ByteBuffer SSE | Useful when streaming MCP; not blocking BIN-207 |
| `SharedEventLoopGroups` (fix EMFILE from many ELGs) | Hummingbird owns loops | Lesson noted; no action unless we spawn raw NIO servers beside Hummingbird |
| Official MCP Swift SDK + `mattt/eventsource` | Hand-rolled JSON-RPC + `URLSession` upstream | **Best follow-on** for Streamable HTTP / SSE MCP client |

### What not to port

- Bonjour advertiser/browser, secure-channel encryptor, relay tunnels
- Monolithic `HTTPHandler` (OpenAI/Anthropic/MCP/images in one type)
- Returning plaintext secrets across the host→guest bridge

## 3. EventSource + Swinject (thread asks)

- **EventSource:** Prefer tracking Osaurus’s actual choice — MCP Swift SDK → `mattt/eventsource` — when implementing Streamable HTTP. Recouse remains optional; don’t add either until the transport milestone.
- **Swinject:** No evidence in either tree. Composition-root-only if CLI/HUD wiring becomes combinatorial.

## Follow-ons (optional Linear children)

1. **Adopt `modelcontextprotocol/swift-sdk` (+ EventSource)** for upstream MCP client in `HTTPUpstreamMCPProvider`.
2. **SSRF-guarded brokered fetch** capability (inspired by `osaurus.fetch`), still host-auth / guest-broker.
3. **Host-bridge identity hardening** — document token-bound identity rules copied from `SandboxEgressProxy` into Andromeda broker auth ADR.

## Multica

Studio Habitat API was unreachable from the cloud agent at spike time. Create HAB cross-link to **BIN-216** on Studio when available; do not block the spike close.

## Decision record

**2026-08-02:** Spike closed Done. No code dependency on osaurus-tools or a Networking port for BIN-207. Patterns captured here and in BIN-216.
