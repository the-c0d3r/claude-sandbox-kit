#!/usr/bin/env bash
# Layer 2: uninstall must only remove a managed path if it is CURRENTLY a
# symlink into this repo. A symlink pointing elsewhere, and a real file
# the user created (whether or not install.sh ever ran), must survive.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
trap 'rm -rf "$HOME_DIR"' EXIT

fail=0
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/elsewhere"

# A symlink into some unrelated location, not this repo.
printf 'unrelated target\n' > "$HOME_DIR/elsewhere/CLAUDE.md"
ln -s "$HOME_DIR/elsewhere/CLAUDE.md" "$HOME_DIR/.claude/CLAUDE.md"

# A plain file the user created for a path install.sh never touched.
printf 'user plugins content\n' > "$HOME_DIR/.claude/plugins"

HOME="$HOME_DIR" bash "$REPO/uninstall.sh" > /dev/null

if [ ! -L "$HOME_DIR/.claude/CLAUDE.md" ]; then
  echo "FAIL: foreign symlink at CLAUDE.md was removed, expected untouched"
  fail=1
else
  actual="$(readlink "$HOME_DIR/.claude/CLAUDE.md")"
  if [ "$actual" != "$HOME_DIR/elsewhere/CLAUDE.md" ]; then
    echo "FAIL: foreign symlink target changed -- now points to $actual"
    fail=1
  fi
fi

assert_not_symlink "$HOME_DIR/.claude/plugins" "user-created plugins file untouched" || fail=1
assert_file_content "$HOME_DIR/.claude/plugins" "user plugins content" "user-created plugins content untouched" || fail=1

exit "$fail"
