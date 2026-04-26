#!/usr/bin/env bash
set -euo pipefail

# commit-qa-tests.sh (FR-8) — Stage and commit a list of QA test files with
# the canonical message:
#   qa({ID}): add executable QA tests from executing-qa run
#
# Usage:
#   commit-qa-tests.sh <ID> <test-files...>
#
# Args:
#   <ID>          Requirement ID (e.g., FEAT-030).
#   <test-files>  One or more test-file paths to stage. Paths may contain
#                 spaces; quote each path on the caller side.
#
# Exit codes:
#   0  committed
#   1  no files to commit (after `git add`, the staged set against the
#      QA test files is empty — typically because the files are already
#      committed). Caller continues.
#   2  missing/invalid args (no ID, or no files supplied, or a supplied path
#      does not exist)

usage() {
  echo "Usage: commit-qa-tests.sh <ID> <test-files...>" >&2
}

if [[ $# -lt 2 ]]; then
  echo "Error: expected at least 2 args (ID + one or more files)." >&2
  usage
  exit 2
fi

ID="$1"
shift

if [[ -z "$ID" ]]; then
  echo "Error: ID is required." >&2
  exit 2
fi

# Validate every supplied path exists.
for f in "$@"; do
  if [[ ! -e "$f" ]]; then
    echo "Error: test file does not exist: $f" >&2
    exit 2
  fi
done

# Verify we are inside a git repo.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# Stage each file.
git add -- "$@"

# Determine whether any of the supplied files have staged changes.
STAGED=""
STAGED="$(git diff --cached --name-only -- "$@" 2>/dev/null || true)"

if [[ -z "$STAGED" ]]; then
  echo "[info] no files to commit (already committed or unchanged)" >&2
  exit 1
fi

MESSAGE="qa(${ID}): add executable QA tests from executing-qa run"

git commit -m "$MESSAGE" -- "$@" >/dev/null

echo "committed ${ID}"
exit 0
