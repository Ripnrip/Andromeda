# zsh 5.9 buffer-overflow crashes when spawned by Manus (macOS 26 beta)

**Date:** 2026-08-25 · **Tracking:** [HAB-360](https://habitat.multica.app) (Multica) · **Found during:** iTerm2 "session ended very soon" fix

## What

30+ crash reports in `~/Library/Logs/DiagnosticReports/zsh-2026-08-1*.ips` (Aug 12–17, 2026):

- `/bin/zsh` 5.9 (arm64-apple-darwin25.0) on macOS 26.0 beta (25A354)
- `EXC_BREAKPOINT (SIGTRAP)` → `__chk_fail_overflow` via `__sprintf_chk` — "detected buffer overflow"
- Dies ~25ms after launch, **before any rc file runs** (not a dotfile problem)
- `responsibleProc: Manus` on every crash; parents vary (Manus, bash, Docker backend, nested zsh)

## Key insight

Apple's stock zsh crashes at spawn **only when Manus is the responsible process**. iTerm2, Terminal.app, and manual/logind spawns are unaffected. If shells die instantly inside Manus, this is the cause — separate from any terminal-app issue.

Suspected mechanism: zsh 5.9's hardened `sprintf` fortify checks trip during prompt/terminal-init when the environment Manus sets (env vars or pty state) overflows a fixed stack buffer. Crash memory is full of powerline 256-color escape sequences.

## Action

- [ ] File Apple Feedback with 3+ `.ips` attachments
- [ ] Report to Manus with the same evidence
- [ ] Recheck after next macOS 26 beta (`sw_vers` build ≥ 25A354 successor)

Related-but-separate: iTerm2 3.6.11 "session ended very soon after starting" was a wedged app instance (zero windows, dead AppleScript) — fixed by SIGTERM + relaunch on 2026-08-25.
