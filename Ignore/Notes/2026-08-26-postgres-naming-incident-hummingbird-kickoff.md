# 2026-08-26 — Postgres naming incident → Hummingbird rewrite kickoff (Studio host)

Follow-up note to `docs/POSTGRES-PROCESS-NAMING-2026-08-26.md` (canonical journal lives in
multibrain; mirrored copy in Andromeda `docs/`).

## What happened
Activity Monitor wall of ~30 unnamed `postgres` processes → root-caused to Multica's Go
server pgxpool (MaxConns=25, prod-sized, pinned by daemon pollers) + PG's
backend-per-connection model + no `cluster_name`/`application_name` anywhere. Fixed live:
`cluster_name=multica-pg17`, `application_name=multica-server` on DATABASE_URL. Operator
error en route: unquoted `&` in shell-sourced `.env` silently backgrounded the assignment
→ brief crash-loop. Lesson: quote dotenv values.

## Why this pushed toward Swift/Hummingbird
The three follow-up action items (default `application_name` in pool config, env-sized
pool knobs, pool-stats telemetry) each need Go code changes + tests in a 147k-LOC
backend. In Swift they're a handful of lines in one file at the point of pool
construction — demonstrated in `multica/server-swift` (Phase 0 scaffold, same session).
Andromeda's whole stack is Swift; a Swift backend converges tooling, skills, and the
canon (Hummingbird 2.x patterns already in swift-canon references).

## Trackers
- multibrain doc (canonical): `docs/POSTGRES-PROCESS-NAMING-2026-08-26.md`
- Multica: HAB-363 (incident, done) · HAB-364 (Go follow-up, todo) · HAB-365 (Hummingbird
  rewrite program, planned) — Linear still free-limit-blocked
- Andromeda mirrors: `docs/POSTGRES-PROCESS-NAMING-2026-08-26.md` + this note
