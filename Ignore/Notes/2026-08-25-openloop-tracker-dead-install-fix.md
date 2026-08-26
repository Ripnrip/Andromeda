# OpenLoopTracker was dead-on-arrival — fixed 2026-08-25

**Tracking:** claude-side knowledge-sync done · **Repo:** `~/Developer/Closure/open-loop-tracker` · **Found during:** iTerm2 fix session (HAB-360 day)

## What
- Collector `~/.local/bin/open-loop-collector` broken **since install (Aug 14)**: `install-local.sh` copies binaries but not `libRealmSwift.dylib`; binary rpath is `@loader_path` only → `dyld: Library not loaded` on every exec.
- Consequence: Realm store `~/Library/Application Support/OpenLoopTracker/open-loop.realm` **empty** — zero sessions ever tracked. The spool fallback also empty (wrapper only fires on `claude` invocations).

## Fix (applied)
1. `cp .build/release/libRealmSwift.dylib ~/.local/bin/` — collector works.
2. `scripts/install-local.sh` patched to install the dylib (**uncommitted — review/commit**).
3. Verified end-to-end: `start` → 1 open session → `exit` → 0 → `erase-local-data`.

## Next (roadmap: gather + recap)
- `herd-gather` tool: CGWindowList terminal enumeration + `herdr api snapshot` → create ONE new Herd workspace (never fuse existing), one labeled tab per terminal, recap summary.
- Recap pipeline: gathered terminals + OpenLoopTracker open loops → daily recap → auto-create Multica issues / Andromeda notes.
- herdr 0.8.0 has no color API yet — labels + emoji ink only; revisit when display metadata grows color tokens.
