#!/usr/bin/env bash
set -euo pipefail

# commit-qa-artifact.sh (FEAT-032 FR-12) — Stage and commit the QA results
# artifact at qa/test-results/QA-results-{ID}.md with the verdict-and-mode-aware
# message templates pinned by Bats:
#
#   Initial run: qa({ID}): record QA results
#   Re-QA run:   qa({ID}): re-record QA results after fix attempt {N}
#
# The commit lands AFTER render-qa-results.sh writes the artifact; for the
# initial run it sits alongside commit-qa-tests.sh's earlier QA-tests commit.
# For re-QA runs the QA-tests commit is skipped (no new tests written) so this
# script is the only thing that commits during re-QA. The post-condition is
# `git status --porcelain` empty so the addressing-qa-findings fix-phase
# precheck can proceed.
#
# Usage:
#   commit-qa-artifact.sh <ID> <mode> [<attempt>]
#
# Args:
#   <ID>       Requirement ID (e.g., FEAT-030).
#   <mode>     One of: initial | re-qa
#   <attempt>  Required when mode == re-qa. The current qaFixAttempts value
#              from `workflow-state.sh get-qa-state`. Must be a positive integer.
#
# Exit codes:
#   0  artifact committed
#   1  no artifact at qa/test-results/QA-results-<ID>.md, or nothing staged
#      after `git add` (artifact already committed and unchanged — informational)
#   2  missing/invalid args (no ID, unknown mode, missing/invalid attempt for re-qa)

usage() {
  echo "Usage: commit-qa-artifact.sh <ID> <mode> [<attempt>]" >&2
  echo "  mode: initial | re-qa" >&2
  echo "  attempt: required when mode==re-qa (positive integer)" >&2
}

if [[ $# -lt 2 ]]; then
  echo "Error: expected at least 2 args (ID + mode)." >&2
  usage
  exit 2
fi

ID="$1"
MODE="$2"
ATTEMPT="${3:-}"

if [[ -z "$ID" ]]; then
  echo "Error: ID is required." >&2
  usage
  exit 2
fi

case "$MODE" in
  initial|re-qa) ;;
  *)
    echo "Error: unknown mode '${MODE}' (expected initial|re-qa)." >&2
    usage
    exit 2
    ;;
esac

if [[ "$MODE" == "re-qa" ]]; then
  if [[ -z "$ATTEMPT" ]]; then
    echo "Error: re-qa mode requires <attempt> as the third arg." >&2
    usage
    exit 2
  fi
  if ! [[ "$ATTEMPT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <attempt> must be a positive integer (got '${ATTEMPT}')." >&2
    exit 2
  fi
fi

ARTIFACT="qa/test-results/QA-results-${ID}.md"
if [[ ! -f "$ARTIFACT" ]]; then
  echo "Error: QA results artifact not found: $ARTIFACT" >&2
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

git add -- "$ARTIFACT"

STAGED="$(git diff --cached --name-only -- "$ARTIFACT" 2>/dev/null || true)"
if [[ -z "$STAGED" ]]; then
  echo "[info] no QA artifact changes to commit (already committed or unchanged)" >&2
  exit 1
fi

if [[ "$MODE" == "initial" ]]; then
  MESSAGE="qa(${ID}): record QA results"
else
  MESSAGE="qa(${ID}): re-record QA results after fix attempt ${ATTEMPT}"
fi

git commit -m "$MESSAGE" -- "$ARTIFACT" >/dev/null

echo "committed ${ID}"
exit 0
