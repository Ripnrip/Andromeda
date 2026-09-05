# Shared MCP Hub — Andromeda-hosted multiplexer (plan)

> **Status:** 📐 proposed · **Date:** 2026-09-05 · **Repo:** `~/Developer/Andromeda` (branch `fix/ciscope-security-enums-observability`; plan targets `main` via new feature branch)
> **Pillar:** 2 — MCP home · **Trackers:** Linear **BIN-41** (MCP dedupe), **HAB-64** (Multica) · new ticket IDs to be filed per phase
> **Hard requirements (locked):** Swift-only (no project bash); every spawned process has a deterministic human-readable Activity Monitor name; **every process touching a TCC-gated Apple service is a named, code-signed binary — TCC dialogs name code identity, and no rename mechanism changes that** (§2.4); no invisible launchd jobs (visible status/telemetry/ownership/controls); observe-only `MCPServerRegistry` contract respected until this ships.
>
> **Revision 2026-09-05 (evening):** incorporates empirical macOS 26 process-naming tests + TCC code-identity mandate from the operator. Changes: §1 evidence bullet 6 (live signing survey), §2.2 mechanism (argv[0]-copy theory replaced with measured behavior), new §2.4 (TCC & process identity strategy), Phase 0 S1/S4 updates, §6/§7 refresh. Original subagent draft preserved in git history of this file.
>
> **Sources cited below are files actually read in this repo on 2026-09-05.** Unknowns are marked **UNKNOWN** — nothing is guessed.

---

## 1. Problem restatement (evidence-grounded)

Every agent host spawns its own copy of identical MCP servers. Measured evidence:

- `docs/MCP-SPRAWL-PROBLEM.md` — Studio snapshot 2026-07-15: **60** `npm exec` parents; `@modelcontextprotocol/server-filesystem`, `server-memory`, `server-sequential-thinking` at **×15 each**; ~71 MB per row in Activity Monitor.
- `docs/MCP-SPRAWL-BEFORE-AFTER.md` (BIN-41) — trim pass got parents 55 → 37; honest residual: config dedupe alone does **not** drop live counts; only shared lifecycle does.
- `Plans/2026-08-26-process-guardian-daemon-sprawl-plan.md` — 2026-08-25/26 incident: ~45 cloned `node` MCP processes at ~118 MB each, `xcodebuildmcp ×6, memory ×4, sequential-thinking ×4` per session wave; 61.86 GB swap on a 32 GB machine. Its `ProcessGuardian` (R2 rule) *reaps* orphaned MCP children — that is a safety net, not a fix. This hub is the fix it explicitly defers ("Consolidating MCPs to shared network services … separate workstream").
- `docs/POSTGRES-PROCESS-NAMING-2026-08-26.md` — the naming convention precedent: deterministic naming at spawn time so unidentifiable process walls become attributable. (That doc's argv[0] observation holds for *native* binaries; interpreted-runtime behavior on macOS 26 was measured differently on 2026-09-05 — see §2.2.) This plan applies the same convention to MCP.
- Current registry: `Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerRegistry.swift` — **observe-only** (`MCPProcessEnumerating` contract: "Never kill, signal, or unload processes"), seeds from the host inventory, groups duplicates. `docs/ANDROMEDA-CONTROL-PLANE.md` row 2: "shared lifecycle / dedupe host **not shipped**". This plan is that missing piece.
- **2026-09-05 live signing survey (this host):** `~/.local/bin/andromeda-mcp` is ad-hoc signed (`Identifier=andromeda-mcp`, flags=adhoc) — the in-repo precedent. `~/.local/bin/mempalace-mcp` and `~/.local/bin/qdrant-mcp-server` are **"code object is not signed at all"** — if either ever requests a TCC-gated service, the dialog names the interpreter and the grant is unattributable. Hub spawn policy (§2.4) closes this.
- **2026-09-05 empirical naming tests (macOS 26.6.2, arm64):** (a) exec through a symlink → Activity Monitor/`ps comm` shows the **resolved binary path**, never the symlink name — the draft's "binary copy/symlink" mechanism is dead; (b) `sysctlbyname("kern.procname", …)` on self returned rc=0 but `ps comm` unchanged — dead; (c) node `process.title="…"` **works** — `ps comm` shows the custom title — proven with a live child; (d) `setproctitle` python package not installed (untested, expected to work like node); (e) **TCC dialog name is the code identity of the requesting process — none of the above renames affect it** (§2.4).

### Live config inventory (re-verified 2026-09-05, this host)

| Host | File | Live keys observed |
|---|---|---|
| Claude Code | `~/.claude.json` `mcpServers` | `browsermcp, filesystem, memory, openaiDeveloperDocs, sequentialthinking, pageindex-local, qdrant, multica, linear, career-ops` |
| Claude Code | `~/.claude/.mcp.json` | `cerebras-mcp` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `quake-coding-arena, XcodeBuildMCP, obsidian-mcp-tools` |
| Cursor | `~/.cursor/mcp.json` | `claude-mem` (**only** — config has drifted since the 16-key inventory in `MCP-SPRAWL-PROBLEM.md` §4.1; re-inventory is Phase 0 work) |
| Codex | `~/.codex/config.toml` `[mcp_servers.*]` | `chrome-devtools, openaiDeveloperDocs, firecrawl, playwright, node_repl, browsermcp, filesystem, memory, pageindex-local, sequentialthinking, stitch, cerebras-mcp, qdrant, computer-use, multica, linear, cua_repl` |
| Hermes local | `~/.hermes/config.yaml` `mcp_servers:` | `higgsfield (url), agent-zero (url), gbrain (url), mempalace (command: /Users/admin/.local/bin/mempalace-mcp), obsidian (url)` — both `command:` and `url:` forms exist; `inherit_mcp_toolsets: true` at line 469 |
| Hermes habitat (Tart VM) | `~/.hermes` on `agent-habitat.local` | 6 `mcp_servers` + 1 URL (per `MCP-SPRAWL-PROBLEM.md` §4; re-verify over SSH in Phase 0) |

Local stdio MCP binaries already on disk (relevant to MVP selection): `~/.local/bin/andromeda-mcp` (Swift, 267 KB), `~/.local/bin/mempalace-mcp` (uv tool), `~/.local/bin/qdrant-mcp-server` (uv tool), `~/.local/bin/mcp-server-qdrant` (uv tool), `~/.local/bin/cerebras-mcp` (node symlink), `~/.local/bin/qdrant-mcp-reaper` (Swift, 86 KB — prior art for Swift-built MCP tooling).

---

## 2. Architecture

### 2.1 Topology

```
 agent A (Hermes)          agent B (Claude Code)      agent C (Codex/ChatGPT)
   └─ andromeda-mcp-filesystem  └─ andromeda-mcp-filesystem  └─ andromeda-mcp-filesystem
   └─ andromeda-mcp-memory      └─ andromeda-mcp-memory      └─ andromeda-mcp-memory
          │ stdio (JSON-RPC line-delimited, standard MCP client→server)      │
          └──────────────┬───────────────────────────────┬───────────────────┘
                           unix domain sockets at
                     ~/.andromeda/mcp-hub/sockets/*.sock
                                 │
                    andromeda-mcp-hub  (one long-running Swift process,
                    launchd com.andromeda.mcp-hub, KeepAlive=true)
                     ├─ upstream supervisor actor ── spawns/owns:
                     │    andromeda-mcpd-filesystem  (node, launcher-named)
                     │    andromeda-mcpd-memory      (node, launcher-named)
                     │    … one per shared server, stdio pipes
                     ├─ registry bridge: feeds live state into MemoryKit
                     │    MCPServerRegistry (upgrading it from observe to
                     │    "host" mode — its first lifecycle-owning consumer)
                     └─ telemetry: os_log + ~/.andromeda/logs/mcp-hub.jsonl
```

Key decisions:

1. **One hub process, not one per server.** Matches the task brief and the charter pillar ("MCP home — host/consolidate MCP servers, no sprawl"). A single hub keeps fleet surface to exactly **one** new LaunchAgent (`com.andromeda.mcp-hub`) and one shim binary design, and makes cross-server policy (secrets injection, naming, restart budget) centralized.
2. **Shims are real per-agent processes, one per (agent session × server).** MCP-over-stdio clients (Claude Code/Desktop, Cursor, Codex, Hermes `command:` form) expect a child process they can spawn, write JSON-RPC to stdin, and read from stdout. A unix-socket-only design would not be configurable in most of these hosts today. The shim is tiny (pure Foundation, like `Packages/AndromedaMCP/Sources/AndromedaMCP/AndromedaMCP.swift` — 204 lines for a full MCP stdio server proves the weight class): it bridges its own stdio ↔ hub socket. Its cost is ~1–3 MB Swift binary, versus ~71 MB `npm exec` duplicate today.
3. **Shim ↔ hub transport: unix domain socket, one per shim instance** (`~/.andromeda/mcp-hub/sockets/<server>.<shim-pid>.sock`). Framing is line-delimited JSON-RPC end-to-end (no re-encoding); the hub demuxes by connection, not by parsing message ids, so protocol pass-through is faithful (notifications, `id: null` semantics, batching behavior all preserved — `AndromedaMCP.swift`'s dispatch already demonstrates the required header/id discipline).
4. **Upstream spawn: no `npm exec` at runtime.** The hub resolves each server's real entrypoint once (e.g. `node ~/.npm/…/server-filesystem/dist/index.js` or the uv tool binary at `~/.local/bin/…`) from a hub config file, and spawns the resolved executable directly. This kills the `npm exec` parent blob (the 71 MB rows in the screenshot) and gives full argv control.
5. **Where the code lives (new targets, existing packages):**
   - `Sources/AndromedaMCPHub/` (new library) + shim target `andromeda-mcp-shim` — sibling to `Sources/AndromedaHostOps/` (which already hosts fleet-side ops like `PowerLeaseCoordinator.swift`; note `ProcessGuardian.swift` from the guardian plan is *not* on this branch yet — it lands on `feat/process-guardian`).
   - `andromeda mcp-hub …` CLI subcommands in `Sources/AndromedaCLI/Andromeda.swift` (pattern: PR #45's testflight subcommand per the guardian plan; ArgumentParser already a dependency of the CLI target in `Package.swift`).
   - Hub config: `~/.andromeda/mcp-hub/servers.json` (typed `MCPServerEntity`-compatible schema — *new schema, needs ADR per repo rule*; source-consistent with `Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerEntity.swift` fields: `id`, `packageName`, `command`, `duplicateGroup`, `source`).
   - MemoryKit gains a `MCPHubClient`/host-mode extension — **the registry's observe-only contract is respected**: the hub publishes state *into* the registry; the registry itself still never kills (see §7 risks for why this boundary matters).
   - Swift 6 strict concurrency: supervisor state in actors; `Process` handles behind protocols for tests (mirrors `ProcessGuardian`'s `ProcessKiller` protocol-injection testing approach).

### 2.2 Activity Monitor naming (HARD REQUIREMENT)

Convention (extends `POSTGRES-PROCESS-NAMING-2026-08-26.md` to MCP):

| Process | Spawn mechanism | Visible Name | Parent |
|---|---|---|---|
| Hub daemon | real Swift binary `andromeda-mcp-hub`, ad-hoc signed, `com.andromeda.mcp-hub` | `andromeda-mcp-hub` | launchd (`com.andromeda.mcp-hub`) |
| Upstream server `<s>` | per-server **launcher file** `~/.andromeda/mcp-hub/launchers/andromeda-mcpd-<s>.{js,py}` (node/python) or a real Swift binary | `andromeda-mcpd-<s>` | hub |
| Agent shim for `<s>` | per-name **byte-copies** of the one shim binary (`andromeda-mcp-filesystem`, `andromeda-mcp-memory`, …) | `andromeda-mcp-<s>` | the agent host process |

Mechanism notes — all verified 2026-09-05 on macOS 26.6.2 unless marked:

1. **Symlink copies do NOT work** — `ps comm`/Activity Monitor shows the *resolved* binary path, never the symlink name. **Byte-copies do**: identical content → identical ad-hoc cdhash across all shim copies, so TCC grants stay stable across the set and rebuilds only invalidate when the shim code changes.
2. **node upstreams:** launcher file sets `process.title = "andromeda-mcpd-<s>"` before importing the real server entrypoint. Proven: `ps comm` shows the custom title for a live node child. The launcher is a *named file on disk owned by hub config* — auditable, unlike the anonymous `node -e` eval blobs this project bans (ChatGPT's claude-mem loaders are the counter-example that motivated this rule).
3. **python upstreams:** launcher file installs/uses `setproctitle` then runs the real entrypoint. **Partially verified** — package absent on this host today; Phase 0 spike S1 confirms before Phase 1 depends on it. If setproctitle fails on macOS 26, python upstreams keep their interpreter name in AM (full command line still attributes them) and the *strategic* fix applies: replace python MCP servers with Swift ones (`Packages/AndromedaMCP/` proves a full MCP stdio server is ~204 lines of Swift; `~/.local/bin/qdrant-mcp-reaper` is prior art).
4. **Swift upstreams** (andromeda-mcp today; more over time): name IS the binary. Nothing to do.
5. `-d` suffix distinguishes daemon (shared, hub-owned) from shim (per-agent). Deterministic, greppable, self-sorting in Activity Monitor: one block per role. Titles carry instance detail where useful: `andromeda-mcpd-filesystem (dirs=2)` pattern from the Postgres doc's triage runbook.
6. **Naming ≠ TCC identity.** Everything above governs Activity Monitor/`ps` display only. See §2.4.

### 2.3 Repointing existing agents

All changes are config-only; each host keeps a rollback stanza. Hub listens nowhere on TCP by default (local sockets only) — no new port surface.

| Host | Mechanism | Example after cutover |
|---|---|---|
| Hermes (`~/.hermes/config.yaml`) | `mcp_servers.<key>.command:` form (already used by `mempalace` at line 858–859) | `command: /Users/admin/.local/bin/andromeda-mcp-filesystem` with `args:` for allowed dirs |
| Claude Code (`~/.claude.json`, `~/.claude/.mcp.json`) | `mcpServers` command/args | same binary path per key |
| Claude Desktop (`claude_desktop_config.json`) | `mcpServers` command/args | same; **UNKNOWN:** config reload requires app restart (assume restart, verify in Phase 2) |
| Cursor (`~/.cursor/mcp.json`) | `mcpServers` command/args | same |
| Codex (`~/.codex/config.toml`) | `[mcp_servers.<key>]` `command = …` | same |
| ChatGPT desktop / codex app | **UNKNOWN** — config surface not verified in repo docs or this host's dotfiles; Phase 0 must locate it before its cutover step |
| Hermes habitat VM (`agent-habitat.local`) | stdio command form over SSH-not-needed: shim path must exist *inside* the VM — **UNKNOWN:** whether the Tart VM shares the host filesystem for binary paths; if not, hub gains a TCP/localhost listener *inside* the VM lane only (flagged, gated decision, default off) |

Server-specific notes:
- **filesystem**: each agent config currently passes its own allowed-dir list. With one shared process, allowed dirs become the **union** managed in hub config. Per-agent restriction loss is a real semantic change — documented, accepted (dirs are all under `/Users/admin` anyway), and re-checkable via `andromeda mcp-hub status`.
- **Secrets-bearing servers** (`firecrawl` needs `FIRECRAWL_API_KEY`, `cerebras-mcp` needs env): hub injects env at spawn time from its own environment/Keychain. **BLOCKER (known):** `Sources/AndromedaSecrets/SecretsBroker.swift` is a stub returning `granted: false` (per `references/andromeda-state.md` and skill pitfall list). MVP scope avoids this by choosing servers without secrets (§3); secrets-bearing servers join the hub only after the broker lands (charter rule: "No raw keys in client env" — hub env injection is the *host* side and is allowed, but should route via the broker once real).
- **Stateful/per-session servers** (`browsermcp`, `playwright`, `chrome-devtools`, `sequential-thinking`): **UNKNOWN / likely NOT shareable** — they keep per-session UI state or scratch state. Hub supports three placement modes per server: `shared` (one upstream, everyone), `pooled` (N upstreams, shim gets one by lease), `passthrough` (shim spawns the legacy command itself, hub only observes/names it). Cutover only moves servers classified `shared`; classification table is a Phase 0 deliverable. This directly answers "which of the 50+ actually consolidate."

### 2.4 TCC & process identity strategy (HARD REQUIREMENT — operator mandate 2026-09-05)

**Fact (measured, not assumed):** macOS TCC dialogs name the *code identity* of the
requesting process — the executable filename/signature, or its responsible
process. No display-name mechanism changes it: symlink-exec shows the resolved
path, `sysctl kern.procname` is a no-op on macOS 26, node `process.title`
changes `ps` only. Corollary: an unnamed interpreter can hold a personal-data
grant that System Settings shows as "Python" — unattributable and
indistinguishable from malware. That is the exact failure this project bans.

**Policy — every hub-spawned artifact follows it:**

1. **Swift binaries** (hub, shims, Swift upstreams): real filenames, ad-hoc
   signed minimum with stable reverse-DNS identifiers (`com.andromeda.mcp-hub`,
   `com.andromeda.mcp-shim`). Production lane upgrades to Developer ID /
   notarization later — ad-hoc means rebuild ⇒ new cdhash ⇒ re-grant, which is
   acceptable for dev, documented in the runbook, and surfaced by
   `andromeda mcp-hub status` (signing-freshness column).
2. **node/python upstreams:** Activity Monitor naming via launcher files
   (§2.2). **TCC limitation, stated plainly:** if a node/python upstream ever
   touches a TCC-gated Apple framework, the dialog will name the interpreter.
   Therefore: *no TCC-gated capability may be added to a node/python upstream.*
   TCC-gated MCP tools (macOS control, Reminders/Calendar/Contacts/FindMy
   access, screen recording) are **Swift-binary-only** in this architecture —
   either native Swift MCP servers (AndromedaMCP pattern) or not at all.
3. **Inventory & migration (Phase 0, S4):** read
   `~/Library/Application Support/com.apple.TCC/TCC.db` from a context with
   Full Disk Access (direct read is `authorization denied` from a normal
   shell — verified 2026-09-05). Produce the table: which clients currently
   hold which grants (`kTCCServiceReminders`, `Calendar`, `AddressBook`,
   `ScreenCapture`, …). Any grant held by an unsigned/unnamed interpreter is
   flagged for migration: `tccutil reset <service> <bundle-or-path>` then
   re-grant against the named binary. Today-known offenders to check:
   `~/.local/bin/mempalace-mcp`, `~/.local/bin/qdrant-mcp-server` (both
   unsigned per 2026-09-05 survey); the Hermes venv pythons; ChatGPT's
   anonymous eval loaders (out of scope to fix — signed third-party app —
   but listed so their grants are visible).
4. **Reference implementation:** `~/Developer/HermesIdentity` — a named,
   ad-hoc-signed Swift binary (`com.binarybros.HermesIdentity`) with
   `whoami` + `probe-reminders`/`probe-calendar` commands that demonstrate
   the end state: a permission grant attributable by name. Its
   Reminders access returned GRANTED on 2026-09-05.
5. **Guardian interplay:** ProcessGuardian R2 reaping keys on names/argv —
   deterministic hub naming (this section) is what makes an exact whitelist
   possible, which Phase 3 relies on.

---

## 3. Phases

### Phase 0 — Inventory & spikes (no product code beyond probes)
1. Re-run the §1 inventory (config drift is real: Cursor went 16 keys → 1 since July). Refresh `MCPServerRegistry.catalogSeeds()` from the new scan; record deltas in `docs/MCP-SPRAWL-BEFORE-AFTER.md` per its runbook.
2. **Spike S1 (partially pre-answered 2026-09-05):** process naming on macOS 26 — symlink-exec ✗ (resolved path shown), sysctl `kern.procname` ✗ (no-op), node `process.title` ✓ (proven live). Remaining to confirm: python `setproctitle` on macOS 26, and byte-copied shim binaries preserving a single ad-hoc cdhash. Spike shrinks from "unknown mechanism" to "one package install + one codesign check".
3. **Spike S2:** hub↔shim socket framing: verify faithful pass-through of MCP `initialize`/`notifications/initialized`/`tools/list`/`tools/call` against one real client (Claude Code) and one real upstream (`@modelcontextprotocol/server-filesystem`).
4. **Spike S3:** per-session state classification: empirically determine `shared`/`pooled`/`passthrough` per server in the inventory (drive each with two concurrent stdio clients against one upstream; watch for state bleed).
5. ADR: hub config schema (`~/.andromeda/mcp-hub/servers.json`), socket dir layout, naming convention. Repo rule: no silent schema changes.
6. File Linear tickets (BIN-*): naming spike, hub core, shim, cutover waves, decommission. Cross-link HAB-* per `docs/ANIMA-PROJECT-LINKS.md` routing guide.
7. **Spike S4 (TCC inventory):** with Full Disk Access granted to the survey context, read `TCC.db` and produce the grant-holder table per §2.4(3). Classify every current holder: named-signed ✓ / named-unsigned ⚠ / unnamed interpreter ✗ (migration candidate). Output feeds the Phase 2+ cutover checklist.
8. **Deliverable:** `docs/plans/SHARED-MCP-HUB-INVENTORY.md` (or extension of the before/after doc) with the classification table.

### Phase 1 — MVP: hub + filesystem + one memory store
Scope deliberately avoids secrets (broker blocker) and per-session-state servers (spike S3 risk).

- **Servers:** `@modelcontextprotocol/server-filesystem` and **one** memory store.
  - Memory store candidates: `mempalace-mcp` (already a local named uv binary at `~/.local/bin/mempalace-mcp`; already in Hermes config) vs `@modelcontextprotocol/server-memory` (the ×15 offender; node). **Decision deferred to Phase 0 spike S3 + operator call.** Flag: `server-memory` is stateful via `MEMORY_FILE_PATH`; sharing one process makes memory *actually shared across agents* — which matches the Anima direction (agents already share memory stores via Letta/Qdrant per multibrain AGENTS.md), but the visibility/cloak tagging rules from multibrain AGENTS.md must be reviewed before flipping (private-vs-shared semantics).
- Build: `AndromedaMCPHub` library (supervisor actor, upstream `Process` ownership, socket accept loop, JSON-RPC pipe relay), `andromeda-mcp-shim` executable (server chosen by the binary's own filename — per-name byte-copies per §2.2, or a `--server` arg for the single-binary dev build), `andromeda mcp-hub {status,validate,install}` CLI, `ops/com.andromeda.mcp-hub.plist` (KeepAlive=true, RunAtLoad, stdout/stderr to `~/.andromeda/logs/`, modeled exactly on `ops/com.andromeda.hud.plist` — including its "exec the binary directly, never `/usr/bin/open -a`" rule).
- Install via typed Swift installer only (BIN-101 law — no launchctl-by-hand; the hud plist header documents the install contract the Swift installer must keep).
- Tests (canon: fixtures + protocol injection, no real process kills): supervisor restart policy fixtures, shim relay round-trip with mock hub, naming spawn unit tests asserting argv vectors, config schema validation. Follow the guardian plan's testing discipline (`ProcessKiller`-style protocol injection).
- Acceptance: two concurrent Claude Code sessions both talk to **one** `andromeda-mcpd-filesystem` and **one** memory upstream; Activity Monitor shows exactly the named roster; `andromeda mcp-hub status` shows upstream + shim census; telemetry JSONL emits spawn/exit/dedupe events (schema consistent with `MCPServerRegistry` telemetry in `Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerRegistry.swift` lines 365–380).

### Phase 2 — Cutover wave 1 (agent hosts)
Order chosen by blast radius:
1. **Hermes local** (`~/.hermes/config.yaml`) — `command:` form native; repoint `filesystem`/`memory` equivalent keys; verify `inherit_mcp_toolsets: true` (line 469) doesn't re-import stale definitions from parent sessions — **UNKNOWN, verify in this phase**.
2. **Claude Code** (`~/.claude.json` + `~/.claude/.mcp.json`) — repoint `filesystem`, `memory`; keep `career-ops`, `multica`, `linear` untouched (not in MVP).
3. **Claude Desktop** — repoint after app-restart reload verified.
4. **Codex** (`~/.codex/config.toml`) — repoint the same two keys.
5. **Cursor** — deferred pending Phase 0 re-inventory (its config changed shape).

Each step: before/after process counts recorded into `docs/MCP-SPRAWL-BEFORE-AFTER.md` (its "Commands used" section is the template), comment BIN-41 with integers only per `docs/MCP-SPRAWL-OPS.md` §5. Rollback = restore prior config stanza (kept commented beside the new one until wave 2).

### Phase 3 — Expand roster + secrets path
- Add `sequential-thinking` if spike S3 says `shared`/`pooled` is safe; add `qdrant-mcp-server` (uv binary, already named); add uv-hosted memory/qdrant consolidation.
- Secrets-bearing servers (`firecrawl`, `cerebras-mcp`) join **only after** `SecretsBroker` stops being a stub (extend `Sources/AndromedaSecrets/SecretsBroker.swift` to Keychain first — skill pitfall, do not assume auth exists). Hub then becomes the env-injection point per the host-held-auth wrapper recipe in `references/andromeda-mcp-pattern.md` (literal-wrapper option): client configs contain only the shim path, tokens never appear in any agent config again.
- Guardian integration: once the trio no longer spawns per-session, relax `ProcessGuardian` R2 (orphaned MCP reaping) to the residual `passthrough` set only — the two systems must not fight (guardian kills what hub owns = incident class; coordination via the hub's pid/argv namespace is deterministic, but the R2 matcher whitelist must be updated in the same PR that flips each host).

### Phase 4 — Decommission
- Remove the trio (`filesystem`/`memory`/`sequential-thinking` `npm exec` entries) from every host config that was repointed; delete `multica` dead entry per the andromeda-mcp-ops skill's rewiring note (it "only ever booted OMC's ast-grep bridge"); remove the 75 MB `~/.claude/plugins/marketplaces/omc` clone.
- Target end state recorded in before/after doc: `npm exec` parents ≈ count of `passthrough`-classified servers only (est. 60 → single digits; honest number set by Phase 0 classification, not promised here).
- Guardian R2 residual scope, hub decommission runbook (`andromeda mcp-hub uninstall`: bootout + socket cleanup + config archival to `legacy/` per repo rule), fleet `LaunchEntity` registration so the hub appears in the HUD roster (`Sources/AndromedaHUDCore/FleetConstellationView.swift` surface).

---

## 4. Failure isolation & crash-restart semantics

1. **Upstream crash:** supervisor actor detects EOF/exit on the upstream pipe → marks server `degraded` → restarts with exponential backoff (1s → 2s → 5s → 30s cap, jittered; one restart budget per 60s window per server — no restart storms). In-flight shim requests to that server get a JSON-RPC error response (`-32000` server-restarting, message names the server) rather than a hang; shims stay alive and retry the connection.
2. **Hub crash:** launchd `KeepAlive=true` restarts it. All upstreams restart with it (cold start ~seconds; node servers are the slowest — budget measured in Phase 1). Shims get socket EOF → exit non-zero with a clear stderr line; agent MCP clients (Claude Code, Hermes) already restart failed stdio servers, which respawns the shim. **UNKNOWN:** each host client's exact stdio-retry behavior — spike S2 verifies; worst case is a manual agent-session reconnect, which is today's failure mode anyway.
3. **Shim crash/leak:** shim death closes its socket; hub reaps the fd and logs. A shim orphaned by a killed agent (ppid 1) is *named* (`andromeda-mcp-<server>`), so both Activity Monitor and the existing guardian R2 rule can see it — but with the hub, orphan reaping becomes the exception path, not the steady state.
4. **One bad server never kills the hub:** each upstream is a separate `Process` with its own pipes and its own actor-isolated state; a wedged upstream is SIGTERM→SIGKILL'ed by the supervisor after a `ping` timeout (MCP `ping` handling already implemented in `Packages/AndromedaMCP/Sources/AndromedaMCP/AndromedaMCP.swift` lines 52–58 is the reference semantics) while other servers keep serving.
5. **Runaway memory:** supervisor samples upstream RSS; a server exceeding its configured RSS ceiling (e.g. 3× Phase-1 baseline) is restarted and the event emitted to telemetry + os_log. This is the hub-side answer to the 118 MB node clones.
6. **Idempotency & bounded retries** per repo engineering rules; every restart/circuit-breaker event lands in `~/.andromeda/logs/mcp-hub.jsonl` with server name, reason, pid — the observability law (visible status, telemetry, ownership, controls) applied to the hub itself.

---

## 5. What this plan deliberately does NOT do

- Does not make `MCPServerRegistry` kill anything. The registry stays observe/scan; the hub is a new lifecycle owner that *publishes* into it. (Skill pitfall: "Do not add lifecycle control without explicit design" — this document is that explicit design, but the code boundary remains hub-owns, registry-reports.)
- Does not replace `ProcessGuardian` (HAB-369/370) — guardian handles SourceControl daemons and non-hub MCP orphans; §3 Phase 3 coordinates the R2 overlap.
- Does not touch the AndromedaMCP ast-grep server (`Packages/AndromedaMCP/`) beyond reusing it as the weight-class proof for shim size; its settings rewiring (andromeda-mcp-ops skill) proceeds independently.
- No TCP listener, no remote agents, no Habitat-VM bridging in v1 (§2.3 table — gated, default off).
- No bash install scripts. Swift installer only, per AGENTS.md hard rule and the hud plist's documented contract.

---

## 6. Open questions (explicit UNKNOWNs)

1. Activity Monitor naming for python upstreams — setproctitle on macOS 26 unconfirmed (package absent on host today); node path proven, symlink/sysctl paths disproven (§2.2, spike S1).
2. Claude Desktop / ChatGPT-desktop config reload behavior and ChatGPT's MCP config surface — locate + verify in Phase 0.
3. `shared`/`pooled`/`passthrough` classification per server — spike S3; decides the real decommission number.
4. Shared-memory semantics: which memory store, and visibility/cloak review per multibrain rules before agents share one memory process.
5. Hermes `inherit_mcp_toolsets: true` interaction with repointed stdio servers.
6. Habitat VM binary/filesystem sharing for shims.
7. Each agent host's stdio-MCP reconnect behavior on shim crash.
8. uv tool self-update vs renamed spawn paths — moot for hub-owned spawns (hub resolves real entrypoints itself, §2.1 key decision 4); retained for `passthrough` servers only.
9. SecretsBroker dependency for secrets-bearing servers (known blocker, not an unknown — listed to keep it on the critical path).
10. Full inventory of TCC grants currently held by unnamed interpreters — blocked on Full Disk Access for the survey context (§2.4(3), spike S4).

---

## 7. Top risks

1. **Per-session state servers don't consolidate** (browsermcp/playwright/chrome-devtools/sequential-thinking) → hub's value caps at the stateless trio + uv binaries; Activity Monitor improves a lot, 50+ → maybe 20. Mitigation: honest Phase 0 classification; `pooled` mode recovers part of it.
2. **Python-upstream naming fails** (setproctitle broken/absent) → python servers stay interpreter-named in AM; full command line still attributes them, and the strategic fix (Swift MCP replacements, §2.2 note 3) applies sooner. Spike S1 bounds this before Phase 1.
3. **TCC identity regression via the hub** — worst case is a hub-spawned process *worse* than today's sprawl: an unsigned python holding a Reminders grant behind a friendly name. Mitigation: §2.4 is a hard gate — TCC-gated capabilities are Swift-binary-only; S4 inventories existing grants before cutover; `andromeda mcp-hub status` reports signing freshness standing.
4. **Shared memory store changes agent isolation semantics** — a private memory leaking across agents would be worse than sprawl. Mitigation: memory-store choice is a gated operator decision with cloak review; filesystem MVP carries no such risk.
5. **SecretsBroker stays a stub** → secrets-bearing servers can't join; hub scope shrinks. Mitigation: MVP avoids them; track the broker work as a dependency on the pillar-5 lane (BIN-43 per control-plane doc).
6. **Guardian/hub fight** during transition (R2 reaps hub-owned named processes if matcher keys on `node` argv). Mitigation: same-PR matcher updates per §3 Phase 3; deterministic naming makes the whitelist exact.
7. **Config drift recurrence** — hosts gained/lost keys in 7 weeks without any SoT noticing. Mitigation: hub's `andromeda mcp-hub status` + registry scan become the standing inventory; drift alarm telemetry.
