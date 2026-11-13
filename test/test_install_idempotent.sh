#!/usr/bin/env bash
# Layer 2: re-running install.sh on an already-linked $HOME is a no-op --
# no new backups, no duplicate work, links still valid.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
trap 'rm -rf "$HOME_DIR"' EXIT

fail=0
HOME="$HOME_DIR" bash "$REPO/install.sh" --yes > /dev/null

second_run_output="$(HOME="$HOME_DIR" bash "$REPO/install.sh" --yes)"
second_run_exit=$?

if [ "$second_run_exit" -ne 0 ]; then
  echo "FAIL: second install.sh run exited $second_run_exit"
  fail=1
fi

if ! echo "$second_run_output" | grep -q "already linked"; then
  echo "FAIL: second run did not report paths as already linked"
  echo "$second_run_output"
  fail=1
fi

if ! echo "$second_run_output" | grep -qi "^Backed up: *none$"; then
  echo "FAIL: second run created a backup, expected none"
  echo "$second_run_output"
  fail=1
fi

backup_count="$(find "$HOME_DIR/.claude" -maxdepth 1 -name '.claude-config-backup-*' | wc -l)"
if [ "$backup_count" -ne 0 ]; then
  echo "FAIL: expected 0 backup dirs after idempotent re-run, found $backup_count"
  fail=1
fi

assert_symlink_to "$HOME_DIR/.claude/CLAUDE.md" "$REPO/files/home/.claude/CLAUDE.md" "CLAUDE.md still valid after re-run" || fail=1

exit "$fail"
