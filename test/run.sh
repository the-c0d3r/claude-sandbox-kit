#!/usr/bin/env bash
# Discovers and runs every test/test_*.sh, reports a pass/fail summary.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$REPO/test"

pass=0
fail=0

for t in "$TEST_DIR"/test_*.sh; do
  [ -e "$t" ] || continue
  name="$(basename "$t")"
  if output="$(bash "$t" 2>&1)"; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    # shellcheck disable=SC2001  # prefixes every line; ${//} can't anchor per line
    echo "$output" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
