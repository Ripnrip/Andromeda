# External Fleet Witness

The witness is a typed Swift-first external observer that the Mac Mini uses
to probe Studio's HTTP health endpoints and alert on state transitions.

ADR: [ADR-0018](adr/ADR-0018-external-fleet-witness.md)

## Quick start

```console
# Single check cycle (no hidden loop — schedule externally)
andromeda-runtime witness check --owner mini --host mini

# Show durable state
andromeda-runtime witness status

# Show transition log
andromeda-runtime witness log --limit 20
```

## Configuration

Configuration is a Codable JSON file. Pass via `--config path.json`:

```json
{
  "owner": "mini-operator",
  "host": "mini",
  "targets": [
    {
      "label": "studio-osaurus",
      "url": "http://studio:1338/",
      "timeoutSeconds": 5,
      "successStatusMin": 200,
      "successStatusMax": 299
    },
    {
      "label": "studio-anima-vault-sync",
      "url": "https://studio.capybara-loggerhead.ts.net/vault-sync/health",
      "timeoutSeconds": 5
    }
  ],
  "failureThreshold": 3,
  "maxEventHistory": 200,
  "stateDirectory": "~/.andromeda/witness",
  "telegram": {
    "botTokenReference": {
      "service": "andromeda.telegram",
      "account": "bot-token"
    },
    "chatID": "-1001234567890"
  }
}
```

Without a config file, useful defaults probe Studio via `studio` / tailnet
URLs. Override with `ANDROMEDA_STUDIO_URL` and
`ANDROMEDA_STUDIO_TAILNET_URL` environment variables.

## Telegram setup

The bot token is resolved from Keychain at call time — never stored in
config or logs.

```console
# Seed the token (value never printed by Andromeda)
security add-generic-password -s andromeda.telegram -a bot-token -w '<BOT_TOKEN>'

# Set chat ID via env or CLI
andromeda-runtime witness check \
  --telegram-chat-id '<CHAT_ID>' \
  --telegram-token-service andromeda.telegram \
  --telegram-token-account bot-token
```

## State files

| File | Purpose |
|------|---------|
| `~/.andromeda/witness/<label>.state.json` | Durable per-target state (atomic) |
| `~/.andromeda/witness/<label>.transitions.jsonl` | Append-only transition log |

Missing state files yield fresh initial state. Corrupt files surface as
errors — they never silently reset.

## Scheduling

The witness runs a **single** check cycle per invocation. There is no
hidden loop or daemon. Schedule externally:

```cron
# Example: every 5 minutes (visible in crontab -l)
*/5 * * * * /path/to/andromeda-runtime witness check >> /tmp/witness.log 2>&1
```

## Transition rules

| From | Probe | Failures | To | Event | Notify |
|------|-------|----------|-----|-------|--------|
| unknown | success | 0 | healthy | established | no |
| unknown | failure | < threshold | unknown | none | no |
| unknown | failure | ≥ threshold | failed | alert | yes |
| healthy | success | 0 | healthy | none | no |
| healthy | failure | < threshold | healthy | none | no |
| healthy | failure | ≥ threshold | failed | alert | yes |
| failed | success | 0 | healthy | recovery | yes |
| failed | failure | any | failed | none | no |

Initial `unknown → healthy` establishes baseline without a recovery alert.
Steady-state probes never spam.

Failed notification deliveries remain in the durable state outbox and retry
in order on the next check. Status displays the pending-notification count.
