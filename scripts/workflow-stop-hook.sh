#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_FILE="$PROJECT_ROOT/.sdlc/workflows/.active"

# No active workflow file → allow stop
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

ID="$(cat "$ACTIVE_FILE" 2>/dev/null | tr -d '[:space:]')"

# Empty file → allow stop
if [[ -z "$ID" ]]; then
  exit 0
fi

STATE_FILE="$PROJECT_ROOT/.sdlc/workflows/$ID.json"

# No state file → allow stop
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# jq not available → allow stop (can't check state)
if ! command -v jq &>/dev/null; then
  exit 0
fi

# Parse state
STATUS="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null || true)"

# Allow stop for: complete, paused, failed, or unreadable state
case "$STATUS" in
  complete|paused|failed)
    exit 0
    ;;
  in-progress)
    # Get current step info
    CURRENT_STEP="$(jq -r '.currentStep // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
    TOTAL_STEPS="$(jq -r '.steps | length' "$STATE_FILE" 2>/dev/null || echo 0)"
    STEP_NAME="$(jq -r ".steps[$((CURRENT_STEP - 1))].name // \"unknown\"" "$STATE_FILE" 2>/dev/null || echo "unknown")"

    if [[ "$CURRENT_STEP" -gt 0 && "$CURRENT_STEP" -le "$TOTAL_STEPS" ]]; then
      echo "Workflow $ID is in progress (step $CURRENT_STEP of $TOTAL_STEPS: $STEP_NAME). Continue to complete the current step." >&2
      exit 2
    fi
    exit 0
    ;;
  *)
    # Unknown status → allow stop
    exit 0
    ;;
esac
