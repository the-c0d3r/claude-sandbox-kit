# ADR-003: Memory Sync from Sandboxes

## Status

Superseded by ADR-007

## Context

Claude Code maintains two distinct memory stores during a session:

1. **Personal memory** (`~/.claude/memory/`) — global, cross-project patterns authored by Claude (feedback rules, user preferences, learned behaviour).
2. **Project memory** (`~/.claude/projects/<hash>/memory/`) — per-project patterns keyed by a hash of the project's absolute path.

Both are written during sandbox sessions. Without a sync mechanism, any memory Claude creates in a sandbox is lost when the sandbox is removed.

The kit (ADR-002) solves the delivery direction: it injects a snapshot of personal memory into every new sandbox at creation. It does not help with the reverse direction — getting new memory out of the sandbox.

Additionally, the question arises of whether project memory from other projects should be injected into a sandbox. It should not: a sandbox created for project A has no use for the memory Claude built up while working on project B.

## Considered approaches

### 1. Shared volume / mount

Mount the host's `~/.claude/` or `~/.claude/memory/` directly into the sandbox so writes are immediately visible on both sides.

**Rejected.** This is the same approach that failed for config delivery (ADR-002): `~/.claude/CLAUDE.md` on the host is a symlink into the repo, and symlinks cannot be followed across mount boundaries. Mounting the directory makes the host's contents readable but does not solve the write-back problem cleanly, and would expose all projects' memories to every sandbox.

### 2. Built-in Docker Sandboxes sync

Use a first-party `sbx` mechanism to sync `~/.claude/` back to the host.

**Not available.** As of this writing, Docker Sandboxes has no built-in sync for home-directory contents beyond what `sbx cp` provides.

### 3. Automatic sync via a daemon / cron

Run a background process (rsync loop or inotify watcher) inside the sandbox that continuously mirrors `~/.claude/memory/` to the host.

**Rejected.** Requires a persistent process inside the sandbox for the entire session, adds complexity, and creates race conditions if both sides write simultaneously. The memory store is append-dominant and sessions are short; a pull at the end of the session is sufficient.

### 4. Manual pull via `sbx cp` after each session

Use `sbx cp <sandbox>:<path> <local-path>` to pull memory files out of the sandbox once the session is done.

**Accepted.** `sbx cp` is the standard, supported mechanism for extracting files from a sandbox home directory. A short script wrapping it provides a repeatable, explicit step with visible output.

## Decision

### Personal memory

Pull `~/.claude/memory/` from the sandbox into the repo at `files/home/.claude/memory/` via `sbx cp`. This is the same directory the kit injects at creation, so committing the changes persists them for all future sandboxes.

Personal memory is committed to the config repo because it is global — the rules Claude authors here apply across all projects and should propagate to every subsequent sandbox.

### Project memory

Pull `~/.claude/projects/` from the sandbox and, for each project hash found, check whether the same hash exists on the host. If yes, merge the memory into the host's `~/.claude/projects/<hash>/memory/`. If no, report the hash and the manual copy command.

Project memory is **not** committed to this repo. It is project-specific state that belongs in the project's own context (or in the host's Claude Code data directory), not in the personal config. Committing it here would mix project-specific noise into the global config snapshot injected into every sandbox.

Hash matching works automatically when the project path is the same on both sides — the standard case when `sbx create` is given an absolute path that also exists on the host. When paths differ (e.g. a project that only existed inside the sandbox), the hash will not match any host project and the script reports it for manual handling.

Both scopes are handled by a single script: `sync-memory.sh`, run from the project root with no arguments.

### Sandbox identification

The script must know which sandbox to pull from. Requiring the user to look up and type the sandbox name on every sync is friction that would discourage use.

`sbx ls` output includes a WORKSPACE column (the absolute path passed to `sbx create`) as its last field. The script matches `pwd` against that column using `awk '$NF == cwd {print $1}'`, where `$NF` is always the workspace path regardless of how many space-separated tokens the PORTS column contains, and `$1` is the sandbox name. This works without any special output format flags and is robust to empty or multi-value PORTS.

An explicit sandbox name can still be passed as the first argument to override auto-detection — useful when the current directory has changed since the sandbox was created, or when multiple sandboxes share a path.

## Consequences

**Positive**

- No persistent process or daemon required.
- Personal memory changes are visible in `git status` after the sync, giving a clear review step before committing.
- Project memories from other projects are never injected into unrelated sandboxes — only personal memory travels via the kit.
- The sync is explicit and auditable: the user runs it, sees what changed, and decides whether to commit.
- No sandbox name required in the common case — running from the project root auto-detects the right sandbox via `sbx ls` WORKSPACE matching.

**Negative / accepted trade-offs**

- Sync is manual. If the user forgets to run `sync-memory.sh`, memory entries from that session are lost when the sandbox is removed. This is the same trade-off as not committing after editing a file.
- Hash-based matching only works when the project's absolute path is the same on the host and in the sandbox. Projects created exclusively inside a sandbox (no corresponding host path) produce an unmatched hash that requires manual handling.
- `sbx cp` copies files atomically but does not merge conflicts. If the same memory file was modified on both host and sandbox between creation and sync, the sandbox version overwrites the host version. This is unlikely in practice: the kit injects a snapshot at creation, and memory files are almost always appended-to rather than edited in place.

## References

- ADR-001: layered memory architecture (defines the two memory scopes)
- ADR-002: sandbox config delivery via kit (defines how memory is injected)
- `spec/SPEC-sandbox-kit.md` §8: two-scope memory table and operational procedures
- `sync-memory.sh`: implementation
