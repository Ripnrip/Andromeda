# No Bash implementation surface

**Status:** Enforced (BIN-219)  
**Charter:** `ANDROMEDA-CHARTER.md` — “No Bash implementation surface”

## Rule (agents)

1. **Swift-first.** Operational behavior belongs in Swift modules, typed CLIs, launchable app components, or GitHub Actions YAML.
2. **No new `.sh` files** for orchestration, validation, security checks, installers, or agent workflows.
3. **Shell only via allowlist.** The only committed shell scripts permitted are paths listed in `config/shell-allowlist.txt`. That list is empty by default.
4. **Never “fix” Bash with Bash.** Do not add `lint-no-shell.sh` or similar. Enforcement is Swift tests + `Tools/no_bash_surface_gate.py` + Actions YAML.
5. **Running a shell interactively is fine.** Ban *committing* project-maintained shell automation, not using a shell to investigate.

## Mechanical gates

| Gate | How |
| --- | --- |
| Local / agents | `python3 Tools/no_bash_surface_gate.py` or `swift test --filter NoBashSurfacePolicy` |
| Pre-commit | `git config core.hooksPath .githooks` (Python hook, not a `.sh` file) |
| CI | `.github/workflows/no-bash-surface.yml` (required check) |

## Exception path

1. Explicit human approval on the PR.
2. Add the repo-relative path to `config/shell-allowlist.txt` in the same PR.
3. Prefer an ADR when the script carries operational or security logic.
4. PR template checkbox must acknowledge the exception.

## Canary

CI proves `scripts/oops.sh` is rejected. A PR that adds an unallowlisted `.sh` must go red.
