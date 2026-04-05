#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Prevent premature stopping before release phase is complete
# Reads JSON from stdin, checks completion criteria via pattern matching.
# Two phases: Phase 1 (pre-merge: PR opened), Phase 2 (post-merge: tag pushed).
#
# Exit codes:
#   0 — allow stop (current phase complete or stop_hook_active is set)
#   2 — block stop (phase criteria not yet met)

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

# If the message contains no release-related keywords, it's not from a release workflow — allow stop
if ! echo "$MSG_LOWER" | grep -qE "(release|version|bump|changelog|tag the|phase 1|phase 2|plugin.*v[0-9])"; then
  exit 0
fi

# Check Phase 1 completion first — a Phase 1 message may mention "Phase 2"
# (e.g., "re-invoke for Phase 2") so we must detect Phase 1 before Phase 2.
HAS_PR=false
HAS_REINVOKE=false

if echo "$MSG_LOWER" | grep -qE "(pr.*created)|(pr.*opened)|(pull request.*created)|(pull request.*opened)|(opened.*pr)|(created.*pr)|(opened.*pull request)"; then
  HAS_PR=true
fi

if echo "$MSG_LOWER" | grep -qE "(re-invoke)|(reinvoke)|(re invoke)|(invoke.*again)|(run.*again.*phase 2)|(phase 2)"; then
  HAS_REINVOKE=true
fi

# Phase 1 complete: PR opened and user told to re-invoke
if [[ "$HAS_PR" == "true" && "$HAS_REINVOKE" == "true" ]]; then
  exit 0
fi

# Detect Phase 2: tagging, being on main after merge (only if Phase 1 not complete)
IS_PHASE_2=false
if echo "$MSG_LOWER" | grep -qE "(tag.*release)|(post-merge)|(create.*tag)|(push.*tag)|(tag.*created)"; then
  IS_PHASE_2=true
fi

if [[ "$IS_PHASE_2" == "true" ]]; then
  # Phase 2: tag must be pushed
  if echo "$MSG_LOWER" | grep -qE "(tag.*push)|(push.*tag)|(tag.*created.*push)|(pushed.*tag)"; then
    exit 0
  fi
  echo "Phase 2 is not complete. The git tag must be pushed." >&2
  exit 2
fi

# Neither phase is complete — report Phase 1 missing items
MISSING=""
if [[ "$HAS_PR" != "true" ]]; then
  MISSING="PR has not been created"
fi
if [[ "$HAS_REINVOKE" != "true" ]]; then
  if [[ -n "$MISSING" ]]; then
    MISSING="$MISSING; user has not been told to re-invoke for Phase 2"
  else
    MISSING="User has not been told to re-invoke for Phase 2"
  fi
fi

echo "Phase 1 is not complete. $MISSING." >&2
exit 2
