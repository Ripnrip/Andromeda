# CI — self-hosted macOS (Studio)

> **Why:** GitHub-hosted `macos-*` runners bill minutes and currently fail at job start when the account spending limit / payment gate trips. A **self-hosted Mac runner does not consume hosted macOS minutes**.

> **Why not `ubuntu-latest`?** This package declares `platforms: [.macOS(.v14)]` and ships AppKit HUD/Home targets. SPM will not build the root package on Linux, so a free Linux hosted job cannot replace macOS CI here.

## Job

| Job | Runner | Covers |
|-----|--------|--------|
| `Build & Test (macOS self-hosted)` | `[self-hosted, macOS, andromeda]` | Full build + AppKit/SwiftUI snapshots + MemoryKit |

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## Register a Studio (or Book) runner — operator once

Do this on the Mac that should run HUD snapshots. Prefer **Studio** so paths match fleet docs. Keep the runner **visible** (LaunchAgent below) — Charter/AGENTS ban invisible watchdogs.

### 1. Create a registration token (human / admin)

In GitHub: **Repo → Settings → Actions → Runners → New self-hosted runner**  
(or org runners if you prefer org scope). Copy the short-lived token. Labels **must** include:

- `self-hosted` (added automatically)
- `macOS` (added automatically on Darwin)
- `andromeda` (**add this custom label** — workflow requires it)

### 2. Install the runner under `$HOME` (not a hidden path)

Example layout (Studio template home is `/Users/admin` — rewrite on Book):

```console
mkdir -p "$HOME/actions-runner" && cd "$HOME/actions-runner"
curl -fsSL -o actions-runner-osx-arm64.tar.gz \
  https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-osx-arm64-2.322.0.tar.gz
tar xzf ./actions-runner-osx-arm64-2.322.0.tar.gz
./config.sh --url https://github.com/Ripnrip/Andromeda \
  --token REPLACE_ME \
  --name studio-andromeda \
  --labels macOS,andromeda \
  --work _work
```

Use the Intel (`osx-x64`) tarball on Intel Macs. Pin a current runner release from https://github.com/actions/runner/releases.

### 3. LaunchAgent (visible status)

Template: [`ops/com.andromeda.github-actions-runner.plist`](../ops/com.andromeda.github-actions-runner.plist).

Render Studio home → `$HOME`, then bootstrap (absolute `launchctl`):

```console
LABEL=com.andromeda.github-actions-runner
SRC="$HOME/Developer/Andromeda/ops/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
/usr/bin/python3 -c "from pathlib import Path; import os; p=Path('$SRC'); t='/Users/admin'; Path('$DEST').write_text(p.read_text().replace(t, os.environ['HOME']))"
/bin/mkdir -p "$HOME/.multibrain/logs" "$HOME/Library/LaunchAgents"
/bin/launchctl bootout "gui/$(/usr/bin/id -u)/${LABEL}" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$DEST"
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/${LABEL}"
```

Confirm in GitHub Runners UI: status **Idle** / **Online**, labels include `andromeda`.

Logs: `~/.multibrain/logs/andromeda-gha-runner.launchd.log`.

### 4. Xcode / snapshots

- Prefer Xcode 16.4 if installed (`/Applications/Xcode_16.4.app`); otherwise the job uses `/Applications/Xcode.app`.
- Snapshot PNGs are **host-tied**. After first green run on a new Mac/Xcode, tip `[record-snapshots]` and commit baselines if pixels drift vs old hosted `macos-15` goldens.

## Security

- Private repo only for this runner until fork PR policy is locked.
- Do not expose the runner to untrusted workflows; disable public fork PRs or require approval.
- Env scrub: runner LaunchAgent keeps `HOME` + `PATH` only (no paid API keys) — same curtain as HUD.

## Behavior when offline

If no self-hosted runner is online, the macOS job **queues** (does not burn hosted macOS minutes). Start or kickstart the LaunchAgent on Studio to drain the queue.

To temporarily re-enable hosted macOS after billing is fixed, change `runs-on` back to `macos-15` in `ci.yml` (and budget for minutes).

## Related

- Fleet observe stays observe-only; runner mutate/install is operator docs until a typed install target exists.
- HUD install mutate: `swift run andromeda-install hud`
