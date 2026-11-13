# SPEC: Sandbox Configuration Kit

Companion to ADR-002 and ADR-007. Specifies the file layout, how each piece of config reaches a sandbox, and operational procedures.

Requires sbx ≥ v0.50 (skills store, `sbx ls --json`) and `jq` on the host.

## 1. Goals

- G1: Any sandbox created by `run-sandbox.sh` gets the same `CLAUDE.md`, personal memory, settings, MCP servers, plugins and skills as the host, with no manual steps.
- G2: There is exactly one copy of each config file, in this repo.
- G3: Memory and transcripts written in a sandbox are on the host as soon as they are written — no export step.
- G4: A skill installed in any sandbox or on the host lands in the repo.

## 2. Repository layout

```
claude-sandbox-kit/
├── spec.yaml                  # Kit manifest (kind: mixin)
├── files/home/.claude/        # Kit payload, copied into sandbox ~/.claude/ at create
│   ├── CLAUDE.md              # Global instructions; imports memory/MEMORY.md
│   ├── settings.json          # Settings + MCP server and plugin lists
│   ├── memory/                # Personal memory
│   └── <anything else>        # e.g. agents/, commands/ — linked and copied like CLAUDE.md
├── skills/                    # Shared skills (host, sbx skills store, sandboxes)
│   ├── <name>/SKILL.md
│   ├── synced/                # claude.ai skills, written by Claude Code (gitignored)
│   └── .trash/                # (gitignored)
├── projects/                  # ~/.claude/projects: project memory + transcripts (gitignored)
├── install.sh / uninstall.sh  # Host symlinks + sbx skills store link (with backups) / reverse
└── run-sandbox.sh             # Create / attach, applying host config each time
```

## 3. Kit manifest (`spec.yaml`)

```yaml
schemaVersion: "1"
kind: mixin
name: claude-sandbox-kit
displayName: Claude Sandbox Kit
description: Injects CLAUDE.md, skills, and settings into any Claude sandbox
```

`kind: mixin` extends the built-in `claude` agent. The kit only copies `files/home/.claude/` into the sandbox at create; everything else is done by `run-sandbox.sh`.

## 4. How each piece reaches a sandbox

| What | Host | Sandbox | Mechanism |
|---|---|---|---|
| `CLAUDE.md` and any other entry of `files/home/.claude/` (e.g. `agents/`) | `~/.claude/<entry>` → repo | `/home/agent/.claude/<entry>` (copy) | Kit at create; `run-sandbox.sh` re-copies on every attach |
| Personal memory | `~/.claude/memory/` → repo | `/home/agent/.claude/memory` → repo folder mounted at its host path (live, read-write) | Extra workspace at create; `run-sandbox.sh` symlinks it; loaded via `@~/.claude/memory/MEMORY.md` in `CLAUDE.md` |
| Project memory + transcripts | `~/.claude/projects/<key>/` → repo `projects/<key>/` | `/home/agent/.claude/projects/<key>` → that folder mounted at its host path (live, read-write) | Extra workspace at create; `run-sandbox.sh` symlinks the one entry (sbx keeps `~/.claude/projects` on its own disk) |
| `settings.json` | `~/.claude/settings.json` → repo | `/home/agent/.claude/settings.json` | `run-sandbox.sh` deep-merges the repo file over sbx's defaults, without `blockReadsOutsideWorkingDirectories` |
| MCP servers | `mcpServers` in `settings.json` | `~/.claude.json` | `run-sandbox.sh` runs `claude mcp add --scope user` per entry |
| Plugins | `extraKnownMarketplaces` / `enabledPlugins` | `~/.claude/plugins/` | `run-sandbox.sh` adds marketplaces and installs plugins |
| Skills | `~/.claude/skills` → repo `skills/`; sbx store → repo `skills/` | `/home/agent/.claude/skills` (live, read-write) | sbx skills store, `--skills=readwrite` |

### What a sandbox can change

| Persists to the host (live) | Reverted on next attach | Sandbox-only until `sbx rm` |
|---|---|---|
| Project folder, project memory + transcripts, skills, personal memory | `CLAUDE.md` and the other copied entries; `settings.json` keys present in the repo file; MCP servers and plugins listed there (re-added) | Other settings keys, extra MCP servers/plugins, installed packages, logins, files outside the mounts |

`<key>` is the project path with every non-alphanumeric character replaced by `-` — Claude Code's own scheme when run from the repo root (Claude Code keys memory on the git root, so run `run-sandbox.sh` from there); the sandbox sees the project at the same path, so it uses the same key. Sandbox sessions appear in `claude --resume` on the host; resuming one there runs it outside the sandbox.

`CLAUDE.md` and settings flow host → sandbox only, so a sandbox cannot change the host's instructions or hooks. Personal memory is writable on purpose and is loaded by every host session — review with git and `/memory-promotion`.

Facts behind the mechanisms (tested 2026-10-30, sbx v0.50.1, Claude Code 2.1.306):

- sbx writes its own `settings.json` at create, replacing the kit's copy. It sets `permissions.defaultMode: bypassPermissions`, which the merge keeps.
- Claude Code does not read `mcpServers` from `settings.json`, and does not auto-install plugins from `enabledPlugins`.
- The sandbox image has `uv` but not `uvx`; `run-sandbox.sh` adds a `/usr/local/bin/uvx` shim (`exec uv tool run "$@"`).
- `claude plugin install` and `claude plugin marketplace add` exit 0 when already done; a marketplace declared only in `settings.json` is not enough to install from it. `claude mcp add-json` exits 1 if the server exists (tested 2026-11-02).
- A file placed with `sbx cp` is owned by the host uid (501), so the agent can't write it (tested 2026-11-02), nor delete it from sticky `/tmp`; `run-sandbox.sh` clears its `/tmp` staging path as root. `sbx cp` of a folder to a path that doesn't exist creates it with the folder's contents (no nesting); re-copies replace the sandbox's copy, deletions included (tested 2026-11-13).
- Claude Code does not load `~/.claude/memory/` on its own; the `@import` in `CLAUDE.md` does. Topic files are opened with the Read tool, which `blockReadsOutsideWorkingDirectories` blocks unless `permissions.additionalDirectories` includes `~/.claude/memory`. Skill folders are exempt.
- Everything `run-sandbox.sh` sets survives `sbx stop` / start; a second run is a no-op.
- Personal memory through the mounted workspace + symlink: the `@import` loads, the Read tool opens topic files (with `additionalDirectories`), and Claude's writes land on the host (tested 2026-10-31).
- `~/.claude/projects` in a sandbox is an sbx-owned disk (it can't be replaced); one `<key>` entry inside it can be a symlink. Transcripts and memory written through it land on the host; sbx's startup `chown -R agent:agent ~/.claude/projects` leaves the link and the host files' ownership alone (tested 2026-11-01).
- Reads through the links resolve to the mounted host paths, which `blockReadsOutsideWorkingDirectories` treats as outside the project (Bash reads prompted). `run-sandbox.sh` adds both host paths to the sandbox's `permissions.additionalDirectories`.
- `blockReadsOutsideWorkingDirectories` applies in every permission mode, bypass included, so in a sandbox it prompted for reads such as `/tmp`. `run-sandbox.sh` removes it from the sandbox's merged settings; the host keeps it. The sandbox itself is the isolation.
- `--skills` can only be set at create.

## 5. Host setup

```bash
bash ./install.sh   # from the repo root
```

Creates the links below. Anything already at a destination (other than a link into this repo) is moved to `~/.claude/.claude-config-backup-<timestamp>/` first; already-linked paths are skipped; `projects/` is skipped until it exists (it is gitignored). An existing `settings.json` is shown as a diff and replaced only on confirmation (`--yes` skips the prompt). `uninstall.sh` removes every `~/.claude/` entry that links into this repo and restores the latest backups.

| Link | → | Repo path |
|---|---|---|
| `~/.claude/<entry>`, for every top-level entry (dotfiles included, `.DS_Store` excluded) | → | `files/home/.claude/<entry>` |
| `~/.claude/skills` | → | `skills/` |
| `~/.claude/projects` | → | `projects/` |
| sbx skills store (path from `sbx skills ls --json`, `.store`; on macOS `~/Library/Application Support/com.docker.sandboxes/sandboxes/agent-skills`) | → | `skills/` |

A real sbx store is backed up as `<backup root>/sbx-skills-store`. If sbx is missing, not signed in, or has never run (the store's parent folder doesn't exist yet), the store link is skipped; run `install.sh` again after `sbx login`.

## 6. Scripts

All default to `pwd` as the project path. Run from the project root. Paths are canonicalized with `env pwd -P` (the external `pwd`: `/bin/pwd` on macOS, coreutils on NixOS, which has no `/bin/pwd`): macOS paths are case-insensitive, so `pwd` (and bash's builtin `pwd -P`) keep the typed case (`~/work/myproject`), while sbx stores the on-disk case (`MyProject`) and the sandbox's paths are case-sensitive.

### `run-sandbox.sh [--agent NAME] [path]`

`--agent` defaults to `claude`. For any other sbx agent (`codex`, `gemini`, …) only steps 1, 3 and 6 apply, and step 4 is `sbx create --name <agent>-<folder> --skills=readwrite <agent> <path>`: the agent gets the shared skills store (Codex: `~/.agents/skills`, tested 2026-11-01) and none of the Claude config. The sandbox name includes the agent, so a project can have one sandbox per agent.

1. Warns if the sbx skills store is not linked to the repo.
2. Works out the project's `<key>` and creates `~/.claude/projects/<key>/`.
3. Looks for the sandbox named `<agent>-<folder>` (sbx's default name; characters sbx rejects become `-`). Two projects with the same folder name share that name; sbx then refuses to create the second.
4. If none: `sbx create --name <agent>-<folder> --kit <repo> --skills=readwrite claude <path> <repo>/files/home/.claude/memory ~/.claude/projects/<key>` (both extra paths resolved to their real host paths) — mounted read-write at their host paths. Several sandboxes can share the personal memory mount.
5. Applies the host config (idempotent, every run): copies every entry of `files/home/.claude/` except `settings.json` and `memory/`, replacing what's in the sandbox (a sandbox must not write host config: it could add hooks that run unsandboxed on the host); symlinks `~/.claude/memory` and `~/.claude/projects/<key>` to their mounts, replacing whatever is there (if a mount is missing — a sandbox created before it was added — it warns and skips that link); merges `settings.json` on the host (sbx's copy from the sandbox, then the repo file), adds both host paths to `additionalDirectories`, adds the `uvx` shim, re-registers MCP servers (`claude mcp add-json`), adds marketplaces and installs plugins (both no-ops when already done). Files are copied via `/tmp` and then `cp` inside the sandbox, so the agent owns them (`sbx cp` keeps the host uid).
6. `sbx run --name <sandbox>`.

## 7. Operational procedures

### Adding a skill

Create `skills/<name>/SKILL.md` on the host or in any sandbox. It is live everywhere immediately (sandboxes in readonly mode see it on their next start).

### Editing `CLAUDE.md` or `settings.json`, or adding to `files/home/.claude/`

Edit the repo file. A new entry (e.g. `agents/`) needs `install.sh` re-run on the host. The host sees it immediately; sandboxes get it on the next `run-sandbox.sh`. Personal memory edits (host or sandbox) are live everywhere.

### Adding an MCP server or plugin for sandboxes

Add it to `mcpServers` / `extraKnownMarketplaces` + `enabledPlugins` in `settings.json`. On the host, register MCP servers with `claude mcp add` separately — Claude Code ignores `mcpServers` in `settings.json`.

### Validating the kit

```bash
sbx kit validate .   # from the repo root
```

## 8. Known limitations and rules

- Never run `sbx skills import`: it replaces skills in the store completely, which is now the repo.
- Any readwrite sandbox can modify or delete repo skills; git is the undo.
- Sandboxes also sync claude.ai skills into `skills/synced/`. Unchanged files are not rewritten, so concurrent writes only happen when claude.ai skills change, and with identical content.
- Each machine has its own `<key>` folders (`-Users-…` on macOS, `-home-…` on NixOS), so the same project's memory isn't shared between machines — same as Claude Code without sandboxes.
- A sandbox created before the `<key>` mount keeps its project memory and transcripts inside; recreate it.
- sbx on Linux: Docker documents Ubuntu 24.04+ on x86-64 with KVM; NixOS is unlisted. The scripts avoid macOS-only paths, but have only been run on macOS.
- Entries removed from `files/home/.claude/` are not deleted from an existing sandbox.
- The first attach to a new sandbox asks once whether to make auto mode the default permission mode; answer "No, keep bypass permissions".
- Kits are experimental in Docker Sandboxes. Re-test after `sbx` upgrades.
