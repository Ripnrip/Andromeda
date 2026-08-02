# MCP Shim Demo Script

Recorded proof for BIN-207: guest calls Andromeda MCP with **no** Slack/GitHub secrets; host injects auth and returns a scrubbed result.

## Prerequisites

```console
export ANDROMEDA_BROKER_TOKEN=demo-broker
export SLACK_BOT_TOKEN=xoxb-demo-only
export GITHUB_TOKEN=ghp_demo_only
swift build
```

## Steps

1. Emit guest config (must not contain `xoxb-` / `ghp_`):

```console
./.build/debug/andromeda setup --dry-run --gateway-url http://127.0.0.1:8080
```

2. Start gateway in the foreground (visible process — no hidden launchd):

```console
./.build/debug/andromeda serve --host 127.0.0.1 --port 8080
```

3. From a "guest" shell with **only** the broker token:

```console
export ANDROMEDA_BROKER_TOKEN=demo-broker
# Intentionally unset upstream secrets in the guest:
unset SLACK_BOT_TOKEN GITHUB_TOKEN GH_TOKEN SLACK_TOKEN

curl -sS http://127.0.0.1:8080/v1/mcp/health | jq .

curl -sS http://127.0.0.1:8080/v1/mcp \
  -H "Authorization: Bearer $ANDROMEDA_BROKER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_issues","arguments":{"owner":"acme","repo":"demo"}}}'
```

4. Confirm:
   - Guest env has no Slack/GitHub tokens
   - Response succeeds via `github_proxy`
   - Response body does not contain `ghp_demo_only`
   - Host audit / logs show capability forward without secret values

5. Doctor:

```console
./.build/debug/andromeda doctor
```

## Expected narrative (video)

> Guest says `list_issues` (or `slack_post_message`). MCP config has no upstream tokens. Request hits Andromeda `/v1/mcp`, host injects GitHub/Slack auth upstream, scrubbed result returns. Congrats — memory, secrets/vault, and tools/MCP pillars have MVPs.
