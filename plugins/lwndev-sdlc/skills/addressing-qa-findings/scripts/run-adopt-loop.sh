#!/usr/bin/env bash
set -euo pipefail

# run-adopt-loop.sh (FEAT-032 / Phase 2 / FR-4 / FR-5)
#
# Drive the adopt-phase loop deterministically: enumerate committed QA test
# files matching the FR-3 v1 glob set, call adopt-qa-test.sh once per file,
# stream adopted paths to stdout, and abort on the first non-zero exit. The
# orchestrator (Phase 4) consumes the stdout stream to record adoptions
# incrementally per FR-4 step 2.2.
#
# Usage:
#   run-adopt-loop.sh
#
# Behavior:
#   1. Run `git ls-files` against the FR-3 v1 globs.
#   2. For each path, call adopt-qa-test.sh:
#        - exit 0: print the new path on stdout, increment N.
#        - exit non-zero: abort with the verbatim FR-4 partial-success message:
#          `failed | adoption failed for <path>; <N> adopted, <M> remaining`
#          on stdout where M is the count of QA paths NOT yet successfully
#          processed (including the failing one). The script's stderr line
#          is surfaced to this script's stderr so the caller can pass it
#          through.
#   3. On full success, exit 0. The caller commits the adoption.
#
# Exit codes:
#   0  every QA file adopted (paths streamed to stdout)
#   1  partial-success (verbatim FR-4 message on stdout; failing-script stderr
#      bubbled through this script's stderr)
#   2  no QA files matched the v1 globs (no-op; stdout empty)

ADOPT="${ADOPT_QA_TEST_SCRIPT:-}"
# Prefer co-located sibling so source-tree invocations and test runs always use
# the matching version. Fall back to CLAUDE_PLUGIN_ROOT only when the co-located
# script is missing (e.g., when this script itself runs from a cache).
if [[ -z "$ADOPT" || ! -f "$ADOPT" ]]; then
  SELF_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${SELF_DIR}/adopt-qa-test.sh" ]]; then
    ADOPT="${SELF_DIR}/adopt-qa-test.sh"
  elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    ADOPT="${CLAUDE_PLUGIN_ROOT}/skills/addressing-qa-findings/scripts/adopt-qa-test.sh"
  fi
fi
if [[ ! -f "$ADOPT" ]]; then
  echo "Error: cannot locate adopt-qa-test.sh." >&2
  exit 2
fi

# Enumerate committed QA paths matching the FR-3 v1 glob set. Use a portable
# read loop instead of `mapfile -t` to support macOS bash 3.2.
QA_PATHS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  QA_PATHS+=("$line")
done < <(git ls-files \
  'tests/unit/qa-*.test.ts' \
  'tests/unit/qa-*.test.js' \
  'tests/bats/qa/qa-*.bats' \
  2>/dev/null)

if [[ ${#QA_PATHS[@]} -eq 0 ]]; then
  exit 2
fi

TOTAL=${#QA_PATHS[@]}
ADOPTED=0

ADOPT_TMP="$(mktemp -t adopt-stderr.XXXXXX)"
cleanup() { rm -f "$ADOPT_TMP"; }
trap cleanup EXIT

for path in "${QA_PATHS[@]}"; do
  set +e
  out="$(bash "$ADOPT" "$path" 2>"$ADOPT_TMP")"
  rc=$?
  set -e
  err="$(cat "$ADOPT_TMP" 2>/dev/null || true)"
  : > "$ADOPT_TMP"

  if [[ "$rc" -eq 0 ]]; then
    echo "$out"
    ADOPTED=$((ADOPTED + 1))
  else
    if [[ -n "$err" ]]; then
      echo "$err" >&2
    fi
    REMAINING=$((TOTAL - ADOPTED))
    echo "failed | adoption failed for ${path}; ${ADOPTED} adopted, ${REMAINING} remaining"
    exit 1
  fi
done

exit 0
