# ADR-007: Shared Skills, Memory and Transcripts for Sandboxes

## Status

Accepted. Supersedes ADR-003; amends ADR-002 (skills and settings no longer rely on kit file injection).

## Context

ADR-002 delivered all config by copying `files/home/.claude/` into each sandbox at create; ADR-003 pulled memory back with `sync-memory.sh` after each session. By sbx v0.50 this had four problems:

- **Export step.** Memory written in a sandbox reached the host only if `sync-memory.sh` ran, and concurrent sandboxes overwrote each other's copies (last sync wins). Transcripts never left the sandbox.
- **Skills one-way.** Skills installed inside a sandbox stayed there. The kit also copied Claude Code's synced claude.ai skills (`skills/synced/`, 11 MB incl. fonts), which crashed kit injection in sbx v0.37.
- **Settings never applied.** sbx writes its own `settings.json` at create, replacing the kit's copy. Claude Code also ignores `mcpServers` in `settings.json` and does not auto-install plugins.
- **Personal memory never loaded.** Claude Code's auto memory is per project only; `~/.claude/memory/` was injected but not read.

sbx v0.50 added a shared skills store that can be mounted read-write (`--skills=readwrite`), and `sbx create` mounts extra host folders read-write at their host paths.

## Decision

- **Skills** live in `skills/` at the repo root. `~/.claude/skills` and the sbx skills store both symlink to it; sandboxes are created with `--skills=readwrite`, so a skill added anywhere lands in the repo.
- **Project memory and transcripts** stay in Claude Code's default location, `~/.claude/projects/<key>/` (the repo's gitignored `projects/`). `run-sandbox.sh` mounts the project's `<key>` folder as an extra workspace at create, and `run-sandbox.sh` symlinks the sandbox's `~/.claude/projects/<key>` to it. sbx keeps `~/.claude/projects` on its own disk, so only that one entry is linked. Nothing is written into projects.
- **Personal memory** is mounted the same way: `files/home/.claude/memory` as an extra workspace, `~/.claude/memory` symlinked to it. `CLAUDE.md` imports `@~/.claude/memory/MEMORY.md` so it loads.
- **Reads under `blockReadsOutsideWorkingDirectories`:** the host's `settings.json` lists `~/.claude/memory` and `~/.claude/projects` in `permissions.additionalDirectories`; `run-sandbox.sh` adds the two mounted host paths in the sandbox, since the links resolve there.
- **Settings, MCP servers, plugins** are applied by `run-sandbox.sh` after create and on every attach: deep-merge `settings.json` over sbx's defaults, `claude mcp add` per `mcpServers` entry (with a `uvx` shim), marketplace add + plugin install.
- **`CLAUDE.md`** stays a one-way copy (kit at create, re-copied on attach).
- `sync-memory.sh` is removed. Sandboxes created before this decision were deleted and recreated with `run-sandbox.sh` (2026-10-31).

## Alternatives Considered

- **`autoMemoryDirectory` → `<project>/.claude/memory/`, set per project in `.claude/settings.local.json`.** Implemented briefly, then dropped: it writes into every project, and with `blockReadsOutsideWorkingDirectories` Claude Code ignores the setting when the project isn't a git repo or the file is tracked — memory silently switches off. Transcripts stayed unshared.
- **Replacing the sandbox's whole `~/.claude/projects` with the mount.** Not possible: it is an sbx-owned disk.
- **Kit `host-mount@1` + `sbx create --mount`.** Works, but only with v3 kits: needs the v3 `sbx/claude` kit via the `kit.shortcuts.claude` setting, a buildx docker-container builder for local kits, and a credential binding. Extra workspaces do the same with the v2 kit.
- **Mounting `CLAUDE.md` / `settings.json` read-write.** Rejected: a sandbox could add hooks that run on the unsandboxed host.
- **Keeping kit-copied skills plus sync.** Rejected: skills installed in a sandbox still wouldn't reach the repo, and the copy carried `synced/`.

## Consequences

- No export step: memory, transcripts and skills are on the host as soon as they are written. Sandbox sessions appear in `claude --resume` on the host; resuming one there runs it outside the sandbox.
- Any sandbox can modify or delete repo skills, write its project's memory and transcripts, and write personal memory — which every host session loads. Git is the undo for skills and personal memory; memory-promotion is the review gate for anything promoted further. Project memory is not in git.
- `run-sandbox.sh` must compute Claude Code's project key (project path, every non-alphanumeric character → `-`); a mismatch would mount the wrong folder. It uses the folder it is run in, so it must be run from the repo root, where that matches Claude Code's git-root key.
- Sandboxes also sync claude.ai skills into `skills/synced/`; unchanged files are not rewritten, so concurrent writes only occur on real changes, with identical content.
- `--skills` and workspaces are create-only: a sandbox created without `--skills=readwrite` or the memory mounts must be recreated.
- Never run `sbx skills import` — it replaces skills in the store, which is now the repo.
