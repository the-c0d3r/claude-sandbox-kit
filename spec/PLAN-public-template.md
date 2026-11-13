# PLAN: Public Template

Publish this setup as a public GitHub template with nothing personal in it. Its main purpose is the automation layer on top of Docker Sandboxes (`sbx`). Anyone (the author included) clones it into a private copy and uses git to track their own instructions, memory, settings and skills, while still pulling template updates.

Architecture: `ADR-008`, `SPEC-public-template.md`. Sandbox mechanics: `ADR-007`, `SPEC-sandbox-kit.md`.

## Decided

### Two repos

| Repo | Visibility | Contents |
|---|---|---|
| `claude-sandbox-kit` (template) | Public, fresh git history | Scripts, docs, tests, starter files |
| Private copy | Private (GitHub private or local) | Template files + everything personal |

- The private copy is a clone of the template with remotes `upstream` = public (fetch only: `git remote set-url --push upstream DISABLED`) and `origin` = private.
- Template updates: `git pull upstream main`.
- Template work is done in a separate clone of the public repo, never moved out of the private copy (personal content could leak with it).
- The public repo starts with fresh history, so no personal file from the author's own copy is in it.

### Ownership — what makes `git pull upstream` conflict-free

| Owner | Files | Rule |
|---|---|---|
| Template | Scripts, `spec.yaml`, docs, tests | Users don't edit them |
| User | Everything in `files/home/.claude/` (`CLAUDE.md`, `settings.json`, `memory/`, agents, commands, `sandbox-mcp.json`, …), `skills/`, `skills.lock.json`, `projects/*/memory/` | Template ships starters/empty files and never changes them after the first release; new defaults are announced in the README/changelog |

### Skills

- The template ships **no skills**; all skills are opt-in.
- The author's skills move to a **separate public skills repo**, all skills in one repo, one folder each (`skills/<name>/SKILL.md`, the layout of `anthropics/skills`). Anyone installs only the ones they want: `sbx skills add <owner>/<repo> --skill <name>`; `sbx skills update` refreshes them.

| Type | Where | In git (private copy)? | How it's replicated |
|---|---|---|---|
| Created locally (on the host or in a sandbox) | `skills/<name>/` | Yes | Git |
| From other repos (incl. the author's skills repo) | `skills/<name>/` | No | sbx's lock file (repository + commit per skill), tracked in the private copy |
| From plugins | Plugin cache | No | `enabledPlugins` + `extraKnownMarketplaces` in `settings.json` |
| claude.ai synced | `skills/synced/` | No (gitignored) | Claude Code re-syncs them |

#### Skills from other repos: the lock file

sbx records every `sbx skills add` in a lock file, `<sbx data>/sandboxes/agent-skills-metadata/sources.json` (`{"version":1,"skills":{"<name>":{"repository":…,"commit":…}}}`), and writes only the skill folder into the store (`skills/`). The private copy tracks a **copy** of it as `skills.lock.json`; sbx refuses a symlinked lock ("not a regular file", tested 2026-11-01).

| Step | Direction | What happens |
|---|---|---|
| `install.sh` (new machine) | repo → sbx | Copy `skills.lock.json` over sbx's lock, then `sbx skills update`: every listed skill whose folder is missing is downloaded (tested) |
| `run-sandbox.sh` (every run) | sbx → repo | Copy sbx's lock to `skills.lock.json`; regenerate `skills/.gitignore` with one `/<name>/` line per listed skill |

On a machine, sbx is the source of truth; `git diff skills.lock.json` shows what was added or removed. `sbx skills update` installs the **latest** version, not the recorded commit — a rebuild gets the same skills, not necessarily the same versions.

How a user works with it:

```bash
sbx skills add <owner>/<skills-repo> --skill pdf   # install one skill
sbx skills update                                 # refresh all of them
sbx skills rm pdf --force                         # remove one
./run-sandbox.sh                                  # records the change in skills.lock.json
git add skills.lock.json skills/.gitignore && git commit -m "skills: add pdf"
# new machine: clone the private copy, ./install.sh → skills are downloaded again
```

### Starter `CLAUDE.md`

The template ships the author's `CLAUDE.md` (scrubbed) as a sample. When an existing `CLAUDE.md` is found, install offers to keep it, take the template's, or merge — the merge option prints a ready-to-paste prompt for an AI assistant to combine the two files, with no hand merging.

### Project memory in git

Track `projects/<key>/memory/`; ignore transcripts and session data in `projects/` (`*.jsonl`, session folders).

### Install adopts an existing setup

`install.sh` on a machine that already has a `~/.claude/`:

- Copies existing skill folders into `skills/` (name clashes reported, never overwritten).
- `CLAUDE.md`: keep / take template / merge via AI prompt (above).
- Uses the existing `settings.json` and memory in place of the starters; merges into settings the keys the setup needs (memory read access, official marketplace).
- Backs up the originals as today; `uninstall.sh` restores them.

### Linked paths come from the folder, not a fixed list

Everything placed in `files/home/.claude/` is linked into `~/.claude/` and copied into sandboxes (e.g. adding `agents/` just works), replacing the hard-coded `MANAGED` list.

### ADRs and specs ship, scrubbed of personal details

### Sandbox MCP servers

A sandbox-only list in the user's files, `files/home/.claude/sandbox-mcp.json`, replaces the `mcpServers` key in `settings.json` (which Claude Code ignores):

```json
{
  "local":   { "nixos": { "command": "uvx", "args": ["mcp-nixos"] },
               "fetch": { "command": "uvx", "args": ["mcp-server-fetch"] } },
  "gateway": ["notion"]
}
```

- `local`: local tools, run **inside** the sandbox (registered there with `claude mcp add` on every `run-sandbox.sh`), so they stay sandboxed.
- `gateway`: names registered on the host with `sbx mcp add --url …`; `run-sandbox.sh` passes them as `--static-mcp` when it creates a sandbox, so logins stay on the host.
- Never put a local command server in `gateway`: the gateway runs those on the host with full permissions, outside the sandbox.

How a user works with it:

```bash
# local tool: add it under "local", then
./run-sandbox.sh                         # registered inside the sandbox on this run

# remote service with a login (once per machine):
sbx mcp add notion --url https://mcp.notion.com/mcp
sbx mcp auth notion                      # OAuth in the browser; token stays on the host
# add "notion" under "gateway", then:
./run-sandbox.sh                         # new sandboxes start with it
sbx mcp load <sandbox> notion            # existing sandboxes (--static-mcp is create-only)

# check inside the sandbox's Claude: /mcp
```

Untested here: the gateway path end to end (`sbx mcp add` → `auth` → `--static-mcp`/`load` → tools visible in the sandbox), and the exact `sbx mcp load` argument order.

#### Findings behind this

MCP does work in sandboxes, in two ways:

| Way | How | Where the server runs | Tested here |
|---|---|---|---|
| Inside the sandbox | `claude mcp add` in the sandbox (what `run-sandbox.sh` does now, with a `uvx` shim) | In the sandbox, under its network policy | Yes: `nixos`, `fetch` connected |
| sbx MCP gateway | `sbx mcp add NAME --url …` or `--command …` on the host; attached with `sbx create --static-mcp NAME` or `sbx mcp load`; the sandbox sees one `mcp-gateway` endpoint | Remote URL servers: remote. `--command` (local stdio) servers: **on the host, with full permissions** | Only the default `mcp-gateway` entry, seen in every sandbox |

The gateway keeps OAuth tokens and secrets on the host; without `--static-mcp`, it starts in a dynamic mode where the agent can find and add servers itself. Sources: [Docker: MCP gateway](https://docs.docker.com/ai/sandboxes/mcp-gateway/), `sbx mcp add --help`.


## Work items

### Template repo
- [x] Data-driven linking from `files/home/.claude/` (`install.sh`, `uninstall.sh`, `run-sandbox.sh`)
- [ ] Adopt-on-install for skills, settings, memory; `CLAUDE.md` keep/take/merge with the AI merge prompt; tests for each
- [ ] Skills lock: `install.sh` copies `skills.lock.json` to sbx and runs `sbx skills update`; `run-sandbox.sh` copies sbx's lock back and regenerates `skills/.gitignore`
- [ ] `.gitignore`: track `projects/*/memory/`, ignore transcripts/session data
- [x] Starter files: scrubbed `CLAUDE.md`, `settings.json` (safe defaults, no bypass mode), empty `memory/MEMORY.md`
- [ ] Starter `sandbox-mcp.json` with the `local` examples
- [ ] `run-sandbox.sh`: read `sandbox-mcp.json` (`local` → `claude mcp add` in the sandbox, `gateway` → `--static-mcp` at create); drop `mcpServers` from `settings.json`
- [ ] Test the gateway path end to end with one remote server
- [x] Public README: install, private-copy setup (remotes, push-disable), updating, uninstall, skill types
- [ ] README: link the recommended skills repo once it exists
- [x] `LICENSE` (MIT)
- [x] Scrub ADRs/specs and shipped files of personal paths/details; `test_no_hardcoded_paths.sh` covers docs
- [x] Rewrite `SPEC-public-template.md` and an ADR (ADR-008) for this model; drop subtree pieces

### Skills repo
- [ ] Create the public skills repo (`skills/<name>/SKILL.md` per skill, README listing them with `sbx skills add` commands)
- [ ] Move the author's skills there; check each for personal details first

### Release
- [ ] Create the public template repo with fresh history from the template-owned + starter files only
- [ ] Fresh-clone test: clone → `install.sh` on an empty `~/.claude` and on one with existing skills/settings/`CLAUDE.md` → `uninstall.sh` restores; `run-sandbox.sh` in a throwaway project (copies a folder entry, e.g. `agents/`)

## Advice

- Run a personal-data check before every push to the public repos: grep for home paths, names, memory files. A pre-push hook in the template and skills clones could enforce it.
- Keep the first release small; data-driven linking and adopt-on-install are the parts adopters hit first.
- `sbx skills` is marked experimental; re-test the lock-file approach after sbx upgrades.
