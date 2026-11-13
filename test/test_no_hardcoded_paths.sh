#!/usr/bin/env bash
# Layer 1 (static): fails on any real home path (/Users/<name>, /home/<name>
# other than the sandbox's /home/agent) in any file of the repo, docs
# included — everything here is public.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

fail=0

while IFS= read -r file; do
  [ -f "$file" ] || continue

  while IFS=: read -r line content; do
    [ -n "${line:-}" ] || continue
    echo "hardcoded personal path in $file:$line -> $content"
    fail=1
  done < <(grep -noP '(?<![A-Za-z0-9/])/Users/[A-Za-z0-9_.-]+.*' "$file")

  while IFS=: read -r line content; do
    [ -n "${line:-}" ] || continue
    user="$(printf '%s' "$content" | grep -oP '(?<![A-Za-z0-9/])/home/[A-Za-z0-9_.-]+' | head -1 | sed -E 's#.*/home/([^/]+).*#\1#')"
    if [ "$user" != "agent" ]; then
      echo "non-agent /home path in $file:$line -> $content"
      fail=1
    fi
  done < <(grep -noP '(?<![A-Za-z0-9/])/home/[A-Za-z0-9_.-]+.*' "$file")
done < <(git ls-files --cached --others --exclude-standard)

exit "$fail"
