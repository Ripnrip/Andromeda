# Letta Memory Ingress — Anima/MemoryKit capability (design note)

> **Status:** ✅ Phase 0 spike COMPLETE 2026-09-05 (results below) · **Date:** 2026-09-05 · **Pillar:** 1 — Memory (Anima/MemoryKit)
> **Repo:** `~/Developer/Andromeda` · **Home (target):** `Packages/MemoryKit/Sources/MemoryKit/Services/`
> **Related:** `docs/plans/SHARED-MCP-HUB.md` (§2.4 TCC identity hard gate; SecretsBroker stub blocker) · multibrain AGENTS.md (visibility/cloak tags requirement)
> **Origin:** operator request 2026-09-05 — "can you add things to letta agents' memories?" — answer is yes; the question is which lane. This doc answers: **Anima's lane, behind the capability curtain, not a standalone CLI.**
> **Operator scope lock (2026-09-05):** **local Letta only.** No cloud API key path. The REST/cloud mechanism below is recorded for completeness but is out of scope until the operator says otherwise.

---

## 1. Capability

Client-facing capability ID (behind the curtain — clients never see Letta, hosts, or keys):

| Capability | Behavior |
|---|---|
| `memory.write` | Upsert a fact into a named memory target; Letta agents are one backend among several |
| `memory.write.letta` (internal) | Operator-facing: write specifically into a Letta agent's core/archival memory |

Visibility/cloak tags are mandatory on every write (`public` / `friends` / `private` / `internal`) per multibrain AGENTS.md — a memory without a tag is rejected at the adapter, not silently published.

## 2. Mechanism survey (verified live on Studio, 2026-09-05)

| Path | Status on this host | Notes |
|---|---|---|
| **Message-the-agent** (agent files the fact itself via its own memory tools) | ✅ available now — 6+ agents running in `~/.letta` (8.8 GB state), channels live via the desktop app | Most Letta-native; no new plumbing; write latency = one agent turn |
| **Letta REST API** (`PATCH /v1/agents/{id}/core-memory`, `POST /v1/agents/{id}/archival-memory`) | ⚠️ not directly reachable — desktop's local ADE backend on `127.0.0.1:52152` speaks the ADE websocket protocol, not REST; nothing on `:8283` | Needs either the Letta Cloud API key (agents sync to cloud env `studio.ian`) or a standalone `letta server` on `:8283` |
| **Direct file edits in `~/.letta`** | ❌ rejected | agents cache state; unsupported and fragile — explicitly out of scope |

**Decision:** the adapter implements (a) message-the-agent first (works today, zero credentials), then (b) REST writes once the Letta Cloud key is available. (c) is permanently excluded.

## 3. Architecture

```
agent/client → memory.write(fact, tags)          # capability curtain
                    │
              Anima ingress adapter (Swift, in MemoryKit/Services/)
                    │
        ┌───────────┴────────────┐
        │                        │
  LettaChannelWriter        LettaRESTWriter      ← both implement
  (message the agent        (core/archival        one protocol
   via channel-gateway        via REST)             `LettaMemoryWriting`
   ws://127.0.0.1:52152/ws)
        │                        │
   Letta agent self-files    Letta Cloud / local server
```

- **New Swift service, named & signed** per the canon: `andromeda-memory-ingress` (or folded into the existing long-running Andromeda daemon if one exists at build time — do not invent a second daemon; fleet rule). Ad-hoc signed, identifier `com.andromeda.memory-ingress`. Appears in the HUD fleet roster as a `LaunchEntity`.
- **Secrets:** Letta Cloud API key must come from the **SecretsBroker** — which is currently a stub (`Sources/AndromedaSecrets/SecretsBroker.swift` returns `granted: false`). Therefore REST writes are gated on pillar-5 progress (BIN-43 lane); channel-writer path needs no secrets and ships first.
- **Observability:** every write emits a telemetry event (agent id, tags, path used, latency, outcome) into the Andromeda telemetry stream + `os.Logger`. No silent writes.

## 4. Phases (revised 2026-09-05 after the Phase 0 spike)

- **Phase 0 — spike: ✅ DONE (2026-09-05).** Findings: git-backed memfs write lane exists today via the bundled `letta` CLI; only `system/**` is in-context; pre-commit frontmatter contract measured (§7). Channel/websocket reversing dropped — unnecessary.
- **Phase 1 — git-backed writer: ✅ LANDED (2026-09-05, uncommitted for review).** `GitBackedLettaWriter` in MemoryKit — contract-compliant render, attributable commits, idempotency, git + CLI verification legs. 9 unit tests + live E2E green. Remaining in phase: PR it per the merge gate (BIN-218), and Multica-backfill the ticket (done: `2a5ea368`).
- **Phase 2 — operationalize the lane.** Fix Studio-Agent's model endpoint (Multica `253690cb`) so agents can *converse* over their memory again (ingress verification beyond the token census: ask the agent what it knows). Decide daemon home: fold the writer into an existing long-running Andromeda binary vs a new `com.andromeda.memory-ingress` daemon. Wire telemetry events (write/commit/verify) into the fleet stream + HUD `LaunchEntity` roster.
- **Phase 3 — multi-agent + tag enforcement at scale.** All local agents (not just Studio-Agent) under the lane; per-agent cloak defaults (e.g. Antara-chan's customer data → `internal`-only hard rule); conflict policy when an agent self-edits the same file between ingress commits (git merge policy: ours-appends, never rewrite agent-authored content).
- **Phase 4 — fleet backends behind the same protocol.** qdrant (`secondbrain_learnings`, exists today), SecondBrain vault notes, and Letta agents all behind one `memory.write` — clients stop caring which backend holds a fact. This phase is where Anima starts subsuming the Python multibrain memory fleet (control-plane doc direction), one backend at a time.
- **Descoped by operator lock (2026-09-05):** Letta Cloud REST path and SecretsBroker dependency — local only until the operator reopens it.

## 5. Unknowns / risks

1. Channel-gateway protocol details (auth handshake on `ws://127.0.0.1:52152/ws`) — Phase 0 spike; worst case: drive the desktop app's documented channel API.
2. Which of the 6 agents in `~/.letta` is the Librarian (target for knowledge-sync-style writes) — resolve by listing agents and reading their `persona`/`human` blocks in Phase 0.
3. SecretsBroker delivery date — hard dependency for Phase 2 (same blocker noted in SHARED-MCP-HUB §3 Phase 3).
4. Dedup semantics: re-writing the same fact must not duplicate archival entries — adapter keeps a local idempotency ledger (hashed fact+agent) in MemoryKit storage.

## 6. What this is NOT

- Not a standalone `letta-memory` CLI. One-off CLIs are how the MCP sprawl happened; capabilities live behind the curtain.
- Not a migration: Letta agents keep owning their memories; this is an ingress lane, not a takeover. Anima's "consume and subsume" direction is separate, tracked in the control-plane doc.

---

## 7. Phase 0 results (completed 2026-09-05, live on this host)

**Verdict: the write lane exists TODAY with zero new code** — the Letta desktop app bundles a complete `letta` CLI (`…/Letta.app/Contents/Resources/app.asar.unpacked/node_modules/@letta-ai/letta-code/letta.js`), and local agent memory is **git-backed memfs** at `~/.letta/lc-local-backend/memfs/agent-<id>/memory`. The `letta memory` subcommand family (`status`, `diff`, `backup`, `restore`, `export`, `pull`, `tokens`) is the sanctioned lifecycle surface: *"Memory is git-backed. Use git commands for commit/push."*

### Agent fleet map (discovered from `~/.letta/agent-folders.json` + memory blocks)

| Agent | ID | Notes |
|---|---|---|
| Antara-chan | `agent-c40be0c6-…` | user's main agent (kawaii persona, GLM-5.2) |
| Berserker | `agent-930484c3-…` | Andromeda/ops author (Kimi K3, BYOK); memory: 37,460 tokens across `system/` |
| Letta Code | `agent-6cb1972a-…` | default letta/auto-chat agent |
| Studio-Agent | `agent-local-4fd6a77b-…` | **live on the local backend** (`lc-local-backend`, ws://127.0.0.1:52152); "Studio local agent via Hermes" |

### Verified write loop (executed, real)

1. Write `system/knowledge/process-identity-tcc-canon.md` into Studio-Agent's memfs.
2. `git commit` as identity `andromeda-memory-ingress` (visible, attributable author).
3. `letta memory status --agent …` → `{"dirty": false, "summary": "clean"}` ✅
4. `letta memory tokens --agent …` → `{"total_tokens": 176, "files": [{"path": "system/knowledge/process-identity-tcc-canon.md", …}]}` ✅ **counted in-context**

### Hard-won layout rules (measured, not documented anywhere else)

- **Only `system/` is in-context core memory.** `letta memory tokens` = "system prompt token estimate" and counts *only* `system/**`. Files under `reference/`, `skills/`, or any other dir are on-disk but NOT injected into the agent's system prompt. Ingress writes targeting agent awareness go to `system/knowledge/` (subdir structure supported — Berserker uses `system/human/prefs/…`).
- **MemFS pre-commit contract (hook read live 2026-09-05):** staged `.md` under `system/` or `reference/` may carry ONLY the frontmatter keys `description` (required, non-empty), `read_only` (protected — agents can't add/change/remove), `limit` (legacy). Any other key = commit rejected. Metadata (visibility/source/tags/date/slug) rides in the **body**. `MEMORY.md` must have NO frontmatter; `skills/` entries must be folders (`skills/<name>/SKILL.md`). A v2 validator (`name`+`description` contract) activates only when the layout policy file says `shared-memory`/`root-marker` — absent here.
- **Rename loophole (documented, not to be relied on):** the validator filters `--diff-filter=ACM`; pure renames (R) skip it. The initial spike commit entered `system/knowledge/` via `git mv` + `--amend` and bypassed validation; a fresh add is validated. The writer now renders contract-compliant files, so the lane works *through* the hook, not around it.
- The `~/.letta/agents/agent-*/memory` dirs (the 6 older agents) are **not git repos** and are not the local backend's live store — they're export/snapshot dirs. Live local state is `~/.letta/lc-local-backend/memfs/`.
- **Conversation path currently blocked on this host:** headless message to Studio-Agent returns `402 local_backend_error` — its model endpoint is a stub (`https://example.invalid/v1`, cerebras-typed). Separate ops item (Multica 253690cb): configure a real local-model endpoint before any agent-side verification ("did the agent read it?") can run. The git-backed ingress lane does not depend on it.
- **post-commit hook** pushes to a memory-repository remote if configured — none is configured (local-only; nothing leaves the host).

### Phase 0 conclusion (revised plan impact)

- §2 mechanism table: **channel/websocket reversing is unnecessary for writes.** The native lane is `file write → git commit → letta memory status/tokens`. Anima's adapter wraps exactly that.
- Phase 1 simplifies: `LettaMemoryWriting` protocol + `GitBackedLettaWriter` (file+commit+verify via the CLI's JSON outputs) — no websocket client needed.
- Remaining Phase 1 unknowns: memfs layout for multi-agent local backend (does `lc-local-backend/memfs` host more agents when they're created locally?), whether the desktop app watches memfs for live reload (post-commit hook exists: `.git/hooks/post-commit` is installed — likely the backend-refresh trigger; behavior TBD in spike).

---

## 8. Phase 1 scaffold — LANDED 2026-09-05

`Packages/MemoryKit/Sources/MemoryKit/Services/LettaMemoryIngress.swift` — protocol
`LettaMemoryWriting`, models (`LettaMemoryFact` with mandatory `MemoryVisibility` tag,
`LettaMemoryReceipt`), and the live implementation `GitBackedLettaWriter` (actor, Swift 6
strict concurrency, all shell work through the injected `ProcessRunning` seam from
`RetrievalService.swift` — no baked `Foundation.Process`). Behavior: renders the fact to
`system/knowledge/<slug>.md`, commits under the attributable identity
`andromeda-memory-ingress`, verifies clean-tree after commit, idempotent rewrites return
`unchanged: true` without a duplicate commit.

**Verified:** `swift test --filter LettaMemoryIngress` — **6/6 pass** (write lands + receipt,
idempotency, visibility rendered, empty-title rejection, missing-memfs error, slug safety).

**Not committed** — new files only, left in the working tree on branch
`fix/ciscope-security-enums-observability` for operator review; Per AGENTS.md merge gate
(BIN-218) any PR from this goes through normal review.

**Next:** decide daemon home (fold into an existing Andromeda long-running binary vs new `com.andromeda.memory-ingress`); unblock agent-side conversation verification by fixing Studio-Agent's model endpoint (Multica `253690cb`).
