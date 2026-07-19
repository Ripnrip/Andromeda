# PROOF 46 — Andromeda Behind the Curtain (2026-07-19)

## Claim and evidence

| Claim | Evidence |
|-------|----------|
| Six pillars and stable client curtain are canonical | `docs/ANDROMEDA-CONTROL-PLANE.md` |
| `memory.recall/store` ship; Home/Bar journal/session dump ship; HUD parser is open | `docs/MEMORY-ONEPAGER.md`, `Features.md`, PR #10 surface |
| `infer.write` currently stores an episodic record tagged `infer-write` | canonical capability matrix; existing HUD/MemoryKit contract |
| `project.state.list/get/create/update` ships behind operator routing | `docs/ANDROMEDA-CONTROL-PLANE.md`, existing project-state proofs |
| SwiftData is the only implemented hot store | `docs/DATA-CONTRACTS.md`; `~/.multibrain/anima-hot.store` |
| Studio is hub; Book is unverified satellite; Mini is isolated | `docs/FLEET.md`, `docs/RUNBOOK.md` |
| Nightly clocks and KeepAlive services have explicit owners | control-plane schedule matrix; `docs/RUNBOOK.md` |
| SecondBrain and SwiftData are SoTs; indexes are rebuildable | control-plane store matrix; `docs/DATA-CONTRACTS.md` |
| Visibility defaults private; credential/cloak material forces internal | control-plane privacy matrix; `docs/DATA-CONTRACTS.md` |
| Graph views and indexes have distinct purposes | control-plane graph matrix |
| Letta is Python interactive Librarian, never nightly conductor | `docs/RUNBOOK.md`, control-plane Letta boundary |
| Context7 is optional and has no repo presence | scoped repository search; canonical non-prescriptive note |
| Workspace flip remains NO-GO | `docs/ANDROMEDA-WORKSPACE-READINESS.md`, PROOF 44 |

## Gaps retained honestly

- HUD lacks journal/session-dump parser parity and bypasses `VisibilityFilter`.
- Python materialized notes do not consistently emit `visibility` / `content_hash`.
- CloudKit public/friends-only egress is not proven shipped.
- `infer.write` naming does not match its current episodic-store behavior.
- Book jobs and tunnels need fresh live verification.
- Secrets broker, MCP consolidation, SkillRegistry product surface, Swift Letta
  replacement, and typed fleet mutate are not shipped.

## Re-audit criteria

1. Merge Andromeda PR #10 only after its CI gates are green; do not merge as part of this proof.
2. Land BIN-101 all-Swift installer and retain observe-versus-mutate separation.
3. Prove HUD parser and visibility enforcement, including missing=private and secret=internal.
4. Prove CloudKit/vector egress permits only public/friends.
5. Version `infer.write` semantics without breaking existing stored records/callers.
6. Re-verify Book clocks/tunnels and preserve Mini isolation.
7. Keep future Swift HTTP/WS agent runtime separate from Autocache and use current Hummingbird APIs.
8. Re-run mirror, stale-claim, link, and Mermaid checks; then require the human word before workspace flip.

Tracker cross-links: Linear BIN-102 · Multica HAB-105.
