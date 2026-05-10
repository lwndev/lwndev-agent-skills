#!/usr/bin/env bash
# qa-dispatch.sh — QA verdict dispatcher for the orchestrator fix loop (FEAT-032 FR-7).
#
# Usage: qa-dispatch.sh <ID> [--explain]
#
# Reads {qaFixAttempts, qaLastVerdict, adoptedTests, qaLoopCap} from workflow-state.sh
# and emits one dispatch token on stdout, then exits 0.
#
# Dispatch tokens (load-bearing — orchestrator branches on these verbatim):
#   dispatch=advance              — initial PASS, EXPLORATORY-ONLY, or post-adopt PASS
#   dispatch=adopt-phase          — post-fix PASS needing adoption (adoptedTests empty)
#   dispatch=fix-phase            — ISSUES-FOUND and qaFixAttempts < qaLoopCap
#   dispatch=pause:qa-loop-exhausted — ISSUES-FOUND and qaFixAttempts >= qaLoopCap
#   dispatch=pause:qa-error       — verdict == ERROR
#   dispatch=pause:fix-suite-failed  — fix-phase returned suite-gate failure
#   dispatch=pause:adoption-failed   — adopt-phase returned partial-success failure
#
# Note: `dispatch=re-qa` is NOT emitted here; the orchestrator emits it internally
# after a fix-phase returns `done | phase=fix-committed`. This script handles only
# verdict-gated branches from qa-dispatch state.
#
# --explain: emit a human-readable context line to stderr (debugging).
#
# Exit codes:
#   0  dispatch token emitted on stdout
#   1  state file missing or malformed
#   2  missing / malformed args
#
# CLAUDE_PLUGIN_ROOT derivation: three levels up from this script's directory.
#   scripts/ -> orchestrating-workflows/ -> skills/ -> lwndev-sdlc/

set -euo pipefail

# --- arg parsing ---

if [[ $# -lt 1 ]]; then
  echo "Error: qa-dispatch.sh requires <ID> [--explain]" >&2
  exit 2
fi

id="$1"
explain=false
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --explain) explain=true ;;
    *)
      echo "Error: qa-dispatch.sh unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! "$id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  echo "Error: qa-dispatch.sh invalid ID format: $id" >&2
  exit 2
fi

# --- locate workflow-state.sh ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKFLOW_STATE="${SCRIPT_DIR}/workflow-state.sh"
# PATH-shadow hook for bats: if workflow-state.sh is on PATH, prefer it.
if command -v workflow-state.sh >/dev/null 2>&1; then
  WORKFLOW_STATE="$(command -v workflow-state.sh)"
fi

# --- read QA state ---

qa_json=""
qa_state_tmp=$(mktemp)
if ! qa_json=$(bash "$WORKFLOW_STATE" get-qa-state "$id" 2>"$qa_state_tmp"); then
  cat "$qa_state_tmp" >&2
  rm -f "$qa_state_tmp"
  echo "[error] qa-dispatch: get-qa-state failed for $id" >&2
  exit 1
fi
# Relay stderr verbatim on success — captures FR-13 migration debug line
# (`[workflow-state] debug: migrating ...`) without contaminating qa_json.
cat "$qa_state_tmp" >&2
rm -f "$qa_state_tmp"

if ! echo "$qa_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "[error] qa-dispatch: malformed JSON from get-qa-state: $qa_json" >&2
  exit 1
fi

qa_fix_attempts=$(echo "$qa_json" | jq -r '.qaFixAttempts // 0')
qa_last_verdict=$(echo "$qa_json" | jq -r '.qaLastVerdict // empty')
adopted_tests_len=$(echo "$qa_json" | jq -r '(.adoptedTests // []) | length')

# Read qaLoopCap directly from state file (not exposed via get-qa-state).
state_file=".sdlc/workflows/${id}.json"
if [[ ! -r "$state_file" ]]; then
  echo "[error] qa-dispatch: state file not readable: $state_file" >&2
  exit 1
fi
qa_loop_cap=$(jq -r '.qaLoopCap // 2' "$state_file")

# --- dispatch logic (FR-7) ---

dispatch=""

case "${qa_last_verdict:-}" in

  PASS)
    if [[ "$qa_fix_attempts" -eq 0 ]]; then
      # Initial-run PASS — advance directly.
      dispatch="advance"
      $explain && echo "[qa-dispatch] initial-run PASS (qaFixAttempts=0) → advance" >&2 || true
    elif [[ "$adopted_tests_len" -gt 0 ]]; then
      # Post-adopt PASS — all tests adopted; advance.
      dispatch="advance"
      $explain && echo "[qa-dispatch] post-adopt PASS (qaFixAttempts=${qa_fix_attempts}, adoptedTests=${adopted_tests_len}) → advance" >&2 || true
    else
      # Post-fix PASS needing adoption.
      dispatch="adopt-phase"
      $explain && echo "[qa-dispatch] post-fix PASS (qaFixAttempts=${qa_fix_attempts}, adoptedTests=0) → adopt-phase" >&2 || true
    fi
    ;;

  EXPLORATORY-ONLY)
    # Only reachable from initial run (re-QA cannot return this verdict per FR-3).
    dispatch="advance"
    $explain && echo "[qa-dispatch] EXPLORATORY-ONLY → advance (no tests to fix)" >&2 || true
    ;;

  ISSUES-FOUND)
    if [[ "$qa_fix_attempts" -lt "$qa_loop_cap" ]]; then
      dispatch="fix-phase"
      $explain && echo "[qa-dispatch] ISSUES-FOUND (qaFixAttempts=${qa_fix_attempts} < cap=${qa_loop_cap}) → fix-phase" >&2 || true
    else
      dispatch="pause:qa-loop-exhausted"
      $explain && echo "[qa-dispatch] ISSUES-FOUND (qaFixAttempts=${qa_fix_attempts} >= cap=${qa_loop_cap}) → pause:qa-loop-exhausted" >&2 || true
    fi
    ;;

  ERROR)
    dispatch="pause:qa-error"
    $explain && echo "[qa-dispatch] ERROR verdict → pause:qa-error" >&2 || true
    ;;

  "")
    # No verdict recorded yet — treat as initial-run (no QA executed yet).
    # This handles the case where qa-dispatch is called before executing-qa has run.
    dispatch="advance"
    $explain && echo "[qa-dispatch] no verdict yet → advance (QA not yet executed)" >&2 || true
    ;;

  *)
    echo "[error] qa-dispatch: unrecognised qaLastVerdict: ${qa_last_verdict}" >&2
    exit 1
    ;;
esac

echo "dispatch=${dispatch}"
exit 0
