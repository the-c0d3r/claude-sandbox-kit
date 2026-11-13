#!/usr/bin/env bash
# Layer 2: a pre-existing real file at a managed path gets moved into a
# timestamped backup dir, and the destination becomes a symlink.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
trap 'rm -rf "$HOME_DIR"' EXIT

fail=0
mkdir -p "$HOME_DIR/.claude"
printf 'pre-existing user CLAUDE.md\n' > "$HOME_DIR/.claude/CLAUDE.md"

HOME="$HOME_DIR" bash "$REPO/install.sh" --yes > /dev/null

assert_symlink_to "$HOME_DIR/.claude/CLAUDE.md" "$REPO/files/home/.claude/CLAUDE.md" "CLAUDE.md now linked" || fail=1

backup_file="$(find "$HOME_DIR/.claude" -maxdepth 2 -path '*/.claude-config-backup-*/CLAUDE.md' | head -1)"
if [ -z "$backup_file" ]; then
  echo "FAIL: no backup found for pre-existing CLAUDE.md"
  fail=1
else
  assert_file_content "$backup_file" "pre-existing user CLAUDE.md" "backup preserves original content" || fail=1
fi

exit "$fail"
