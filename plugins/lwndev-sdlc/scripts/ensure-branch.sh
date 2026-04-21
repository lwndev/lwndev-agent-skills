#!/usr/bin/env bash
# ensure-branch.sh — Idempotently place the working tree on the named branch (FR-5).
#
# Usage: ensure-branch.sh <branch-name>
#
# Behavior:
#   1. Read current branch via `git rev-parse --abbrev-ref HEAD`.
#   2. If current == target: print "on <branch>", exit 0.
#   3. Else if `git show-ref --verify refs/heads/<branch>` matches:
#        `git checkout <branch>` → print "switched to <branch>", exit 0.
#   4. Else: `git checkout -b <branch>` → print "created <branch>", exit 0.
#   5. If checkout fails because of uncommitted changes: exit 3 with
#      "error: uncommitted changes prevent branch switch".
#
# Exit codes:
#   0 success
#   1 git command failure (unrelated to dirty tree)
#   2 usage error (missing arg)
#   3 dirty working tree prevents branch switch

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: ensure-branch.sh <branch-name>" >&2
  exit 2
fi

target="$1"

current=$(git rev-parse --abbrev-ref HEAD)

if [ "$current" = "$target" ]; then
  printf 'on %s\n' "$target"
  exit 0
fi

# Attempt the checkout. Capture stderr so we can classify dirty-tree failures.
if git show-ref --verify --quiet "refs/heads/${target}"; then
  action="switched to"
  checkout_err=$(git checkout "$target" 2>&1 >/dev/null) && rc=$? || rc=$?
else
  action="created"
  checkout_err=$(git checkout -b "$target" 2>&1 >/dev/null) && rc=$? || rc=$?
fi

if [ "${rc:-0}" -ne 0 ]; then
  # Classify: dirty tree shows specific git messages.
  if printf '%s' "$checkout_err" | grep -qE 'would be overwritten|local changes|uncommitted'; then
    echo "error: uncommitted changes prevent branch switch" >&2
    exit 3
  fi
  # Forward the git error for any other failure.
  printf '%s\n' "$checkout_err" >&2
  exit 1
fi

printf '%s %s\n' "$action" "$target"
