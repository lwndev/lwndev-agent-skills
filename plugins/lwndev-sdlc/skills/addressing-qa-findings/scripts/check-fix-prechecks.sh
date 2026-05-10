#!/usr/bin/env bash
set -euo pipefail

# check-fix-prechecks.sh (FEAT-032 / Phase 2 / FR-4)
#
# Run the deterministic preconditions for the fix phase of addressing-qa-findings.
# The model-driven body of the skill calls this script and surfaces the verbatim
# failure message when the script exits non-zero.
#
# Usage:
#   check-fix-prechecks.sh <ID>
#
# Behavior:
#   1. `git diff --quiet && git diff --cached --quiet`. On dirty: print
#      `failed | working tree dirty; commit or stash before re-running` and
#      exit 1.
#   2. `[ -f "qa/test-results/QA-results-${ID}.md" ]`. On absent: print
#      `failed | no QA artifact at qa/test-results/QA-results-{ID}.md` and
#      exit 1. (Note: the printed path uses the literal `{ID}` placeholder
#      per FR-4 verbatim message; the artifact path itself substitutes.)
#
# On success: exit 0 with no output.
#
# Exit codes:
#   0  preconditions satisfied
#   1  precondition failed (verbatim FR-4 message on stdout)
#   2  missing args

if [[ $# -ne 1 ]]; then
  echo "Error: expected exactly 1 argument: <ID>." >&2
  exit 2
fi

ID="$1"

if [[ -z "$ID" ]]; then
  echo "Error: <ID> is required." >&2
  exit 2
fi

# Working-tree clean check.
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "failed | working tree dirty; commit or stash before re-running"
  exit 1
fi

# QA artifact present check.
if [[ ! -f "qa/test-results/QA-results-${ID}.md" ]]; then
  echo "failed | no QA artifact at qa/test-results/QA-results-{ID}.md"
  exit 1
fi

exit 0
