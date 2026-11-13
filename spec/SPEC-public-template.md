# SPEC: Public Template & Private Copies

Companion to ADR-008. Specifies how the public template and each user's private copy fit together, what install/uninstall do, and how the template is kept free of personal data. Planned work: `PLAN-public-template.md`.

## 1. Goals / non-goals

**Goals**

- G1: Anyone with Claude Code (optionally also `sbx`) can clone the template and install it without clobbering an existing `~/.claude/`.
- G2: A user keeps their own instructions, memory, settings and skills in git and pulls template updates without merge conflicts.
- G3: No personal paths, usernames or account-specific config ship in the template; every script self-locates from its own path.
- G4: Install is reversible — uninstall restores the pre-install state.
- G5: The repo carries an open-source license (MIT).

**Non-goals**

- Hosting mechanics (CI, releases).
- Making the sandbox kit (`spec.yaml`, `run-sandbox.sh`) optional: it is a core feature.

## 2. Two repos

| Repo | Visibility | Contents |
|---|---|---|
| Template | Public | Scripts, `spec.yaml`, docs, tests, starter files |
| Private copy | Private (hosted or local) | Template files + everything personal |

A private copy is a clone of the template with two remotes:

```bash
git remote rename origin upstream
git remote set-url --push upstream DISABLED   # pushes to the template fail
git remote add origin <private repo URL>
```

Template updates: `git pull upstream main`. Template changes are made in a separate clone of the template, never moved out of a private copy, so personal files can't leak with them.

## 3. Ownership

What keeps `git pull upstream` conflict-free:

| Owner | Files | Rule |
|---|---|---|
| Template | Scripts, `spec.yaml`, `adr/`, `spec/`, `test/`, `README.md`, `LICENSE`, `.gitignore` | Users don't edit them |
| User | Everything in `files/home/.claude/`, `skills/`, `projects/` | The template ships starters and never changes them after the first release; new defaults are announced in the README |

Starter files:

| File | Starter |
|---|---|
| `files/home/.claude/CLAUDE.md` | One working style, as an example to edit; imports `memory/MEMORY.md` |
| `files/home/.claude/settings.json` | `permissions.additionalDirectories` (`~/.claude/memory`, `~/.claude/projects`) and the official plugin marketplace. No bypass mode, model, plugins or MCP servers |
| `files/home/.claude/memory/MEMORY.md` | Empty index |
| `skills/` | Empty |

## 4. Install / uninstall

`install.sh` (idempotent, self-locating, run from anywhere). Managed paths are every top-level entry of `files/home/.claude/` (dotfiles included, `.DS_Store` excluded), plus `skills/` and `projects/` from the repo root. For each:

1. Source missing (`projects/` before Claude Code creates it): skip.
2. Destination already a symlink into this repo: skip.
3. `settings.json` exists at the destination: print a diff and replace it only on confirmation (`--yes` skips the prompt; no answer declines).
4. Destination exists (file, folder, or symlink elsewhere): move it to `~/.claude/.claude-config-backup-<timestamp>/<name>`.
5. Create the symlink.

It then points the sbx skills store at `skills/` the same way (backup name `sbx-skills-store`), skipping it while sbx is missing, signed out or has never run. It prints what was linked, backed up and skipped.

`uninstall.sh`:

1. For every entry of `~/.claude/` that is a symlink into this repo: remove it and restore the most recent backup of that name, or leave it absent if there is none. Anything else is never touched.
2. The same for the sbx skills store.

Because both scripts derive their paths from the folder, adding config (e.g. `agents/`) needs no script change.

## 5. Keeping personal data out

- Scripts compute `REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; docs use relative commands (`./install.sh`) and placeholders (`/Users/<user>`).
- `test/test_no_hardcoded_paths.sh` fails on any `/Users/<name>` or `/home/<name>` other than `/home/agent` (the sandbox user) in any file of the repo, docs included.

## 6. Testing

Per ADR-005, `test/run.sh` runs every `test/test_*.sh`:

1. Static: `test_no_hardcoded_paths.sh`; `test_shellcheck.sh` (skips if `shellcheck` isn't installed).
2. `install.sh` / `uninstall.sh` in a throwaway `$HOME`, with `sbx` stubbed so the machine's real skills store is never touched: fresh install, idempotent re-run, backup of an existing file, `settings.json` confirm/decline, a new `files/home/.claude/` entry linked and removed, uninstall leaving foreign files alone and restoring backups.

`run-sandbox.sh` needs a real sbx and is checked by hand before a release (fresh-clone test in `PLAN-public-template.md`).

## 7. Rejected alternatives

- **Template as a git subtree in the personal repo, with the personal `CLAUDE.md` importing the template's (`@../../../template/...`).** Avoids text merges of `CLAUDE.md`, but needs a relative import path that fails silently when wrong, a `skills -> template/skills` symlink chain through the sbx store, and subtree commands for every update. Replaced by the ownership split (§3), where users own `CLAUDE.md` outright and plain `git pull` never touches it.
- **Git submodule.** `template/` stays empty until an explicit init step, which breaks kit injection at sandbox create.
- **The whole config as a Claude Code plugin.** Plugins can't carry `CLAUDE.md`, the main payload, and namespace skills.
- **`.example` files copied by hand.** Manual merge on every update.
