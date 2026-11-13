#!/usr/bin/env bash
# Layer 1 (static): optional shellcheck pass over every *.sh script.
# Skips cleanly (exit 0) if shellcheck isn't installed — it's a nice-to-have
# lint, not a hard dependency for running this repo's test suite.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed - skipping (install it locally to enable this check)"
  exit 0
fi

fail=0
while IFS= read -r file; do
  [ -f "$file" ] || continue  # tracked but deleted in the working tree
  # SC1091: sourced test/lib/harness.sh isn't followed — it's checked on its own.
  shellcheck -e SC1091 "$file" || fail=1
done < <(git ls-files --cached --others --exclude-standard -- '*.sh')

exit "$fail"
