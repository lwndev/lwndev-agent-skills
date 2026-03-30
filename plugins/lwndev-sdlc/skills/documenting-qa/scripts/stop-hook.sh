#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Prevent premature stopping before QA test plan is complete
# Reads JSON from stdin, checks completion criteria via pattern matching.
#
# Exit codes:
#   0 — allow stop (plan is complete or stop_hook_active is set)
#   2 — block stop (plan not yet verified/saved)

# Read stdin JSON; if empty or malformed, allow stop to avoid trapping the user
INPUT="$(cat)" || exit 0
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Check stop_hook_active bypass — exit 0 immediately if true
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" || exit 0
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

# Extract last_assistant_message
MESSAGE="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)" || exit 0
if [[ -z "$MESSAGE" ]]; then
  exit 0
fi

# Normalize to lowercase for case-insensitive matching
MSG_LOWER="$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')"

# Check for completion indicators:
# The plan is complete when the qa-verifier subagent has confirmed completeness
# and the test plan has been saved. Look for patterns indicating verified + saved.

HAS_PLAN_REF=false
HAS_COMPLETE_INDICATOR=false

# Check for test plan file reference (QA-plan- pattern)
if echo "$MSG_LOWER" | grep -q "qa-plan-"; then
  HAS_PLAN_REF=true
fi

# Check for completion/verification indicators
if echo "$MSG_LOWER" | grep -qE "(test plan.*(complete|saved|verified|written|created))|(complete.*test plan)|(saved.*test plan)|(verified.*test plan)|(plan.*complete)|(verification.*complete)|(verif.*pass)|(completeness.*confirmed)|(subagent.*confirm)|(qa-verifier.*complete)|(qa-verifier.*pass)|(all.*(criteria|items|entries).*covered)"; then
  HAS_COMPLETE_INDICATOR=true
fi

if [[ "$HAS_PLAN_REF" == "true" && "$HAS_COMPLETE_INDICATOR" == "true" ]]; then
  exit 0
fi

# Require both indicators — the plan reference and a completion signal.
# The SKILL.md instructs Claude to mention the plan file path and confirm
# completeness in the same message when attempting to finish.

echo "Test plan documentation does not appear complete. Ensure the qa-verifier subagent has confirmed completeness and the test plan has been saved." >&2
exit 2
