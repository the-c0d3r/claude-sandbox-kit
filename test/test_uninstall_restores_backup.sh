#!/usr/bin/env bash
# Layer 2: uninstall removes our symlink and restores the most recent
# backup, ending up exactly where the user started.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
trap 'rm -rf "$HOME_DIR"' EXIT

fail=0
mkdir -p "$HOME_DIR/.claude"
printf 'pre-existing user CLAUDE.md\n' > "$HOME_DIR/.claude/CLAUDE.md"

HOME="$HOME_DIR" bash "$REPO/install.sh" --yes > /dev/null
HOME="$HOME_DIR" bash "$REPO/uninstall.sh" > /dev/null

assert_not_symlink "$HOME_DIR/.claude/CLAUDE.md" "CLAUDE.md no longer a symlink after uninstall" || fail=1
assert_file_content "$HOME_DIR/.claude/CLAUDE.md" "pre-existing user CLAUDE.md" "CLAUDE.md content restored" || fail=1

# Paths with no pre-existing file (no backup to restore) are left absent.
assert_not_symlink "$HOME_DIR/.claude/skills" "skills no longer a symlink" || fail=1
if [ -e "$HOME_DIR/.claude/skills" ]; then
  echo "FAIL: skills should be left absent (no backup existed), but it exists"
  fail=1
fi

exit "$fail"
