## Summary

-

## Checklist

- [ ] I did **not** add shell scripts (`.sh` / bash shebang) where Swift or Actions YAML was required.
- [ ] Any shell file in this PR is on `config/shell-allowlist.txt` and has explicit reviewer approval.
- [ ] I ran `python3 Tools/no_bash_surface_gate.py` (or `swift test --filter NoBashSurfacePolicy`) locally when touching repo layout / tooling.
- [ ] Docs / changelog updated if behavior, schema, or ops expectations changed.
