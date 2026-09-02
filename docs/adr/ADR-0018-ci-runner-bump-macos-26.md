# ADR-0018: CI macOS runner bump — macos-15 → macos-26

- **Status:** Accepted
- **Date:** 2026-09-02
- **Context:** Andromeda CI audit (PR #63 Codex P2 fixes, Multica `1c6009ba`)
- **Supersedes:** the macos-15 baseline pin implied by ci.yml comments (no prior ADR)

## Context

`ci.yml` and `web-visual-diff.yml` run on GitHub-hosted **`macos-15` (arm64, Xcode 16.4)**,
and the snapshot baselines are contractually pinned to that runner image ("Snapshot PNGs
are tied to this image — re-record with `[record-snapshots]` if changed").

Two problems surfaced:

1. **30 PreviewParitySnapshotTests failures** — verified pre-existing on clean branch
   HEAD. Cause: baselines are recorded on CI's macos-15 image; local verification on
   the fleet (macOS 26) renders differently, so every local `swift test` run is red.
2. **Image-generation drift** — GitHub has deprecated macos-14 and now ships a
   `macos-26` arm64 image; macos-15 is next in the deprecation line. Staying pinned
   to a deprecated-generation image accumulates re-record debt with every bump we
   postpone.

The fleet (studio.local and dev machines) runs macOS 26. GitHub offers
`macos-26` arm64 at the same billing rate as `macos-15` arm64.

## Considered options

| Option | Verdict | Why |
|---|---|---|
| **A. Bump GHA image to `macos-26`** | **chosen** | Same OS generation as the fleet — the runner-image-bound baseline drift class collapses instead of being papered over. One-line-per-workflow + one `[record-snapshots]` re-record commit. Same arm64 pricing. |
| B. Self-hosted runner on Studio | deferred, separate task | Zero GHA minutes and permanent fleet parity, but it's a persistent daemon — per AGENTS.md it must be enrolled with visible status/telemetry/ownership (FleetObserve + typed Swift install per BIN-101), not a rushed CI escape hatch. Fork-PR trust boundary also needs thought. Track under Fleet pillar; ci.yml comments already name Studio as the intended fallback tier. |
| C. Per-platform baseline sets (macos-15 + local) | rejected | Doubles baseline maintenance forever; treats the symptom. |
| D. Perceptual-diff tolerance | rejected for now | Weakens the vacuous-suite guard that BaselineIntegrityTests just strengthened (same PR cycle). Revisit only if A still leaves legitimate cross-minor-version drift. |

## Decision

1. Bump `runs-on:` from `macos-15` to `macos-26` in `.github/workflows/ci.yml` and
   `.github/workflows/web-visual-diff.yml`.
2. Re-record baselines via a PR-head `[record-snapshots]` tip on the new image.
3. Update the in-file comments that pin "macos-15 + Xcode 16.4" to the new image.
4. Local macOS 26 verification becomes meaningful again (same generation as CI).

## Consequences

- One noisy baseline-re-record commit lands; reviewers must not hand-edit PNGs.
- The 30 local snapshot failures should collapse (root cause removed, not masked).
- Multica `1c6009ba` (snapshot fast-follow) closes if the suite goes green on both
  CI and local.
- Studio self-hosted runner remains a **deferred** follow-up, to be done properly
  under the Fleet pillar with FleetObserve visibility when enrolled.

## References

- Audit doc: `docs/FLIP-STATUS-2026-09-01.md`
- Baseline pin comments: `.github/workflows/ci.yml` (~L31–34, L256)
- Multica: `1c6009ba-6dfa-4b4d-9ea5-fa8fba62b4c2`
