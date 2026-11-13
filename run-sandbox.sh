#!/usr/bin/env bash
# Creates or re-attaches the sbx sandbox for a project and agent (default:
# claude), with the shared skills store. For Claude it also applies this repo's
# config on every run. Details: spec/SPEC-sandbox-kit.md §6.
#
# Usage: run-sandbox.sh [--agent NAME] [project-path]
set -euo pipefail
shopt -s nullglob dotglob

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_SRC="$REPO/files/home/.claude"
SETTINGS="$HOME_SRC/settings.json"
AGENT=claude
if [ "${1:-}" = "--agent" ]; then
  AGENT="${2:?--agent needs an agent name (see sbx create --help)}"
  shift 2
fi
PROJECT="${1:-$(pwd)}"

# The repo is the --kit: keep Finder's .DS_Store files out of what gets copied.
find "$REPO" -name ".DS_Store" -delete 2>/dev/null || true

if [ ! -d "$PROJECT" ]; then
  echo "Error: project path does not exist: $PROJECT" >&2
  exit 1
fi

# Real path with on-disk case: macOS paths are case-insensitive, the sandbox's
# aren't. `env pwd -P` is the external pwd (NixOS has no /bin/pwd).
real_dir() { (cd "$1" && env pwd -P); }

PROJECT="$(real_dir "$PROJECT")"
SANDBOX="$AGENT-$(basename "$PROJECT")"   # sbx's default name
SANDBOX="${SANDBOX//[^A-Za-z0-9.-]/-}"

if [ "$AGENT" = claude ]; then
  MEMORY_DIR="$(real_dir "$HOME_SRC/memory")"
  # Claude Code's folder for the project's memory and transcripts; matches when
  # run from the repo root.
  KEY="${PROJECT//[^A-Za-z0-9]/-}"
  mkdir -p "$HOME/.claude/projects/$KEY"
  PROJECT_DATA="$(real_dir "$HOME/.claude/projects/$KEY")"
fi

# ── Claude config → sandbox ────────────────────────────────────────────────────

# Copy a host file or folder into the sandbox, replacing what's there, owned by
# the agent (sbx cp keeps the host uid, which the agent can't write to — or, in
# sticky /tmp, delete: hence root for the cleanup).
put() {
  sbx exec -u root "$SANDBOX" rm -rf /tmp/run-sandbox.tmp
  sbx cp "$1" "$SANDBOX:/tmp/run-sandbox.tmp"
  # shellcheck disable=SC2016  # expands inside the sandbox
  sbx exec "$SANDBOX" sh -c 'rm -rf "$1" && cp -R /tmp/run-sandbox.tmp "$1"' sh "$2"
}

# Point a sandbox path at a mounted host folder (extra workspaces are mounted at
# their host paths).
link_mount() {
  if ! sbx exec "$SANDBOX" test -d "$1"; then
    echo "Warning: $1 isn't mounted in $SANDBOX (created before it was); recreate it." >&2
    return
  fi
  # shellcheck disable=SC2016  # expands inside the sandbox
  sbx exec "$SANDBOX" sh -c '[ "$(readlink "$2")" = "$1" ] || { rm -rf "$2" && ln -s "$1" "$2"; }' \
    sh "$1" "$2"
}

apply_claude_config() {
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand now: $tmp is local
  trap "rm -rf '$tmp'" EXIT

  # One-way copies: a sandbox must not write host config (it could add hooks
  # that run unsandboxed on the host).
  local src
  for src in "$HOME_SRC"/*; do
    case "$(basename "$src")" in
      settings.json|memory) ;;  # merged / mounted below
      *) put "$src" "/home/agent/.claude/$(basename "$src")" ;;
    esac
  done
  link_mount "$MEMORY_DIR" /home/agent/.claude/memory
  link_mount "$PROJECT_DATA" "/home/agent/.claude/projects/$KEY"

  # Repo settings over sbx's own (objects merge, everything else is
  # replaced). The mounts count as inside the project. The read block is
  # dropped: it prompts even in bypass mode, and the sandbox is the isolation.
  sbx cp "$SANDBOX:/home/agent/.claude/settings.json" "$tmp/sandbox.json"
  jq -s --arg mem "$MEMORY_DIR" --arg data "$PROJECT_DATA" '
    (.[0] * .[1])
    | .permissions.additionalDirectories += [$mem, $data]
    | .permissions.additionalDirectories |= unique
    | del(.permissions.blockReadsOutsideWorkingDirectories)
  ' "$tmp/sandbox.json" "$SETTINGS" > "$tmp/merged.json"
  put "$tmp/merged.json" /home/agent/.claude/settings.json

  # The image ships uv but not uvx.
  # shellcheck disable=SC2016  # expands inside the sandbox
  sbx exec -u root "$SANDBOX" sh -c 'command -v uvx >/dev/null || {
    printf "#!/bin/sh\nexec uv tool run \"\$@\"\n" > /usr/local/bin/uvx && chmod 755 /usr/local/bin/uvx; }'

  # Claude Code ignores mcpServers in settings.json. Re-added each run so repo
  # changes apply.
  for name in $(jq -r '.mcpServers // {} | keys[]' "$SETTINGS"); do
    sbx exec "$SANDBOX" claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
    sbx exec "$SANDBOX" claude mcp add-json --scope user "$name" \
      "$(jq -c --arg n "$name" '.mcpServers[$n]' "$SETTINGS")" >/dev/null
  done

  # Plugins aren't auto-installed; both commands are no-ops when already done.
  for repo in $(jq -r '.extraKnownMarketplaces // {} | .[].source.repo' "$SETTINGS"); do
    sbx exec "$SANDBOX" claude plugin marketplace add "$repo" >/dev/null 2>&1 \
      || echo "Warning: marketplace $repo: add failed" >&2
  done
  for plugin in $(jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' "$SETTINGS"); do
    sbx exec "$SANDBOX" claude plugin install "$plugin" >/dev/null 2>&1 \
      || echo "Warning: plugin $plugin: install failed" >&2
  done
}

# ── Main ───────────────────────────────────────────────────────────────────────

# Same store lookup as install.sh / uninstall.sh — keep in sync.
STORE="$(sbx skills ls --json 2>/dev/null | jq -r '.store // empty' || true)"
if [ -z "$STORE" ] || [ "$(readlink "$STORE" 2>/dev/null)" != "$REPO/skills" ]; then
  echo "Warning: sbx skills store is not linked to $REPO/skills — run install.sh." >&2
fi

if sbx ls --json | jq -e --arg n "$SANDBOX" 'any(.[]; .name == $n)' >/dev/null; then
  echo "Found sandbox: $SANDBOX"
elif [ "$AGENT" = claude ]; then
  sbx create --name "$SANDBOX" --kit "$REPO" --skills=readwrite claude \
    "$PROJECT" "$MEMORY_DIR" "$PROJECT_DATA"
else
  sbx create --name "$SANDBOX" --skills=readwrite "$AGENT" "$PROJECT"
fi

if [ "$AGENT" = claude ]; then
  echo "Applying config to $SANDBOX"
  apply_claude_config
fi

sbx run --name "$SANDBOX"
