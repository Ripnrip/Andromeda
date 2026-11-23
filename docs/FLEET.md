# Fleet — Multi-Brain Hosts

Who runs what. Operational source of truth: `~/Developer/multibrain/docs/FLEET.md`;
`~/Developer/Andromeda/docs/FLEET.md` is its byte-identical projection.
Identity reverified 2026-10-07 under **HAB-928**; Book is a user-confirmed mobile laptop.
Live service observations are timestamped evidence, not permanent health guarantees.
Ops detail: [RUNBOOK.md](RUNBOOK.md).

## Topology

```text
Studio (hub; canonical vault)
  ├─ Tailscale/SSH → habitat VM (agent-habitat; <tailscale-ip>)
  │                   VirtualMac2,1; Hermes state.db ingest
  ├─ LAN/SSH      → physical iMac (agent-habitat-home; <lan-ip>)
  │                   iMac18,2; Homebridge :8581; Tailscale logged out
  ├─ LAN/SSH      → Fleet Node: <NODE> (<hostname>; <lan-ip>)
  │                   <ARCH> <PLATFORM>; Pi Fleet services (<SVC1>:<PORT>, <SVC2>:<PORT>, <SVC3>:<PORT>)
  └─ opportunistic→ Book (book-1; <tailscale-ip>)
                      laptop satellite; expected offline while travelling/asleep
Mini (<tailscale-ip>): isolated lane, not a hive satellite by default.
```

The iMac and VM are **siblings reached from Studio**, not a VM→iMac chain.
Physical identity, SSH account, transport endpoint, service role, and availability
policy are separate fields. A stale Tailscale registration is not proof a host is down.

## Cloak radios (HAB-1140, probed 2026-10-23, read-only)

GL-MT3000 `ssh cloak`. Two 2.4 GHz APs, not one:

- **Guest 2G** `<guest-ssid-2g>` (`guest2g`/`ra1`, guest `<cloak-guest-subnet>`): `isolate=1`, guest zone `input=REJECT` `forward=REJECT`. Peers cannot see each other; cannot initiate into LAN or router admin (DHCP/DNS only). **No `lan → guest` forwarding** — LAN also cannot visit guest clients until that is added.
- **Personal 2G** `<lan-ssid>` (`wifi2g`/`ra0`, LAN `<cloak-lan-subnet>`): same SSID as 5 GHz, `isolate=0`, `wds=1`. Trusted LAN; do **not** enable isolate.
- Router already binds `0.0.0.0` on :22/:80/:443/:8080/:8443 (LAN-visible, guest-blocked).
- Kill-switch: wanted `9920 iif br-guest blackhole` present; `vpn_block_lan_leak` absent. Do not mutate VPN rules from this inventory.
- `tailscaled` process observed with **no** `/etc/rc.d/S80tailscale` (ghost; not killed this probe).
- Canonical operational identity remains `~/Developer/multibrain/docs/FLEET.md`; this file keeps broker/product placeholders rather than a forced byte-copy.

## Cloak egress tunnel — router chain (survey 2026-11-22, read-only)

Full-chain SSH survey: MT3000 + MT3600BE + Tailscale + Studio route tables. Read-only; no uci/firewall mutation. No keys recorded.

- **Chain:** Frontier FL `<isp-lan-subnet>` → cloak MT3000 WAN (Frontier segment) → WG `wgclient1` (`<wg-client-ip>`) → home MT3600BE `wgserver` (`<wg-server-ip>`, UDP 3478, behind the NY Verizon gateway's port-forward) → internet. All `br-lan` + `br-guest` clients egress NY; FL ISP IP never surfaces.
- **Cloak (GL-MT3000, OpenWrt 21.02/mt7981):** up 63 d; handshake live (5 s at survey), lifetime 3.25 TiB ↓ / 1.62 TiB ↑; dnsmasq `noresolv` → `<wg-server-ip>` (no DNS leak); cake on WAN.
- **Home (GL-MT3600BE):** up 159 d; wgserver peer = cloak pubkey `kvQoo…y+DE=`, allowed `<wg-client-ip>/32`.
- **Fail-closed stack verified live:** `5000/5001 iif br-lan/br-guest → table 1001` (`default dev wgclient1`), `5002/5003` blackholes below GL's `6000`; `9910` + `9920 iif br-guest` present; no orphaned `br-lan` `9920`.
- **Deco mesh** (`777mesh`/`_2g`/`_5g`) rides the Frontier segment, not the cloak — Deco SSID issues belong to the Frontier box.
- **tailscaled on cloak:** same ghost process since ≥2026-10-04 (PID 18838, service `DISABLED`, no rc.d symlink — will not survive reboot); `tailscale0` UP, registered `<cloak-host>`. Zero effect on egress — WG rides the public endpoint; no OOM posture.
- **Watchtowers (Studio):** cloak-watch + router-watchdog (+deadman) launchd jobs loaded, last exit 0; cloak-watch state `OK`, NY egress at every 5-min check through the survey window.
- **Visuals:** canonical tree only — `docs/assets/cloak-topology-2026-11-22.png` (rendered map) + admin-UI captures (`cloak-mt3000-admin`, `cloak-mt3600be-admin`, `frontier-gateway`, same date) in `~/Developer/multibrain/docs/assets/`; vault copies in SecondBrain `Attachments/`.

## Role matrix

| Capability | Studio (hub) | Book (satellite) | Fleet Node (<NODE>) |
|------------|--------------|------------------|---------------------|
| `run-nightly.sh` | documented 02:30 | documented 03:00; installed laptop job unverified | N/A (Swift services) |
| `healthcheck` + Telegram | documented hourly | documented hourly while running; installed laptop job unverified | systemd + HTTP /health endpoints |
| claude-mem capture | ✅ + worker LaunchAgent | ✅ (worker optional; CAPTURE_BROKEN flag seen historically) | N/A |
| Local Hermes extract | ✅ | ✅ if `~/.hermes` present | N/A |
| Multica extract | ✅ `:5442` | only if Multica local | N/A |
| habitat Hermes SSH | ✅ | optional | N/A |
| LadybugDB + index-server | ✅ | ❌ → health `n/a` | N/A |
| Letta + shim + bridge | ✅ | ❌ → health `n/a` | N/A |
| Qdrant knowledge-sync | ✅ `:6333` | usually ❌ | N/A |
| Weekly retro LaunchAgent | ✅ Mon 08:00 | ❌ | N/A |
| `brain` CLI | ✅ | after chezmoi alias sync + hub reachability | N/A |
| Pi Fleet MCP | via curtain | via curtain | ✅ port <PORT> |
| Pi Fleet Doorway | via curtain | via curtain | ✅ port <PORT> |
| Vault Sync Relay | via curtain | via curtain | ✅ port <PORT> |

## Full machine matrix

| Machine | Fleet role | Stores / flows | Current caveat |
|---------|------------|----------------|----------------|
| Studio | Phase-2 hub | canonical SecondBrain deposit, SwiftData hot store, `state.db`, Letta/Postgres, Ladybug, Qdrant, Multica | hub services are Python/native services, not a shipped all-Swift runtime |
| Book (`book-1`, `<tailscale-ip>`) | Phase-1 laptop satellite; opportunistic | documented local vault mirror, nightly + health + Telegram | expected offline is not a hub incident; installed jobs remain unverified while unreachable |
| Mac Mini | isolated lane | its own local state only | **not** a hive satellite unless explicitly promoted |
| habitat VM (`VirtualMac2,1`) | Hermes source (`agent-habitat`, `<tailscale-ip>`) | dashboard :9119, gateway, APNS relay and mempalace processes observed; state.db via SSH alias `habitat` | separate from physical iMac; VM lifecycle/host placement not established by guest hardware |
| iPhone | MinIO/Obsidian sync client | curated file sync/consumption | not CloudKit-shipped proof or a hub |
| iMac (physical; `iMac18,2`) | Homebridge host (`agent-habitat-home`, `<lan-ip>`) | Homebridge and child bridges observed; UI HTTP 200; colima process also observed | SSH works as `agenthabitat`; Tailscale installed but logged out; CloudKit satellite remains planned |
| Fleet Node (`<NODE>`, `<lan-ip>`) | Pi Fleet edge node (<ARCH>) | <SVC1> (MCP), <SVC2> (command log), <SVC3> (vault sync) | <ARCH> Swift 6.1; systemd services; deployed via AndromedaInstall (BIN-101) |

## Availability and registration policy (HAB-928)

- **Book:** user-confirmed mobile laptop. Offline/asleep/travelling is expected absence, not hub RED. Keep `last_success` and data age visible; stale contributions are not fresh health. Catch-up and installed job settings must be checked when Book next becomes reachable; no remote deployment is claimed here.
- **iMac:** authenticated SSH is `agenthabitat@<lan-ip>`. Tailscale is installed but returned `Logged out.` on 2026-10-07. Do not infer missing SSH from trying the wrong account. Homebridge UI returned HTTP 200; that does not verify accessories or HomeKit automations.
- **LAN identity:** router reservation `dhcp.imac_homebridge` binds observed MAC to `<lan-ip>` with DNS `agent-habitat-home.lan`. DNS was read back to .111 after dnsmasq-only reload. Backup: `/etc/config/dhcp.HAB-928.before` on cloak. The Mac's LocalHostName was already correct; the old dynamic lease advertised `agenthaitathome`, so no host rename was needed. Do not edit lease files by hand.
- **VM:** SSH alias `habitat` already resolves `admin@<tailscale-ip>`; extractor uses this alias. Guest model does not locate the virtualization host. Do not restore VM auto-boot from this inventory.

- **Book implementation boundary:** audited Studio health/Fleet Observe reads local files and local launchd only; no Book reachability probe exists there. Therefore no Studio Book-offline alert required disabling. `role=satellite` exempts hub-only Letta/Ladybug checks, **not** 24-hour capture freshness, 26-hour dead-man age, or anomaly alerts in Book's own health script. Offline tolerance is a policy target, not a shipped config switch. Inspect actual Book jobs when reachable; do not disable all stale/failure checks to simulate it.
- **Laptop scheduling:** `StartCalendarInterval` can coalesce missed sleep-time runs at wake; `StartInterval` does not replay missed sleep firings. Repo nightly has `RunAtLoad=false`; its 20-hour guard gates work but does not schedule it. Hourly health does not invoke nightly; shutdown/login catch-up and multi-day backfill are not implemented guarantees. Book-only login/awake retries require inspected plists and a separate verified rollout.
- **Studio live health roster:** `com.multibrain.health` was not loaded on 2026-10-07; `com.binarybros.secondbrain-health` was loaded with a 1800-second interval and last exit 0. The matrix's hourly entry is historical documented intent, not a live install assertion.

## GitHub identity + Vowel Sounds (HAB-1370, 2026-11-03)

Studio `gh` is **Ripnrip** only. GitHub SSH is **noeticactivity**. Private `AMORC-code/*` 404s on `gh` even when the repo exists — clone via `git@github.com:AMORC-code/<repo>.git`. Canonical ops copy remains `~/Developer/multibrain/docs/FLEET.md`.

Vowel Sounds Flutter tree: `~/Developer/vowel_sound_app_flutter` (`1.3.0+18`). iOS `com.amorcresources.rc-accord` (team `CG8DT2WPSL`). Android `com.rosc.vowel_sound_app_flutter`.

### LAN monitor delivery (HAB-928)

Swift `FleetLANHealth` source/tests/plist are retained in
`ops/monitors/fleet-lan-health/` (Multibrain operational home). Parent and independent
review each passed 16/16 checks. Signed installed binary:
`~/.local/share/fleet-lan-health/FleetLANHealth`; config in the same directory;
status `~/.local/state/fleet-lan-health/status.json`. The installed binary's scrubbed
live probe returned HTTP200 at 2026-10-07T23:35:42Z.

**Periodic monitoring is NOT active.** The supervised Hermes gateway refused
`launchctl bootstrap`; no workaround was attempted. The 300-second plist is staged
at `~/.local/share/fleet-lan-health/com.binarybros.FleetLANHealth.plist`, outside
active LaunchAgents. See the source README for the real-Terminal activation and
stop commands. `status` rejects stale/clock-skewed observations; raw old JSON is not
current health. No alerts, auto-repairs, Book probes or HomeKit functional checks.

### Tailscale cleanup: inventory only, no removals performed

Exact IDs observed in fresh local Tailscale status (not deletion approvals):

| DNS registration | Address | Node ID | Observed last seen |
|---|---|---|---|
| `agent-habitat-home` | `<tailscale-ip>` | `<node-id>` | 2026-07-23 |
| `agents-imac-5` | `<tailscale-ip>` | `<node-id>` | 2026-09-20 |
| `agents-imac` | `<tailscale-ip>` | `<node-id>` | 2026-10-05 |

**Protect:** live `agent-habitat` (`<tailscale-ip>`, `<node-id>`),
Book (`book-1`, `<tailscale-ip>`), and Mini (`<tailscale-ip>`). Older registrations
are candidates, not proven retired merely because offline. Before removal, match
exact admin-console device ID to host provenance, preview one removal, and obtain
confirmation for that target. The previous name/IP deletion list was incorrect.

## Fleet Node — systemd service policy (Example: <NODE>)

Fleet nodes running Debian/ARM64 use **systemd** (not launchd).
Deployed via AndromedaInstall Swift CLI (BIN-101), not bash scripts.

| Unit | Port | Description | Data Path |
|------|------|-------------|-----------|
| `<NODE>-mcp.service` | <PORT> | MCP server | `/var/lib/<NODE>/mcp` |
| `<NODE>-doorway.service` | <PORT> | Command log gateway | `/var/lib/<NODE>/doorway` |
| `<NODE>-vault-sync.service` | <PORT> | Vault sync relay | `/var/lib/<NODE>/vault`, `/var/lib/<NODE>/vault-sync-state` |

**Environment files:** `/etc/<NODE>/{mcp,doorway,vault-sync}.env`
**Logs:** `journalctl -u <NODE>-*` (structured JSON via swift-log)
**Health:** `curl http://localhost:<port>/health` — all return 200 OK with JSON

**Security hardening applied:**
- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectSystem=strict`
- `ProtectHome=yes`
- `ReadWritePaths` limited to service data directories
- `CapabilityBoundingSet=CAP_NET_BIND_SERVICE`
- Run as `<NODE>` user (UID 1000)

## LaunchAgent install policy

| Plist | Studio | Book |
|-------|--------|------|
| `com.multibrain.nightly` | install (02:30) | install (remap HOME, **03:00**) |
| `com.multibrain.health` | install | install (remap HOME) |
| `com.multibrain.claude-mem-worker` | install | optional |
| `com.multibrain.letta*` | install | **do not** |
| `com.multibrain.index-server` | install | **do not** |
| `com.multibrain.retro` | install | **do not** |
| `com.multibrain.dreamcatcher` | install (`--no-llm`) | optional / **do not** by default |

Repo `ops/*.plist` bake Studio absolute paths (`/Users/<user>/...`). Always rewrite `HOME` + script paths for other users.

## Config expectations

**Studio (hub)** sets: `vault_dir`, `staging_dir`, `state_db`, `claude_mem_db`, `synthesis_backend=zai` (or omit — defaults to z.ai → `--no-llm`), `graphify_nightly`, Telegram keys, optional `"role": "hub"`.

**No OpenRouter on Studio nightly (locked 2026-07-15).** Hub `run-nightly.sh` ignores `synthesis_backend=openrouter` if Ladybug + Letta runtime are present. Dreamcatcher LaunchAgent forces `--no-llm`. Letta's conversational path may still reference OpenRouter in runtime env — rotate keys as a **human Linear-only** task (never commit secrets).

**Book (satellite)** may set `synthesis_backend=openrouter` only as an explicit opt-in (historically hit HTTP 402). Prefer `zai` or `no-llm`. Add `vault_dir` pointing at Book's `~/Developer/SecondBrain/07-Sessions` so consolidate and git steps agree. Auto-detect marks Book as `satellite` when no `.lbug` / Letta runtime is present.

## Fleet Node Config Expectations (Example: <NODE>)

Fleet node services configured via `/etc/<NODE>/*.env` (deployed by AndromedaInstall):

```bash
# /etc/<NODE>/mcp.env
SWIFT_MCP_PORT=<PORT>
VAULT_RELAY_URL=http://localhost:<VAULT_SYNC_PORT>

# /etc/<NODE>/doorway.env
GYMPI_DOORWAY_PORT=<PORT>
GYMPI_DOORWAY_DATA=/var/lib/<NODE>/doorway

# /etc/<NODE>/vault-sync.env
ANIMA_VAULT_ROOT=/var/lib/<NODE>/vault
ANIMA_VAULT_SYNC_STATE=/var/lib/<NODE>/vault-sync-state
ANIMA_VAULT_SYNC_PORT=<PORT>
```

No secrets in env files — all capability resolution via Andromeda curtain.

## Known satellite issues (2026-07-14; re-verify live)

- Book nightly recently hit **OpenRouter HTTP 402** → fell back to `--no-llm` templates; health went RED and Telegram fired. Prefer killing OpenRouter on satellites too when possible.
- Book repo tip can lag Studio; pull before expecting new hub-only scripts.
- Book `ops/` templates still look like Studio — trust installed LaunchAgents under `~/Library/LaunchAgents/`, not the raw templates.

## Mini

Mac Mini stays in an **isolated lane**. Do not install the hive nightly, Letta,
Ladybug, or Qdrant there by default. Any future promotion requires an explicit
operator decision and a fresh inventory. Horizon-4 "Docker Hermes on mini" is
outdated; habitat SSH remains the documented Hermes feeder.