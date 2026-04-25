#!/usr/bin/env bash
set -euo pipefail

# check-branch-diff.sh (FR-4) — Verify the current branch carries any diff
# relative to main. The caller (executing-qa Step ~1) emits an ERROR verdict
# with `Reason: no changes to test relative to main` when this script exits 1.
#
# Usage:
#   check-branch-diff.sh
#
# No args. Runs `git diff main...HEAD` and inspects the output.
#
# Exit codes:
#   0  non-empty diff (the branch has changes vs. main; QA may proceed)
#   1  empty diff (no changes vs. main; caller emits ERROR verdict)

if [[ $# -ne 0 ]]; then
  echo "Error: check-branch-diff.sh takes no arguments." >&2
  exit 1
fi

# Detached-HEAD or missing main is not the script's responsibility to recover —
# git diff itself surfaces the right error to stderr; the script propagates
# exit-1 in that case.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# Verify main exists locally or as origin/main; prefer local main.
BASE=""
if git rev-parse --verify --quiet main >/dev/null 2>&1; then
  BASE="main"
elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  BASE="origin/main"
else
  echo "Error: cannot resolve 'main' or 'origin/main' as a base." >&2
  exit 1
fi

# git diff <base>...HEAD shows changes on HEAD since the merge-base with <base>.
DIFF_OUTPUT="$(git diff "${BASE}...HEAD" 2>/dev/null || true)"

if [[ -z "$DIFF_OUTPUT" ]]; then
  exit 1
fi

exit 0
