#!/usr/bin/env bash
# commit-work.sh — Create a conventional-commit in the current repo (FR-8).
#
# Usage: commit-work.sh <type> <category> <description>
#
# <type> must be one of:
#   chore | fix | feat | qa | docs | test | refactor | perf | style | build | ci | revert
#
# Behavior:
#   - Validates <type> against the allowed list (exit 2 otherwise).
#   - Does NOT stage anything — the caller is responsible for `git add`.
#   - Runs: git commit -m "<type>(<category>): <description>"
#   - On success: prints the short SHA (from `git rev-parse --short HEAD`).
#   - On failure: forwards git stderr unchanged, exits 1.
#
# Exit codes:
#   0 success (short SHA printed to stdout)
#   1 git failure (e.g., nothing staged)
#   2 usage error (missing args or invalid type)

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "error: usage: commit-work.sh <type> <category> <description>" >&2
  exit 2
fi

type="$1"
category="$2"
description="$3"

case "$type" in
  chore|fix|feat|qa|docs|test|refactor|perf|style|build|ci|revert) ;;
  *)
    echo "error: invalid type '${type}' (expected one of: chore, fix, feat, qa, docs, test, refactor, perf, style, build, ci, revert)" >&2
    exit 2
    ;;
esac

message="${type}(${category}): ${description}"

if ! git commit -m "$message"; then
  exit 1
fi

git rev-parse --short HEAD
