# Setup / doctor demo (BIN-212 / BIN-213)

## CLI checklist demos (generated from `AndromedaHostOps`)

These prove the checklist + guest config shape. **Live Keychain + VM screen recordings** still need to be captured on Studio once `andromeda-runtime serve` is up (Swift CLI: `setup --fix` → `serve` → `doctor`, no bash gate).

Artifacts (agent run):
- `/opt/cursor/artifacts/demos/andromeda-setup-demo.mp4`
- `/opt/cursor/artifacts/demos/andromeda-doctor-demo.mp4`
- `docs/demo/setup-checklist.txt`
- `docs/demo/doctor-checklist.txt`

### setup (host-first)

```text
$ andromeda-runtime setup --yes --runtime-url http://studio…:8788
```

See `setup-checklist.txt`. Guest mcp.json only has `ANDROMEDA_MCP_BEARER_TOKEN` — no `ghp_` / `xoxb-`.

### doctor

```text
$ andromeda-runtime doctor
```

See `doctor-checklist.txt` — curated tools/list must be exactly the 4 `andromeda_*` tools.

## Studio follow-up (acceptance)

1. `setup --fix` with real Keychain seed from `gh auth token`
2. `serve` on tailnet
3. `doctor` with live `/health` + `/mcp` probes from host
4. Screen-record both commands for Tom’s merge guide
