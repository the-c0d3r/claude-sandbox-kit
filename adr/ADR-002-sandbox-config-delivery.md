# ADR-002: Sandbox Configuration Delivery via sbx Kit

## Status

Accepted; amended by ADR-007 (skills via the sbx skills store, settings/MCP/plugins applied by `run-sandbox.sh`)

## Context

Claude Code sandboxes (`sbx`) run in isolated containers. Each sandbox gets a fresh `~/.claude/` directory with only basic generated settings — none of the personal configuration that Claude Code uses on the host (`CLAUDE.md`, skills, `settings.json`, memory). Without a delivery mechanism, every sandbox starts with no instructions, no skills, and default settings.

Four approaches were evaluated:

1. **Mount `~/.claude/`** — pass `~/.claude` as an extra path to `sbx create`. The host's `~/.claude/` is accessible inside the sandbox at `/Users/<user>/.claude`, and `setup.sh` creates symlinks from `/home/agent/.claude/` to it.

2. **Mount `claude-config/`** — pass the config repo as an extra path. `setup.sh` creates symlinks from `/home/agent/.claude/` directly to the repo files.

3. **SessionStart hook** — add a hook to `settings.json` that runs `setup.sh` automatically at session start.

4. **sbx kit** — declare the config as a kit artifact (`spec.yaml` + `files/`) that Docker Sandboxes injects into the sandbox at creation.

## Problems with the rejected approaches

**Mounting `~/.claude/`** failed because `~/.claude/CLAUDE.md` on the host is itself a symlink into the `claude-config` repo, and symlinks cannot be followed across mount boundaries. The sandbox sees a dangling symlink.

**Mounting `claude-config/`** required a manual bootstrap command after every sandbox creation (`bash /path/to/setup.sh`), and only worked for projects whose path happened to be under the synced folder holding the repo. Projects outside that tree had no access to the script.

**SessionStart hook** appeared viable but failed in practice: the sandbox's `settings.json` is freshly generated at creation time and is not copied from the host's `settings.json`. Hooks in the host's config have no effect inside sandboxes.

## Decision

Use the **sbx kit mechanism**. The `claude-config` repo is structured as a kit artifact — `spec.yaml` at the root declares it as a mixin, and `files/home/.claude/` contains the files to inject. Sandboxes are created with `--kit /path/to/claude-config`, which causes Docker Sandboxes to copy the kit files into the sandbox's `~/.claude/` at creation time.

The `files/home/.claude/` subtree serves a dual purpose: it is the kit's injection payload for sandboxes, and it is the source of truth for the host's `~/.claude/` symlinks (managed by `setup.sh`). There is one copy of each file, used by both surfaces.

## Consequences

**Positive**

- No mounts, no manual bootstrap, no hooks. The kit creation command is wrapped in `run-sandbox.sh`, which re-attaches to an existing sandbox if one exists for the current directory and creates a new one otherwise. It defaults to `pwd` and resolves the kit path from its own location — the user never needs to remember or type the full kit path.
- Config is injected at creation, not discovered at session start — the sandbox has correct settings from the first command.
- The kit and host symlinks share the same source files under `files/home/.claude/`, eliminating the risk of the two drifting apart.
- The kit is versioned alongside the config it delivers.

**Negative / accepted trade-offs**

- Kit files are injected as a snapshot at creation. `run-sandbox.sh` mitigates this: on re-attach it computes a content hash of `files/home/.claude/` (excluding `memory/`), compares it against a hash stored in the sandbox at `~/.claude/.kit-hash`, and pushes changed files via `sbx cp` before attaching. Files *removed* from the kit are not deleted from existing sandboxes — only a recreate clears them.
- The `files/home/.claude/` path is unintuitive as the canonical location for `CLAUDE.md` and skills. It is a consequence of structuring the repo to be directly usable as a kit artifact. The README and `setup.sh` make this explicit.
- The kit mechanism is marked experimental in Docker Sandboxes as of this writing. If the spec changes, `spec.yaml` may need updating.

## References

- Docker Sandboxes kit reference: `https://docs.docker.com/ai/sandboxes/customize/kit-reference/`
- Docker Sandboxes kit examples: `https://docs.docker.com/ai/sandboxes/customize/kit-examples/`
- ADR-001: memory architecture (the content being delivered is specified there)
- `spec/SPEC-sandbox-kit.md`: concrete file layout and operational procedures
