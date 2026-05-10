#!/usr/bin/env bash
set -euo pipefail

# detect-re-qa-mode.sh (FEAT-032 FR-3) — Auto-detect whether executing-qa is
# running in initial-run mode or re-QA mode for the given requirement ID.
#
# Re-QA mode is entered when BOTH of these hold:
#   (a) The qa-baseline marker file `.sdlc/qa/.executing-qa-baseline-<ID>` exists
#       (set by qa-baseline.sh init from a prior executing-qa run for the same ID).
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
#   0 always (mode is on stdout; missing marker / missing files are not errors)
#   2 missing/invalid args
#
# Notes:
#   * The script does NOT touch the marker file — it only reads.
#   * The script uses `git ls-files` so untracked qa-*.test.ts files do NOT
#     trigger re-QA mode (mirroring the FR-9 finalize safety-net contract).
#   * No new marker is introduced for re-QA — re-detection on every entry uses
#     the existing baseline marker as the "this ID has run before" signal.

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

MARKER_PATH=".sdlc/qa/.executing-qa-baseline-${ID}"

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

MODE="initial"
if [[ -f "$MARKER_PATH" ]] && [[ "$(printf '%s' "$FILES_JSON" | jq 'length')" -gt 0 ]]; then
  MODE="re-qa"
fi

jq -nc --arg mode "$MODE" --argjson files "$FILES_JSON" \
  '{mode: $mode, files: $files}'
exit 0
