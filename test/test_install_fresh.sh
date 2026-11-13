#!/usr/bin/env bash
# Layer 2: fresh install into an empty $HOME links every entry of
# files/home/.claude/, plus skills/ (and projects/ when present), straight to
# its source in this repo.
set -uo pipefail
shopt -s nullglob dotglob
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HOME_DIR="$(fresh_home)"
trap 'rm -rf "$HOME_DIR"' EXIT

fail=0
HOME="$HOME_DIR" bash "$REPO/install.sh" --yes > /dev/null || { echo "FAIL: install.sh exited non-zero"; fail=1; }

for src in "$REPO/files/home/.claude"/*; do
  name="$(basename "$src")"
  [ "$name" = .DS_Store ] && continue
  assert_symlink_to "$HOME_DIR/.claude/$name" "$src" "$name" || fail=1
done
assert_symlink_to "$HOME_DIR/.claude/skills" "$REPO/skills" "skills" || fail=1
# projects/ is gitignored, so it exists only once Claude Code has created it.
if [ -d "$REPO/projects" ]; then
  assert_symlink_to "$HOME_DIR/.claude/projects" "$REPO/projects" "projects" || fail=1
fi

exit "$fail"
