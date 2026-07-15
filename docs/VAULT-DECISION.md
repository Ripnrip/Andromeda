# Vault Decision & Reconciliation (READ BEFORE DEPOSITING) — 2026-07-05

> **Status 2026-07-14:** Canonical vault **`~/Developer/SecondBrain`** is live (`.obsidian` present; `07-Sessions/` populated by nightly + checkpoints). Pipeline `vault_dir` on Studio points at `…/SecondBrain/07-Sessions`. AI-Config at `~/Documents/Obsidian/vault/AI-Config` still exists as a legacy brain-sync target — migration/archive tasks below may still be open; **do not deposit multibrain output there**.

**Canonical second-brain vault = `~/Developer/SecondBrain`** (PARA/Zettelkasten). User-decided 2026-07-05. The PLAN already targets this path — no plan change needed. But **reality was split at decision time**, so reconcile before any pipeline deposits.

## The current tangle (3 locations, all on the Studio — NOT the VM)

| Location | What it is | Fate |
|----------|-----------|------|
| `~/Developer/SecondBrain` | The **canonical** PARA vault (near-empty). Has our `CLAUDE.md`/`WIKI.md`. | **Deposit target. Populate it.** |
| `~/Documents/Obsidian/vault/AI-Config` | The **live** brain today — own git repo **`Ripnrip/ai-config-brain`**, written by `brain-sync.py`. Holds `lessons/` (15), `decisions.md`, `index.md`, `log.md`, `session-digests.md` (96 KB), `_capture-health.md`. | **Migrate content in → then retire/archive.** |
| `~/Developer/CommonCrawl/data/obsidian_vault` | Separate **Lead Intelligence project** (CommonCrawl leads). Pulls the brain in via an `AI-Config` symlink. | **Cut the symlink; leave the project alone.** |

## Reconciliation tasks (coordinate — do not double-deposit)

1. **Migrate** `~/Documents/Obsidian/vault/AI-Config/*` into `~/Developer/SecondBrain` mapped to PARA (lessons → `01-Permanent/…` or `07-Sessions` where session-shaped; `decisions.md`/`index.md`/`log.md` → MOCs). Preserve git history if desired (the source is a real repo).
2. **Retarget `brain-sync.py`** — it's **chezmoi-managed**. Edit the **chezmoi source** (under `~/Documents/Developer/ai-ide-setup/home/…`), not the applied copy, or the change re-clobbers on `chezmoi apply`. Current: `VAULT=~/Documents/Obsidian/vault`, `BRAIN=$VAULT/AI-Config`. New target: `~/Developer/SecondBrain`. Also update `_capture-health.md`/`brain-health.py` if it hardcodes the old path.
3. **Cut the Lead-Intel symlink:** `rm ~/Developer/CommonCrawl/data/obsidian_vault/AI-Config` (it's just a symlink — brain content is safe at its real location). Leaves the Lead Intelligence project clean.
4. **Register** `~/Developer/SecondBrain` in Obsidian (one-time "open folder as vault") so `obsidian://open?vault=SecondBrain` / the `obs` alias resolve.
5. **Decommission** `Ripnrip/ai-config-brain` once migrated (archive the repo; stop brain-sync writing there).

## Owner
Substrate migration + brain-sync retarget overlap the multibrain build → **Codex's lane** (or a coordinated session). Claude has already fixed the user-facing `obs` alias (`~/.zshrc.d/40-aliases.zsh` → `obsidian://open?path=/Users/admin/Developer/SecondBrain`). Do NOT let the pipeline deposit into AI-Config or the CommonCrawl vault.
