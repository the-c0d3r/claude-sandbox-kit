# shellcheck shell=bash
# Shared helpers for test/test_install_*.sh and test/test_uninstall_*.sh.
# Not shipped to adopters — install.sh/uninstall.sh stay self-contained and
# dependency-free on their own; only this internal test suite shares code.
# shellcheck disable=SC2034  # REPO is used by the tests that source this file
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stub sbx so install.sh/uninstall.sh never touch the machine's real skills
# store: a test install from a throwaway repo would relink it there.
SBX_STUB="$(mktemp -d)"
printf '#!/bin/sh\nexit 1\n' > "$SBX_STUB/sbx"
chmod +x "$SBX_STUB/sbx"
PATH="$SBX_STUB:$PATH"

fresh_home() {
  mktemp -d
}

assert_symlink_to() {
  local dest="$1" expected_target="$2" msg="$3"
  if [ ! -L "$dest" ]; then
    echo "FAIL: $msg -- $dest is not a symlink"
    return 1
  fi
  local actual
  actual="$(readlink "$dest")"
  if [ "$actual" != "$expected_target" ]; then
    echo "FAIL: $msg -- $dest -> $actual, expected -> $expected_target"
    return 1
  fi
}

assert_not_symlink() {
  local dest="$1" msg="$2"
  if [ -L "$dest" ]; then
    echo "FAIL: $msg -- $dest is unexpectedly a symlink"
    return 1
  fi
}

assert_file_content() {
  local file="$1" expected="$2" msg="$3"
  local actual
  actual="$(cat "$file" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $msg -- $file contains [$actual], expected [$expected]"
    return 1
  fi
}

assert_exists() {
  local path="$1" msg="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    echo "FAIL: $msg -- $path does not exist"
    return 1
  fi
}
