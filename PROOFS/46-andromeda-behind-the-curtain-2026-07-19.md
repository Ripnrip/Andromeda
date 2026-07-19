# PROOF 46 — Andromeda Behind the Curtain (2026-07-19)

## Pinned scope

- Original multibrain documentation commit:
  `ae40c4c728cffaa691dbfc07857c9f8caf0befdf`.
- Original Andromeda mirror commit:
  `f7490eb04252ef0e60faa8f979903255fe9158a5`.
- Corrective follow-up is the commit containing this proof in each repository.
  Self-referencing its SHA inside its own contents is impossible; resolve the exact
  verification targets after checkout with:

```bash
git log -1 --format=%H -- PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md
git branch --show-current
```

Expected branches are multibrain `main` and Andromeda
`feat/andromeda-hud-core-promote`. PR #10 was not merged.

## Claim and evidence

| Claim | Evidence |
|-------|----------|
| Six pillars and stable client curtain are canonical | `docs/ANDROMEDA-CONTROL-PLANE.md` |
| `memory.recall/store` ship; Home/Bar journal/session dump parser ships; HUD parser remains incomplete | `docs/MEMORY-ONEPAGER.md`, parser test results below |
| `infer.write` currently stores an episodic record tagged `infer-write` | canonical capability matrix; existing HUD/MemoryKit contract |
| `project.state.list/get/create/update` ships behind operator routing | canonical capability matrix; project-state tests below |
| SwiftData is the only implemented hot store | `docs/DATA-CONTRACTS.md`; `~/.multibrain/anima-hot.store` |
| Studio is hub; Book is unverified satellite; Mini is isolated | `docs/FLEET.md`, `docs/RUNBOOK.md` |
| SecondBrain and SwiftData are SoTs; indexes are rebuildable | control-plane store matrix; `docs/DATA-CONTRACTS.md` |
| Visibility defaults private; credential/cloak material forces internal | privacy matrix; visibility and CloudKit tests below |
| Letta is Python interactive Librarian, never nightly conductor | `docs/RUNBOOK.md`, control-plane Letta boundary |
| Context7 has no implementation/code presence; documentation references are non-prescriptive | canonical non-prescriptive note; scoped search below |
| Post-flip install remains all-Swift and command-gated | `docs/RUNBOOK.md`; BIN-101 |
| Workspace flip remains NO-GO | `docs/ANDROMEDA-WORKSPACE-READINESS.md`, PROOF 44 |

## Recorded verification

Commands were run from the named repository unless a subdirectory is shown.

### Targeted tests

```bash
cd Packages/MemoryKit
swift test --filter 'CloudKitSyncTests|ProjectStateSurfaceTests|VisibilityFilterTests'
```

Result: **PASS — 43 tests in 3 suites, 0 failures**. This independently reproduces
the reviewer's 43-test privacy/CloudKit/project-state result.

```bash
cd /Users/admin/Developer/Andromeda
swift test --filter 'HUDCommandTests|AndromedaMemoryCommandTests'
```

Result: **PASS — 7 tests in 2 suites, 0 failures** for the exact current HUD/Home
parser suites. The separate reviewer reported **PASS — 16 Home/HUD parser tests**;
that independent total is retained as reviewer evidence rather than rewritten as a
locally observed count.

### Eight byte-identical mirrors

```bash
for f in ANDROMEDA-CONTROL-PLANE.md MEMORY-ONEPAGER.md FLEET.md RUNBOOK.md \
  DATA-CONTRACTS.md ANDROMEDA-SURFACE-AREA.md ANDROMEDA-WORKSPACE-READINESS.md; do
  cmp -s "docs/$f" "/Users/admin/Developer/Andromeda/docs/$f" || exit 1
done
cmp -s PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md \
  /Users/admin/Developer/Andromeda/PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md
```

Result: **PASS — 8/8 byte-identical**. Pairwise SHA-256 verification used:

```bash
shasum -a 256 docs/ANDROMEDA-CONTROL-PLANE.md \
  /Users/admin/Developer/Andromeda/docs/ANDROMEDA-CONTROL-PLANE.md |
  awk '{print $1}' | uniq | wc -l
shasum -a 256 PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md \
  /Users/admin/Developer/Andromeda/PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md |
  awk '{print $1}' | uniq | wc -l
```

Result: **PASS — each pair printed `1` unique hash**. `cmp` above covers all eight;
the hash command records representative canonical-doc and proof pairs.

### Markdown, Mermaid, stale claims, and secrets

```bash
python3 - <<'PY'
from pathlib import Path
import re
files = list(Path("docs").glob("*.md")) + [Path("README.md"), Path("PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md")]
for path in files:
    text = path.read_text()
    assert len(re.findall(r"(?m)^```(?:[A-Za-z0-9_-]+)?\s*$", text)) % 2 == 0, path
    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
        if "://" not in target and not target.startswith("#"):
            assert (path.parent / target.split("#", 1)[0]).resolve().exists(), (path, target)
    for block in re.findall(r"```mermaid\n(.*?)```", text, re.S):
        assert block.lstrip().startswith(("flowchart", "sequenceDiagram", "graph"))
print("markdown_links=PASS fences=PASS mermaid_blocks=PASS")
PY
```

Recorded result: `markdown_links=PASS fences=PASS mermaid_blocks=PASS`.

```bash
rg -n -i 'SwiftData (or|/) Realm|Letta (owns|conducts|runs)( the)? nightly|Context7 has (zero|no) repo presence|retro.*(template only|not installed)|dreamcatcher.*(paid default|uses Haiku path)|Rebuild HUD with .*install-and-sign\.sh' \
  AGENTS.md README.md Features.md Roadmap.md TODO.md docs/ANDROMEDA-*.md \
  docs/DATA-CONTRACTS.md docs/FLEET.md docs/MEMORY-ONEPAGER.md docs/RUNBOOK.md
```

Recorded result: **no active stale claim**. Historical matches intentionally remain
outside this active-doc scope in `Changelog.md`, `docs/PLAN.md`, and `docs/VISION.md`.

```bash
rg -n '(sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,})' \
  AGENTS.md README.md Features.md Roadmap.md TODO.md docs PROOFS/46-andromeda-behind-the-curtain-2026-07-19.md
git diff --check
```

Recorded result: **secret-pattern matches `0`; diff check PASS**.

## Tracker cross-link evidence

- Linear **BIN-102**:
  <https://linear.app/binary-bros/issue/BIN-102/andromeda-control-plane-pillars-mcp-host-skills-llm-proxy-secrets>
  - original comment: `42ca4aa1-ce9c-4e57-9280-d43dcc2ffeac`
  - corrective explicit HAB-105/PROOF 46 comment:
    `26a31316-a361-49cb-9c57-2a4051dc66b0`
- Multica **HAB-105** (no stable issue URL exposed by the CLI):
  - issue UUID: `31b653d4-f287-40ab-8920-ea016a3671ab`
  - original comment: `c7f8b4ad-8094-476b-9add-3293f232174a`
  - corrective explicit BIN-102/PROOF 46 comment:
    `db3c26d5-ce1c-41c7-b7a7-36bd4f2f8c1e`

## Remaining gaps and re-audit criteria

- HUD still lacks journal/session-dump parser parity and bypasses `VisibilityFilter`.
- Python notes do not consistently emit `visibility` / `content_hash`.
- CloudKit public/friends-only egress is unit-proven, not GUI/live-replica proven.
- `infer.write` naming still mismatches its episodic-store behavior.
- Book jobs/tunnels need fresh live verification; Mini remains isolated.
- Secrets broker, MCP consolidation, SkillRegistry product surface, Swift Letta
  replacement, and typed fleet mutate are not shipped.
- BIN-101 must deliver the typed Swift `andromeda-install` artifact and exact command;
  no Bash substitute is approved.
- Merge PR #10 only after green CI, rerun this proof on the resulting `main`, preserve
  PROOF 44 NO-GO, and require the human word before workspace promotion.
