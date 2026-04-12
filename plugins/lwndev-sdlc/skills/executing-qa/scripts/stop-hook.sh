#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Prevent premature stopping before QA execution is complete
# Reads JSON from stdin, checks completion criteria via pattern matching.
# Two phases: (1) QA verification pass, (2) documentation reconciliation.
#
# Exit codes:
#   0 — allow stop (both phases complete or stop_hook_active is set)
#   2 — block stop (verification or reconciliation not yet complete)

ACTIVE_FILE=".sdlc/qa/.executing-active"

# If the executing-qa skill is not active, allow stop immediately
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

# Read stdin JSON; if empty or malformed, allow stop to avoid trapping the user
INPUT="$(cat)" || exit 0
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Check stop_hook_active bypass — exit 0 immediately if true
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" || exit 0
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

# Extract last_assistant_message
MESSAGE="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)" || exit 0
if [[ -z "$MESSAGE" ]]; then
  exit 0
fi

# Normalize to lowercase for case-insensitive matching
MSG_LOWER="$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')"

# Check for QA verification completion indicators
HAS_VERIFICATION=false
if echo "$MSG_LOWER" | grep -qE "(qa.*pass)|(verification.*pass)|(verification.*complete)|(verif.*clean)|(all.*pass)|(all.*entries.*pass)|(verdict.*pass)|(clean.*pass)|(clean.*verdict)"; then
  HAS_VERIFICATION=true
fi

# Check for reconciliation completion indicators
HAS_RECONCILIATION=false
if echo "$MSG_LOWER" | grep -qE "(reconciliation.*complete)|(reconciliation.*done)|(reconciliation.*finished)|(reconcil.*all.*areas)|(all.*reconciliation)|(documentation.*reconcil.*complete)|(reconcil.*covered)|(reconcil.*updated)"; then
  HAS_RECONCILIATION=true
fi

# Check for results file indicator
HAS_RESULTS=false
if echo "$MSG_LOWER" | grep -qE "(qa-results-)|(test.results.*saved)|(results.*saved)|(saved.*results)"; then
  HAS_RESULTS=true
fi

# Both verification and reconciliation must be complete
if [[ "$HAS_VERIFICATION" == "true" && "$HAS_RECONCILIATION" == "true" ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

# If results file is mentioned with either indicator, that's also sufficient
# (results are only saved at the very end after both phases)
if [[ "$HAS_RESULTS" == "true" && ("$HAS_VERIFICATION" == "true" || "$HAS_RECONCILIATION" == "true") ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

# Build a helpful message about what's missing
MISSING=""
if [[ "$HAS_VERIFICATION" != "true" ]]; then
  MISSING="QA verification has not passed cleanly"
fi
if [[ "$HAS_RECONCILIATION" != "true" ]]; then
  if [[ -n "$MISSING" ]]; then
    MISSING="$MISSING; documentation reconciliation is not yet complete"
  else
    MISSING="Documentation reconciliation is not yet complete"
  fi
fi

echo "$MISSING." >&2
exit 2
