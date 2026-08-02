# MCP Shim — Slack + GitHub via Andromeda

**Status:** MVP (option 2 — auth-preserving wrapper)  
**Linear:** [BIN-207](https://linear.app/binary-bros/issue/BIN-207/mcp-shim-mvp-slack-github-auth-preserving-proxy-option-2) · [BIN-208](https://linear.app/binary-bros/issue/BIN-208/andromeda-setup-doctor-interactive-cli)  
**Parent:** [BIN-102](https://linear.app/binary-bros/issue/BIN-102/andromeda-control-plane-pillars-mcp-host-skills-llm-proxy-secrets)

## Why

Guest VMs (Apple VM / Habitat) need Slack + GitHub tools without holding Slack bot tokens or GitHub PATs. Andromeda on the host keeps those secrets and exposes a single MCP surface.

This lands MVPs for three Hummingbird pillars:

| Pillar | MVP |
|--------|-----|
| Memory | Brokered memory-read (AI-Config / host DB) |
| Secrets / vault | Host `SecretVault` + guest broker token only |
| Tools / MCP | `/v1/mcp` shim for `slack_proxy` + `github_proxy` |

## Approach

1. **Now (option 2):** literal MCP wrapper. Andromeda proxies `tools/list` / `tools/call` to upstream Slack/GitHub MCP (or in-process mocks), injecting host credentials on the upstream hop only.
2. **Next (option 1):** further curate the tool set. Starter allowlists already slim discovery.

Capability curtain IDs (guests see these, never provider brand menus for secrets):

- `slack_proxy`
- `github_proxy`

## Guest config (no upstream secrets)

```json
{
  "mcpServers": {
    "andromeda": {
      "url": "http://<host-tailnet>:8080/v1/mcp",
      "headers": {
        "Authorization": "Bearer ${ANDROMEDA_BROKER_TOKEN}"
      }
    }
  }
}
```

Generate with:

```console
andromeda setup --dry-run
andromeda setup --write-guest-config ~/guest-mcp.json
```

Host env (never copy these into the VM):

- `ANDROMEDA_BROKER_TOKEN` — guest↔Andromeda auth
- `SLACK_BOT_TOKEN` / `SLACK_TOKEN`
- `GITHUB_TOKEN` / `GH_TOKEN`
- Optional: `SLACK_UPSTREAM_MCP_URL`, `GITHUB_UPSTREAM_MCP_URL` for real upstream MCP HTTP endpoints

## Flow

```text
Guest agent  --(broker token)-->  Andromeda /v1/mcp
                                      |
                                      +-- allowlist check
                                      +-- inject host Slack/GitHub credential
                                      +-- upstream tools/call
                                      +-- scrub secrets from response
Guest agent  <------ result -----------+
```

## CLI

```console
andromeda status
andromeda setup [--dry-run] [--write-guest-config PATH]
andromeda doctor [--guest-config PATH]
andromeda serve
```

`setup` and `doctor` are interactive checklists, idempotent, and never print secret values. On macOS they expect a visible status surface (HUD/menubar); on Linux CI they degrade to CLI checklists with a warn.

## Demo

See `docs/demo/mcp-shim-demo.md` and the recorded walkthrough under `/opt/cursor/artifacts/` when generated in-session.

## Tests

```console
swift test --filter AndromedaMCPTests
swift test --filter GatewayMCPRoutes
```
