# CI — self-hosted macOS (Studio)

> **Why:** GitHub-hosted `macos-*` runners bill minutes and currently fail at job start when the account spending limit / payment gate trips. A **self-hosted Mac runner does not consume hosted macOS minutes**.

> **Why not `ubuntu-latest`?** This package declares `platforms: [.macOS(.v14)]` and ships AppKit HUD/Home targets. SPM will not build the root package on Linux, so a free Linux hosted job cannot replace macOS CI here.

## Job

| Job | Runner | Covers |
|-----|--------|--------|
| `Build & Test (macOS self-hosted)` | `[self-hosted, macOS]` | Full build + AppKit/SwiftUI snapshots + MemoryKit |

Workflow: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

Darwin runners automatically get `macOS` plus `ARM64` or `X64` — GitHub’s default `runs-on: self-hosted` snippet works; we pin `macOS` so a Linux self-hosted box cannot steal the job.

## Register a Studio (or Book) runner — operator once

Do this on the Mac that should run HUD snapshots. Prefer **Studio**. Keep the runner **visible** (LaunchAgent below) — Charter/AGENTS ban invisible watchdogs.

### 1. Create a registration token (human / admin)

In GitHub: **Repo → Settings → Actions → Runners → New self-hosted runner** → macOS / ARM64.  
Copy the short-lived token (≈1 hour). **Never commit the token.**

### 2. Install outside the git index (recommended) **or** under Andromeda with gitignore

**Preferred** (keeps the clone clean):

```console
mkdir -p "$HOME/actions-runner" && cd "$HOME/actions-runner"
```

**If you insist on the Andromeda folder**, use a sibling or ignored path — `actions-runner/` is in `.gitignore`:

```console
cd /path/to/Andromeda
mkdir -p actions-runner && cd actions-runner
```

Download + verify (pin matches GitHub UI as of 2026-07; pick **one** arch):

**Apple Silicon (`osx-arm64`):**

```console
curl -o actions-runner-osx-arm64-2.335.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-osx-arm64-2.335.1.tar.gz
echo "e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769  actions-runner-osx-arm64-2.335.1.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-osx-arm64-2.335.1.tar.gz
```

**Intel Mac (`osx-x64`):**

```console
curl -o actions-runner-osx-x64-2.335.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.335.1/actions-runner-osx-x64-2.335.1.tar.gz
echo "b2fe57b2ae5b0bc1605f9fc0723c07eedf06167321d3478ce0440f15e5b0a010  actions-runner-osx-x64-2.335.1.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-osx-x64-2.335.1.tar.gz
```

Configure — URL **must** be Andromeda (not multibrain). Replace `REPLACE_ME` with a fresh token from
**Andromeda → Settings → Actions → Runners → New self-hosted runner** (never commit tokens):

```console
./config.sh --url https://github.com/Ripnrip/Andromeda \
  --token REPLACE_ME \
  --name studio-andromeda \
  --work _work
```

On Darwin this registers labels `self-hosted`, `macOS`, and `ARM64` or `X64` automatically — enough for `[self-hosted, macOS]` (stricter than GitHub’s bare `self-hosted` snippet, so a Linux box cannot steal the job).

Foreground smoke test:

```console
./run.sh
```

Leave that terminal open until GitHub shows the runner **Idle** under **Ripnrip/Andromeda**, then stop with Ctrl+C and install the LaunchAgent (§3) so it survives logout.

Newer pins: https://github.com/actions/runner/releases.

### 3. LaunchAgent (visible status)

Template: [`ops/com.andromeda.github-actions-runner.plist`](../ops/com.andromeda.github-actions-runner.plist).

Default ProgramArguments point at `$HOME/actions-runner/run.sh` (Studio template `/Users/admin/...`). If you installed under `~/Developer/Andromeda/actions-runner`, edit the rendered plist paths before bootstrap.

```console
LABEL=com.andromeda.github-actions-runner
SRC="$HOME/Developer/Andromeda/ops/${LABEL}.plist"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
/usr/bin/python3 -c "from pathlib import Path; import os; p=Path('$SRC'); t='/Users/admin'; Path('$DEST').write_text(p.read_text().replace(t, os.environ['HOME']))"
# If runner lives under Andromeda/actions-runner, fix paths:
# /usr/bin/sed -i '' "s|/actions-runner/|/Developer/Andromeda/actions-runner/|g" "$DEST"   # adjust to taste
/bin/mkdir -p "$HOME/.multibrain/logs" "$HOME/Library/LaunchAgents"
/bin/launchctl bootout "gui/$(/usr/bin/id -u)/${LABEL}" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$DEST"
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/${LABEL}"
```

Confirm in GitHub Runners UI: status **Idle** / **Online**, labels include `macOS`.

Logs: `~/.multibrain/logs/andromeda-gha-runner.launchd.log`.

### 4. Xcode / snapshots

- Prefer Xcode 16.4 if installed (`/Applications/Xcode_16.4.app`); otherwise the job uses `/Applications/Xcode.app`.
- Snapshot PNGs are **host-tied**. After first green run on a new Mac/Xcode, tip `[record-snapshots]` and commit baselines if pixels drift vs old hosted `macos-15` goldens.

## Security

- Private repo only for this runner until fork PR policy is locked.
- Do not expose the runner to untrusted workflows; disable public fork PRs or require approval.
- Env scrub: runner LaunchAgent keeps `HOME` + `PATH` only (no paid API keys) — same curtain as HUD.
- Registration tokens expire quickly; treat any token pasted into chat as burned and mint a fresh one from the GitHub UI if unsure.

### Fallback (hosted macOS)

While Studio self-hosted is offline, CI uses GitHub-hosted `macos-15` (same as `feat/andromeda-hud-core-promote`). Billing is unblocked on that path as of 2026-07-21. Switch `runs-on` back to `[self-hosted, macOS]` in `.github/workflows/ci.yml` once Andromeda shows an **Idle** runner.

## Behavior when offline

If no self-hosted runner is online, the macOS job **queues** (does not burn hosted macOS minutes). Start or kickstart the LaunchAgent on Studio to drain the queue.

To temporarily re-enable hosted macOS after billing is fixed, change `runs-on` back to `macos-15` in `ci.yml` (and budget for minutes).

## Related

- Fleet observe stays observe-only; runner mutate/install is operator docs until a typed install target exists.
- HUD install mutate: `swift run andromeda-install hud`
