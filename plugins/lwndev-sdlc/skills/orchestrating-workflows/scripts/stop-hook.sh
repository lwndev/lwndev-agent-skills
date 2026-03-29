#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Prevent premature stopping mid-workflow
# Reads .sdlc/workflows/.active, queries workflow state, and blocks stop
# if the workflow is in-progress with remaining steps.
#
# Exit codes:
#   0 — allow stop (no active workflow, paused, or complete)
#   2 — block stop (in-progress with remaining steps)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SCRIPT="${SCRIPT_DIR}/workflow-state.sh"
ACTIVE_FILE=".sdlc/workflows/.active"

# If .active file doesn't exist or is empty, allow stop
if [[ ! -f "$ACTIVE_FILE" ]] || [[ ! -s "$ACTIVE_FILE" ]]; then
  exit 0
fi

WORKFLOW_ID="$(tr -d '[:space:]' < "$ACTIVE_FILE")"

# Empty after trimming — allow stop
if [[ -z "$WORKFLOW_ID" ]]; then
  exit 0
fi

# Query workflow status — if state file doesn't exist, clean up stale .active
STATE_JSON="$(bash "$STATE_SCRIPT" status "$WORKFLOW_ID" 2>/dev/null)" || {
  # State file not found or malformed — stale .active file
  rm -f "$ACTIVE_FILE"
  exit 0
}

STATUS="$(echo "$STATE_JSON" | jq -r '.status')"

case "$STATUS" in
  complete|paused)
    exit 0
    ;;
  in-progress|failed)
    CURRENT_STEP="$(echo "$STATE_JSON" | jq -r '.currentStep')"
    TOTAL_STEPS="$(echo "$STATE_JSON" | jq -r '.steps | length')"
    NEXT_DESC="$(echo "$STATE_JSON" | jq -r ".steps[${CURRENT_STEP}].name // \"unknown\"")"

    if [[ "$CURRENT_STEP" -ge "$TOTAL_STEPS" ]]; then
      # All steps done — allow stop
      exit 0
    fi

    echo "Workflow ${WORKFLOW_ID} is ${STATUS}. Continue to step $((CURRENT_STEP + 1)): ${NEXT_DESC}" >&2
    exit 2
    ;;
  *)
    # Unknown status — allow stop to avoid trapping the user
    exit 0
    ;;
esac
