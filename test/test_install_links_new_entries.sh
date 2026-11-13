#!/usr/bin/env bash
# Layer 2: a new entry added to files/home/.claude/ (here agents/) is linked
# by install.sh and removed by uninstall.sh with no list to update. Runs
# against a throwaway copy of the scripts so the real repo isn't changed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$HOME_DIR" "$TMP_REPO"' EXIT

fail=0
cp "$REPO/install.sh" "$REPO/uninstall.sh" "$TMP_REPO/"
mkdir -p "$TMP_REPO/files/home/.claude/agents" "$TMP_REPO/skills"
printf 'agent\n' > "$TMP_REPO/files/home/.claude/agents/reviewer.md"

HOME="$HOME_DIR" bash "$TMP_REPO/install.sh" --yes > /dev/null
assert_symlink_to "$HOME_DIR/.claude/agents" "$TMP_REPO/files/home/.claude/agents" "new agents/ entry linked" || fail=1

HOME="$HOME_DIR" bash "$TMP_REPO/uninstall.sh" > /dev/null
if [ -e "$HOME_DIR/.claude/agents" ] || [ -L "$HOME_DIR/.claude/agents" ]; then
  echo "FAIL: agents/ still present after uninstall"
  fail=1
fi

exit "$fail"
