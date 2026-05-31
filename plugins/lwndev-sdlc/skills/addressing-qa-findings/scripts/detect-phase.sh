#!/usr/bin/env bash
set -euo pipefail

# detect-phase.sh (FEAT-032 / Phase 2 / FR-4)
#
# Auto-detect the addressing-qa-findings phase from the FR-4 state triple
# {qaLastVerdict, qaFixAttempts, adoptedTests}. The skill body calls this
# script and branches on stdout.
#
# Usage:
#   detect-phase.sh <ID>
#
# Output (stdout, single line):
#   phase=fix     — verdict == ISSUES-FOUND AND adoptedTests == []
#   phase=adopt   — verdict == PASS AND qaFixAttempts > 0 AND adoptedTests == []
#   phase=unknown — anything else
#
# Exit codes:
#   0  phase printed (caller branches on stdout; phase=unknown is exit 0 too —
#      the skill emits the verbatim failure message itself)
#   2  missing args / state file unreadable

if [[ $# -ne 1 ]]; then
  echo "Error: expected exactly 1 argument: <ID>." >&2
  exit 2
fi

ID="$1"

if [[ -z "$ID" ]]; then
  echo "Error: <ID> is required." >&2
  exit 2
fi

# Locate workflow-state.sh. Prefer the co-located sibling (this script's own
# plugin tree) so source-tree invocations and test runs always use the
# matching version. Fall back to CLAUDE_PLUGIN_ROOT only if the co-located
# script is missing (e.g., when this script is itself running from a cache).
WF_STATE=""
SELF_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
candidate="${SELF_DIR}/../../orchestrating-workflows/scripts/workflow-state.sh"
if [[ -f "$candidate" ]]; then
  WF_STATE="$candidate"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  WF_STATE="${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh"
fi
if [[ ! -f "$WF_STATE" ]]; then
  echo "Error: cannot locate workflow-state.sh (set CLAUDE_PLUGIN_ROOT)." >&2
  exit 2
fi

if ! state="$(bash "$WF_STATE" get-qa-state "$ID" 2>/dev/null)"; then
  echo "Error: workflow-state.sh get-qa-state failed for ${ID}." >&2
  exit 2
fi

verdict="$(echo "$state" | jq -r '.qaLastVerdict // "null"')"
attempts="$(echo "$state" | jq -r '.qaFixAttempts // 0')"
adopted_count="$(echo "$state" | jq -r '.adoptedTests | length')"

if [[ "$verdict" = "ISSUES-FOUND" && "$adopted_count" = "0" ]]; then
  echo "phase=fix"
  exit 0
fi

if [[ "$verdict" = "PASS" && "$adopted_count" = "0" ]]; then
  # Route to adopt-phase when attempts>0 (post-fix PASS) OR when qa-* files
  # are git-visible (initial-run PASS with un-adopted tests — BUG-023 fix).
  # Use the same three canonical FR-9 globs (Edge Case 17 lockstep: do NOT
  # add pytest/go-test globs).
  qa_files_present=false
  if git ls-files \
      'tests/unit/qa-*.test.ts' \
      'tests/unit/qa-*.test.js' \
      'tests/bats/qa/qa-*.bats' \
      2>/dev/null | grep -q .; then
    qa_files_present=true
  fi
  if [[ "$attempts" -gt 0 ]] || $qa_files_present; then
    echo "phase=adopt"
    exit 0
  fi
fi

echo "phase=unknown"
exit 0
