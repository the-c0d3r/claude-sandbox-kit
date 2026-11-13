# claude-sandbox-kit

A git-tracked Claude Code configuration (`CLAUDE.md`, settings, memory, skills) that is shared live with [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`). One copy of each file, in this repo: the host links to it, and every sandbox gets it on each run.

## Repo structure

```
claude-sandbox-kit/        ← this directory IS the sbx kit
├── spec.yaml              # Kit manifest
├── files/home/.claude/    # Linked into ~/.claude/; copied into sandboxes
│   ├── CLAUDE.md          # Starter instructions; imports memory/MEMORY.md
│   ├── settings.json      # Starter settings (+ MCP server and plugin lists)
│   └── memory/            # Personal memory (starts empty)
├── skills/                # Shared with the host and every sandbox (sbx skills store)
│   └── synced/            # claude.ai skills, written by Claude Code (gitignored)
├── projects/              # ~/.claude/projects: project memory + transcripts (gitignored)
├── install.sh             # Links ~/.claude entries and the sbx skills store here (with backups)
├── uninstall.sh           # Reverses install.sh, restoring backups
├── run-sandbox.sh         # Create/re-attach a sandbox for a project, applying this config
├── test/                  # test/run.sh runs the suite
├── adr/                   # Architecture decision records
└── spec/                  # Specs and plans
```

## Set up your private copy

Your instructions, memory and skills are personal, so keep them in a private copy and pull template updates into it:

```bash
git clone https://github.com/<owner>/claude-sandbox-kit.git
cd claude-sandbox-kit
git remote rename origin upstream
git remote set-url --push upstream DISABLED   # never push personal files here
git remote add origin <your private repo URL>
git push -u origin main
```

Update later with `git pull upstream main`. You own everything in `files/home/.claude/` and `skills/`; the template ships starters and doesn't change them after release, so pulls don't conflict.

## Install

Requires `jq`; the sandbox parts need sbx ≥ v0.50.

```bash
./install.sh    # from the repo root
```

It links each entry of `files/home/.claude/` into `~/.claude/`, plus `~/.claude/skills` → `skills/` and `~/.claude/projects` → `projects/` (once it exists), and points the sbx skills store at `skills/`. Anything already there is moved to `~/.claude/.claude-config-backup-<timestamp>/` first; an existing `settings.json` is shown as a diff and replaced only if you confirm (`--yes` skips the prompt). Re-running is safe.

`./uninstall.sh` removes every `~/.claude/` link into this repo and restores the backups.

To add more config (e.g. `agents/`, `commands/`), put it in `files/home/.claude/` and re-run `./install.sh`.

## Sandboxes

From the project root (`$CLAUDE_CONFIG` = path to this repo):

```bash
"$CLAUDE_CONFIG/run-sandbox.sh"
```

It creates the sandbox if there isn't one (`--kit` this repo, `--skills=readwrite`, personal memory and the project's `~/.claude/projects/<key>/` as extra workspaces), applies the config, and attaches.

| What | Shared how |
|---|---|
| Project memory + transcripts | `~/.claude/projects/<key>/` mounted and linked — live both ways; sandbox sessions show in `claude --resume` on the host |
| Personal memory | `files/home/.claude/memory/` mounted and linked — live both ways |
| Skills | `skills/` is the sbx skills store, mounted read-write — live both ways |
| `CLAUDE.md` and the rest of `files/home/.claude/` | Copied in on every run; a sandbox can't change the host's copies (it could add hooks that run outside the sandbox) |
| `settings.json` | Merged over sbx's defaults on every run |
| MCP servers, plugins | `mcpServers`, `extraKnownMarketplaces`, `enabledPlugins` in `settings.json`, installed on every run |

Other agents: `"$CLAUDE_CONFIG/run-sandbox.sh" --agent codex` (any agent `sbx create --help` lists). They get the shared skills store (at `~/.agents/skills` for Codex) and nothing else from this repo. Each agent has its own sandbox per project (`codex-<folder>`).

Details: `spec/SPEC-sandbox-kit.md`, `adr/ADR-007-shared-skills-and-project-memory.md`.

## Components

### CLAUDE.md

Loaded in full at the start of every session: communication style, engineering values, debugging approach, and rules for maintaining memory. The starter is one person's working style; edit it to yours. See `adr/ADR-001-memory-architecture.md` for what belongs here versus skills and memory.

### Skills

The template ships none. Add one by creating `skills/<name>/SKILL.md` (with `name` and `description` frontmatter) on the host or in any sandbox, or install one with `sbx skills add <owner>/<repo> --skill <name>`. It's live everywhere immediately. Only the name and description load at startup; the body loads when the task matches.

### Personal memory (`files/home/.claude/memory/`)

Narrow, evolving patterns that don't yet belong in `CLAUDE.md`. Claude Code doesn't load this folder on its own: `CLAUDE.md` imports `MEMORY.md` (the index), and topic files are read on demand (`permissions.additionalDirectories` in `settings.json` allows it).

### Project memory (`~/.claude/projects/<key>/memory/`)

Claude Code's auto memory, in its default location (the repo's `projects/`, gitignored). Shared live with the project's sandbox, together with the session transcripts.

### MCP servers

Claude Code ignores `mcpServers` in `settings.json`; `run-sandbox.sh` registers each entry in the sandbox with `claude mcp add`. On the host, register them with `claude mcp add` yourself. Example entry:

```json
"mcpServers": {
  "fetch": { "command": "uvx", "args": ["mcp-server-fetch"] }
}
```

## Tests

```bash
test/run.sh
```

Covers install/uninstall (in a throwaway `$HOME`, with `sbx` stubbed out), hardcoded personal paths, and `shellcheck` when installed. `run-sandbox.sh` needs a real sbx and isn't covered.

## Reference

- `adr/ADR-001-memory-architecture.md` — why the layered memory model was chosen
- `spec/SPEC-memory-system.md` — placement rules, promotion algorithm, skill authoring requirements
- `adr/ADR-002-sandbox-config-delivery.md` — how config first reached sandboxes (sbx kit)
- `adr/ADR-007-shared-skills-and-project-memory.md` — live sharing of skills, memory and transcripts
- `adr/ADR-008-public-template-and-private-copies.md` — template + private copy model
- `spec/SPEC-sandbox-kit.md` — kit layout, how each piece reaches a sandbox, procedures
- `spec/SPEC-public-template.md` — how the template and private copies fit together
- `spec/PLAN-public-template.md` — planned work

## License

MIT — see `LICENSE`.
