#!/usr/bin/env bash
# Layer 2: settings.json is higher-risk (§6) -- confirm both sides of the
# gate: --yes overwrites non-interactively, and a declined/non-interactive
# prompt leaves the user's file untouched without crashing the script.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

fail=0

# Case 1: --yes bypasses the prompt and overwrites.
HOME_DIR_YES="$(fresh_home)"
mkdir -p "$HOME_DIR_YES/.claude"
printf '{"custom": true}\n' > "$HOME_DIR_YES/.claude/settings.json"
HOME="$HOME_DIR_YES" bash "$REPO/install.sh" --yes > /dev/null
assert_symlink_to "$HOME_DIR_YES/.claude/settings.json" "$REPO/files/home/.claude/settings.json" "--yes overwrites settings.json" || fail=1
rm -rf "$HOME_DIR_YES"

# Case 2: no --yes, stdin closed (non-interactive decline) -- must not
# crash, must leave settings.json exactly as the user had it, and must
# still process the other managed paths.
HOME_DIR_NO="$(fresh_home)"
mkdir -p "$HOME_DIR_NO/.claude"
printf '{"custom": true}\n' > "$HOME_DIR_NO/.claude/settings.json"
run_exit=0
HOME="$HOME_DIR_NO" bash "$REPO/install.sh" < /dev/null > /dev/null || run_exit=$?
if [ "$run_exit" -ne 0 ]; then
  echo "FAIL: install.sh crashed ($run_exit) on non-interactive settings.json decline"
  fail=1
fi
assert_not_symlink "$HOME_DIR_NO/.claude/settings.json" "declined settings.json stays a real file" || fail=1
assert_file_content "$HOME_DIR_NO/.claude/settings.json" '{"custom": true}' "declined settings.json content unchanged" || fail=1
assert_symlink_to "$HOME_DIR_NO/.claude/CLAUDE.md" "$REPO/files/home/.claude/CLAUDE.md" "other paths still installed despite decline" || fail=1
rm -rf "$HOME_DIR_NO"

exit "$fail"
