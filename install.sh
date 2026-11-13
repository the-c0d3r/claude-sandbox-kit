#!/usr/bin/env bash
# Idempotent installer (spec/SPEC-sandbox-kit.md §5).
# Symlinks this repo's managed paths into ~/.claude/, and the sbx skills store
# to skills/, backing up whatever was there first. Safe to re-run —
# already-linked paths are skipped.
set -euo pipefail
shopt -s nullglob dotglob
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
YES=0
[ "${1:-}" = "--yes" ] && YES=1

# Every top-level entry of files/home/.claude/, plus skills/ and projects/ from
# the repo root (sbx copies files/home/.claude/ into new sandboxes, which must
# not get those two). projects/ is skipped until it exists.
MANAGED=()
for src in "$REPO/files/home/.claude"/*; do
  [ "$(basename "$src")" = .DS_Store ] || MANAGED+=("$src")
done
MANAGED+=("$REPO/skills" "$REPO/projects")

BACKUP_ROOT="$CLAUDE_DIR/.claude-config-backup-$(date +%Y%m%d%H%M%S)"
linked=()
backed_up=()
skipped=()

# Same check as uninstall.sh — keep in sync.
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

mkdir -p "$CLAUDE_DIR"

for src in "${MANAGED[@]}"; do
  label="$(basename "$src")"
  dest="$CLAUDE_DIR/$label"

  if [ ! -e "$src" ]; then
    skipped+=("$label (not present in this repo)")
    continue
  fi

  if is_symlink_into_repo "$dest"; then
    skipped+=("$label (already linked)")
    continue
  fi

  if [ "$label" = "settings.json" ] && [ -e "$dest" ]; then
    echo "=== settings.json already exists at $dest — diff against this repo's version ==="
    diff -u "$dest" "$src" || true
    if [ "$YES" -ne 1 ]; then
      read -r -p "Overwrite $dest with the symlinked version? [y/N] " ans || ans=""
      if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        skipped+=("settings.json (declined)")
        continue
      fi
    fi
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mkdir -p "$BACKUP_ROOT"
    mv "$dest" "$BACKUP_ROOT/$label"
    backed_up+=("$label -> $BACKUP_ROOT/$label")
  fi

  ln -s "$src" "$dest"
  linked+=("$label")
done

# sbx shares its skills store with sandboxes (run-sandbox.sh uses
# --skills=readwrite), so pointing it at skills/ makes skills installed in a
# sandbox land here. sbx reports the store's path, which differs per OS; its
# parent exists once sbx has run. Same lookup as uninstall.sh / run-sandbox.sh.
STORE="$(sbx skills ls --json 2>/dev/null | jq -r '.store // empty' 2>/dev/null || true)"
if [ -z "$STORE" ] || [ ! -d "$(dirname "$STORE")" ]; then
  skipped+=("sbx skills store (sbx not installed, not signed in, or never run — re-run after 'sbx login')")
elif is_symlink_into_repo "$STORE"; then
  skipped+=("sbx skills store (already linked)")
else
  if [ -e "$STORE" ] || [ -L "$STORE" ]; then
    mkdir -p "$BACKUP_ROOT"
    mv "$STORE" "$BACKUP_ROOT/sbx-skills-store"
    backed_up+=("sbx skills store -> $BACKUP_ROOT/sbx-skills-store")
  fi
  ln -s "$REPO/skills" "$STORE"
  linked+=("sbx skills store")
fi

echo
echo "Linked:    ${linked[*]:-none}"
echo "Backed up: ${backed_up[*]:-none}"
echo "Skipped:   ${skipped[*]:-none}"
if [ ${#backed_up[@]} -gt 0 ]; then
  echo "Backup root: $BACKUP_ROOT"
fi
exit 0
