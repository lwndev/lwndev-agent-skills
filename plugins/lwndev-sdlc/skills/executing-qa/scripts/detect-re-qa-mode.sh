#!/usr/bin/env bash
set -euo pipefail

# detect-re-qa-mode.sh (FEAT-032 FR-3, BUG-022) — Auto-detect whether
# executing-qa is running in initial-run mode or re-QA mode for the given
# requirement ID.
#
# Re-QA mode is entered when BOTH of these hold:
#   (a) The requirement ID has a genuine prior QA run recorded in workflow state:
#       qaFixAttempts >= 1 OR qaLastVerdict is non-null.
#       State is read via workflow-state.sh get-qa-state <ID> (co-located in
#       the orchestrating-workflows skill). Fail-safe: any read failure
#       (missing state file, non-zero exit, malformed JSON) yields
#       priorRun=false -> mode=initial. Never fails to re-qa on unavailable state.
#   (b) At least one committed QA test file matches the v1 glob set:
#         tests/unit/qa-*.test.ts
#         tests/unit/qa-*.test.js
#         tests/bats/qa/qa-*.bats
#       Forward-compat globs (qa-*.py, qa-*.go) are NO-OPS in v1 per FR-3 /
#       Edge Case 17 (lockstep constraint with addressing-qa-findings dispatch).
#
# Usage:
#   detect-re-qa-mode.sh <ID>
#
# Output (stdout, JSON):
#   {"mode":"re-qa","files":["tests/unit/qa-foo.test.ts", ...]}
#   {"mode":"initial","files":[]}
#
# Exit codes:
#   0 always (mode is on stdout; state-read failures are not errors)
#   2 missing/invalid args
#
# Notes:
#   * The script does NOT touch any marker or state file — it only reads.
#   * The script uses `git ls-files` so untracked qa-*.test.ts files do NOT
#     trigger re-QA mode (mirroring the FR-9 finalize safety-net contract).
#   * The baseline marker (.sdlc/qa/.executing-qa-baseline-<ID>) is NOT used
#     for re-QA detection. It is written by qa-baseline.sh init (always) for
#     the FR-10 stop-hook diff guard; its presence is not a prior-run signal.

usage() {
  echo "Usage: detect-re-qa-mode.sh <ID>" >&2
}

if [[ $# -ne 1 ]]; then
  echo "Error: expected 1 arg (ID), got $#." >&2
  usage
  exit 2
fi

ID="$1"
if [[ -z "$ID" ]]; then
  echo "Error: ID is required." >&2
  usage
  exit 2
fi

# Resolve workflow-state.sh relative to this script's directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WFSTATE="${SCRIPT_DIR}/../../orchestrating-workflows/scripts/workflow-state.sh"

# Glob set per FR-3 v1. Forward-compat .py/.go globs intentionally absent in
# v1 per Edge Case 17.
GLOBS=(
  "tests/unit/qa-*.test.ts"
  "tests/unit/qa-*.test.js"
  "tests/bats/qa/qa-*.bats"
)

# Collect tracked QA files matching any glob. `git ls-files` returns nothing
# (exit 0) when no match; quote globs so the shell does not pre-expand.
FILES=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  FILES="$(git ls-files -- "${GLOBS[@]}" 2>/dev/null || true)"
fi

# Build the JSON files array.
FILES_JSON='[]'
if [[ -n "$FILES" ]]; then
  FILES_JSON="$(printf '%s\n' "$FILES" | jq -R -s 'split("\n") | map(select(length > 0))')"
fi

# Determine whether a genuine prior QA run exists for this ID.
# Cross-check workflow state (BUG-022 fix): a prior run requires qaFixAttempts>=1
# OR qaLastVerdict non-null. Fail-safe to priorRun=false on any read error so
# initial runs are never misclassified as re-qa when state is unavailable.
PRIOR_RUN=false
if [[ -x "$WFSTATE" ]] || [[ -f "$WFSTATE" ]]; then
  _state_json="$(bash "$WFSTATE" get-qa-state "$ID" 2>/dev/null || true)"
  if [[ -n "$_state_json" ]]; then
    _fix_attempts="$(printf '%s' "$_state_json" | jq -r '.qaFixAttempts // 0' 2>/dev/null || true)"
    _last_verdict="$(printf '%s' "$_state_json" | jq -r '.qaLastVerdict // "null"' 2>/dev/null || true)"
    if [[ "${_fix_attempts:-0}" -ge 1 ]] || [[ "$_last_verdict" != "null" && -n "$_last_verdict" ]]; then
      PRIOR_RUN=true
    fi
  fi
fi

MODE="initial"
if [[ "$PRIOR_RUN" == "true" ]] && [[ "$(printf '%s' "$FILES_JSON" | jq 'length')" -gt 0 ]]; then
  MODE="re-qa"
fi

jq -nc --arg mode "$MODE" --argjson files "$FILES_JSON" \
  '{mode: $mode, files: $files}'
exit 0
