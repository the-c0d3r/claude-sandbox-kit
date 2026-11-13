#!/usr/bin/env bash
# Reverses install.sh (spec/SPEC-sandbox-kit.md §5). Removes every entry of
# ~/.claude/ that is a symlink pointing into this repo — a file the user
# created after install, or a symlink elsewhere, is left alone. Restores the
# most recent backup for each removed path, if one exists.
set -euo pipefail
shopt -s nullglob dotglob
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

removed=()
restored=()
left_absent=()

# Most recent backup of $1 (path relative to a backup root), or empty.
latest_backup() {
  local b found=""
  for b in "$CLAUDE_DIR"/.claude-config-backup-*; do
    [ -e "$b/$1" ] && found="$b/$1"
  done
  printf '%s' "$found"
}

# Same check as install.sh — keep in sync.
is_symlink_into_repo() {
  local dest="$1"
  [ -L "$dest" ] || return 1
  local target resolved
  target="$(readlink "$dest")"
  case "$target" in
    /*) resolved="$target" ;;
    *) resolved="$(cd "$(dirname "$dest")" && cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")" ;;
  esac
  [[ "$resolved" == "$REPO" || "$resolved" == "$REPO"/* ]]
}

for dest in "$CLAUDE_DIR"/*; do
  is_symlink_into_repo "$dest" || continue
  name="$(basename "$dest")"

  rm "$dest"
  removed+=("$name")

  latest="$(latest_backup "$name")"

  if [ -n "$latest" ]; then
    mv "$latest" "$dest"
    restored+=("$name <- $latest")
  else
    left_absent+=("$name")
  fi
done

# sbx skills store (install.sh links it to skills/ and backs up a real store
# as <backup root>/sbx-skills-store). Same lookup as install.sh — keep in sync.
STORE="$(sbx skills ls --json 2>/dev/null | jq -r '.store // empty' 2>/dev/null || true)"
if [ -n "$STORE" ] && is_symlink_into_repo "$STORE"; then
  rm "$STORE"
  removed+=("sbx skills store")
  latest="$(latest_backup sbx-skills-store)"
  if [ -n "$latest" ]; then
    mv "$latest" "$STORE"
    restored+=("sbx skills store <- $latest")
  else
    left_absent+=("sbx skills store")
  fi
fi

echo
echo "Removed:     ${removed[*]:-none}"
echo "Restored:    ${restored[*]:-none}"
echo "Left absent: ${left_absent[*]:-none}"
