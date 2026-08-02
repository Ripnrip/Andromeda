# Andromeda

## Workspace home

Until MemoryKit is battle-tested against live multibrain stores, day-to-day fleet + proofs stay in `~/Developer/multibrain`. This repo is the Swift product/control-plane home (dual-home OK). Don't force-move the Cursor workspace here yet.

## Capability hiding

Clients and satellite agents see `memory.*`, `infer.write`, `project.state.*` only — never Linear/Multica/n8n/provider brands. Andromeda owns selection behind the curtain.

## Project tracking

**Operator/meta-agent only.** Track via Linear ∪ Multica ∪ Slack `#projects`. Cross-link `BIN-*` ↔ `HAB-*`. See `docs/ANIMA-PROJECT-LINKS.md` (§ Routing guide — operator routing vs client capabilities). App clients use `project.state.*`.

## Claude agent habits

1. Read `ANDROMEDA-CHARTER.md` for gateway/product charter when touching Hummingbird / Autocache.
2. Prefer Swift-native patterns and strict concurrency.
3. Update docs in the same change when behavior, schema, or ops expectations change.
4. Run targeted tests before broad tests.
5. **Swift-first / No Bash surface (enforced):** Never add `.sh` / bash-shebang automation. Shell only via `config/shell-allowlist.txt`. Prefer Swift or Actions YAML. Gate: `python3 Tools/no_bash_surface_gate.py`. See `docs/NO-BASH-SURFACE.md`. Also avoid hidden launch/watchdog behavior.
6. Surface background operations through visible status plus telemetry.
