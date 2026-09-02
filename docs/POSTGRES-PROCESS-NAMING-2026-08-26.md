> **Mirror** of `multibrain/docs/POSTGRES-PROCESS-NAMING-2026-08-26.md` (canonical). Andromeda session note: `Ignore/Notes/2026-08-26-postgres-naming-incident-hummingbird-kickoff.md`

# Postgres Process Naming — Incident & Convention (2026-08-26)

> Same genre as [MCP-SPRAWL-PROBLEM.md](MCP-SPRAWL-PROBLEM.md): Activity Monitor full of
> unidentified processes. Third time this class of confusion has cost an investigation
> cycle — hence a written convention, not just a fix.
>
> Trackers: **HAB-363** (incident, done) · **HAB-364** (follow-up: code default, todo).
> Linear blocked: binary-bros workspace exceeded its **free issue limit** — ready-to-paste
> issue text preserved in [Appendix A](#appendix-a--pending-linear-issues). File when
> capacity frees (archive completed issues or upgrade).

## The incident

**00:30, Studio host.** Activity Monitor showed ~30 `postgres` processes (~11.5 MB each).
No way to tell what they served. Suspected a connection leak from an unknown app.

### What it actually was

| Piece | Finding |
|---|---|
| Owner | Multica stack (`com.multica.stack` → `multica-stack.sh` → `server/bin/server`, PID 48529) |
| Connections | 25 idle `postgres: multica multica ::1(…) idle` backends — one pgxpool, `MaxConns=25` |
| Why 25 | `server/cmd/server/dbstats.go` prod-sized default (~3800 acquires/s observed in prod); host env sets no override. Daemon claim/heartbeat pollers pin the pool at its ceiling (~18 acquires/s at 00:44 with zero human traffic) |
| Why it *looked* scary | Postgres spawns **one OS process per connection**; 25 conns + 5 background workers + 1 postmaster = a wall of identical `postgres` rows |
| Why it was *unidentifiable* | `cluster_name` empty; no connection set `application_name` (`pg_stat_activity.application_name` was blank); Activity Monitor's Name column shows only argv[0] = "postgres" |

## The fix (shipped same session, verified)

1. **`ALTER SYSTEM SET cluster_name = 'multica-pg17'`** on the Homebrew `postgresql@17`
   instance (`:5442`) + `brew services restart postgresql@17`.
   → Every PG process now self-identifies:
   `postgres: multica-pg17: multica multica ::1(60356) idle`, `postgres: multica-pg17: checkpointer`, …
2. **`application_name=multica-server`** appended to `DATABASE_URL` in `~/Developer/multica/.env`
   (quoted!). → `pg_stat_activity` shows `application_name = multica-server` on all 25 conns.
   Note: PG 17 process titles carry cluster/user/db/state but **not** application_name —
   the app name lives in `pg_stat_activity`, which is the real diagnostic surface.
3. Stack restarted (`launchctl kickstart -k gui/501/com.multica.stack`), `/health` → `{"status":"ok"}`.

### Operator error logged (the lesson that earns its keep)

First `.env` edit left the URL value **unquoted**. The stack script sources `.env` with
`set -a; . ./.env`, so bash split the line at `&`: the `DATABASE_URL=…disable` assignment
ran inside a *background subshell* (lost), and the server fell back to a default URL on
**:5432** → crash-loop until KeepAlive caught up. Caught within ~90s, fixed by quoting.

**Rule: in any shell-sourced dotenv, quote every value containing `& ? space`.**
Consider a `dotenv`-validator assertion in `multica-stack.sh` (see plan).

## Convention (hive-wide)

1. **Every Postgres instance on a hive host gets `cluster_name = <app>-pg<major>`.**
   - Studio host today: `multica-pg17` (:5442). If the stopped stash-box `postgresql@14`
     (:5432) is ever revived, set `stash-pg14` — owner's call, do not touch while stopped.
2. **Every client connection string sets `application_name`** (URL param or pgx
   `RuntimeParams`). Pattern: `<app>-<role>` — `multica-server`, `multica-sampler`, `multica-migrate`.
3. New service onboarding checklist gains: "named cluster + named connections".

## Triage runbook: "wall of postgres processes"

```bash
# 1. Read the process titles (cluster, user, db, client, state — post-fix these are self-identifying)
ps aux | grep "[p]ostgres:"

# 2. Who is each connection? (application_name, state, age)
psql -h localhost -p 5442 -U admin -d postgres -c \
  "SELECT application_name, usename, datname, state, count(*) FROM pg_stat_activity GROUP BY 1,2,3,4;"

# 3. Which local PID owns the client side of a connection?
lsof -nP -iTCP:5442 -sTCP:ESTABLISHED | awk '{print $1, $2}' | sort | uniq -c

# 4. In Activity Monitor: View → Columns → Command shows the full title.
#    The Name column will always say just "postgres" (argv[0]) — that's macOS, not a bug.
```

Remember: idle backends are cheap (backend-per-connection is Postgres's design; much of
the 11 MB is shared memory). The question is never "why so many processes" — it's
"whose are they, and is the pool pinned at max". `server` logs `db pool stats` /
`db pool pressure` every 15s in `/tmp/multica-stack.err` for the second half of that question.

## Prevention plan (so this doesn't happen again)

- [x] `cluster_name` + `application_name` on the Studio host (this incident, verified)
- [ ] **HAB-364** — `dbstats.go`: default `application_name` in `newDBPool`/`newSamplerDBPool`
      (URL param wins; add to `logPoolConfig`). Makes prod pods identifiable too.
- [ ] Optional, local-only: `DATABASE_MAX_CONNS=10` / `DATABASE_MIN_CONNS=2` in host `.env`
      — right-sizes the 25-conn wall and silences the 15s `db pool pressure` WARN cadence
      on an idle host. Prod keeps 25. (Human decision; low risk.)
- [ ] `multica-stack.sh`: assert `.env` parses cleanly (e.g. `bash -n` + grep for unquoted
      `&`/spaces in assignments) so the operator-error class dies at boot.
- [ ] Consider a `<app>-pg` naming line in the fleet LaunchEntity/host inventory docs when
      a second Postgres lands on any hive host.
- [ ] Linear capacity: file Appendix A issues when the workspace frees up.

## Links

- Trackers: HAB-363 (done) · HAB-364 (todo) — Multica project *Anima Memory / Andromeda*
- Evidence: `ps`/`pg_stat_activity` output in this session; pool telemetry `/tmp/multica-stack.err`
- Sibling problem class: [MCP-SPRAWL-PROBLEM.md](MCP-SPRAWL-PROBLEM.md) + its Activity Monitor screenshot
- Pool sizing rationale: `multica/server/cmd/server/dbstats.go` (comments on the prod incident)

## Appendix A — pending Linear issues

Free-issue-limit blocked 2026-08-26. Two files with ready-to-paste bodies live beside this
incident's session artifacts: incident = "Studio host: name Postgres processes
(cluster_name + application_name) — incident + convention" (→ Done); follow-up =
"multica server: default application_name in pgxpool config" (→ Todo, project
Anima Memory / Andromeda `24f49e6f052c`, team BIN). Bodies were preserved in this doc's
history (git) and in HAB-363/HAB-364 descriptions.

### Sync status (2026-08-26)

| Channel | Status |
|---|---|
| Multica (HAB-363/364) | ✅ done |
| multibrain/docs (this file) | ✅ done |
| Linear (BIN) | ⛔ free issue limit — pending capacity |
| Slack #projects | ⛔ bot token `account_inactive`, `slack` CLI not logged in — needs `slack login` |
