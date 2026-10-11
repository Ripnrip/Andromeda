# Proof — Memory-chain proof runner (HAB-600 / HAB-602)

**Status:** PASS (unit + curtain integration)  
**Date:** 2026-10-07  
**Tickets:** Multica HAB-600 / HAB-602 · Linear BIN-247 / BIN-197  
**ADR:** [ADR-0020](../docs/adr/ADR-0020-memory-chain-proof-state.md)

## What was proven

1. **Write owner exists** — `MemoryChainProofRunner` merges legs into
   `~/.andromeda/proofs/memory-chain.json` (sandbox-guarded). HUD stays read-only.
2. **`agent-to-agent` leg** — writer retain → different reader recall; pass on hit,
   fail on miss/error (never silent pending after an attempt).
3. **Merge preserves prior legs** — e.g. Studio `letta-ingress: pass` survives an
   agent-to-agent re-run.
4. **`ladybug-index` leg started** — `LadybugHTTPHealthProbe` records honest
   `pending` when `:8286` is unreachable; fixed probes merge cleanly. Full
   upsert/query pass still waits on Python serve surface + live hub.
5. **Curtain adapter** — `CurtainAgentToAgentSurface` drives the runner from
   `MemoryComplexityCurtain` (canonical `memory_retain` / `memory_recall`).

## Commands

```bash
swift test --filter MemoryChainProofRunnerTests
swift test --filter CurtainAgentToAgentProofTests
```

## CLI dogfood (Studio)

```bash
andromeda memory-chain prove           # agent-to-agent → ~/.andromeda/proofs/memory-chain.json
andromeda memory-chain prove --ladybug # also start ladybug-index health leg
andromeda memory-chain status          # read-only census
```

## Remaining gaps

- Live Studio write of defaultPath after a real multi-agent MCP session (dogfood via CLI above).
- Ladybug `pass` requires `/nodes`/`/edges` upsert + query on the hub serve path (Berserker lane).
- Cloak-review umbrella still gates shared-memory cutover (Letta-Chan lane).
