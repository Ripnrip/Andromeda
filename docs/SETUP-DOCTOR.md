# Setup + Doctor (BIN-212 / BIN-213)

Host-first, idempotent commands on `andromeda-runtime` for the M4 tools/MCP broker.

## What Tom runs after merge

On the **host** (Studio / Mac with Keychain):

```bash
# 1) Seed Keychain from env (values never printed) + write guest mcp.json
export ANDROMEDA_MCP_BEARER_TOKEN='…broker-only…'
export ANDROMEDA_GITHUB_TOKEN="$(gh auth token)"   # optional
export ANDROMEDA_SLACK_TOKEN='xoxb-…'              # optional

andromeda-runtime setup --yes --fix \
  --runtime-url "http://<tailnet-host>:8788" \
  --write-guest-config ~/Developer/AndromedaData/guest-mcp.json

# 2) Start the runtime in the foreground (visible)
andromeda-runtime serve \
  --host 0.0.0.0 --port 8788 \
  --journal-path ~/Developer/AndromedaData/journal.jsonl \
  --vault-dir ~/Developer/AndromedaData/vault \
  --mcp-bearer-token "$ANDROMEDA_MCP_BEARER_TOKEN" \
  --github-token-service andromeda.github --github-token-account token \
  --slack-token-service andromeda.slack --slack-token-account token

# 3) Diagnose anytime
andromeda-runtime doctor --guest-config ~/Developer/AndromedaData/guest-mcp.json
```

On the **VM** (agent-habitat / Tom’s guest):

- Copy only `guest-mcp.json` (URL + `ANDROMEDA_MCP_BEARER_TOKEN`).
- **Do not** put `GITHUB_TOKEN`, `ghp_*`, `xoxb-*`, or Slack tokens in the guest.
- MCP calls hit `POST /mcp` → curated `andromeda_*` tools → host Keychain → upstream.

## Capability curtain

Guests see: `andromeda_github_get_me`, `andromeda_github_request`, `andromeda_slack_post_message`, `andromeda_slack_request`.

Operators track work in Linear / Multica / Slack — those brands never appear in the tool menu.

## Flags

| Command | Flag | Effect |
|---------|------|--------|
| `setup` | `--dry-run` | Checklist only; no Keychain/FS writes |
| `setup` | `--yes` / `--non-interactive` | Skip prompts |
| `setup` / `doctor` | `--fix` | Create journal/vault dirs; seed Keychain from env if missing |
| `doctor` | `--guest-config` | Scrub-check a guest mcp.json |
| `doctor` | `--health-url` / `--qdrant-url` / `--mcp-url` | Override probes |

Exit code `1` if any checklist row is `fail`.

## Relation to PR #28 / #29

- **PR #29** (M4 curated broker + Keychain) is the tools pillar to merge.
- **PR #28** (Autocache `/v1/mcp` env-vault prototype) contributed the checklist UX shape; this doc’s commands live on **runtime v2**, not Autocache-main.
