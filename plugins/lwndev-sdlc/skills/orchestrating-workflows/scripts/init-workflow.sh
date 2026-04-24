#!/usr/bin/env bash
# init-workflow.sh — Composite new-workflow init (FEAT-028 FR-5).
#
# Usage: init-workflow.sh <TYPE> <artifact-path>
#   <TYPE>          one of feature | chore | bug
#   <artifact-path> path to the requirements document whose filename encodes
#                   the workflow ID (e.g. requirements/features/FEAT-028-*.md)
#
# Composite over `workflow-state.sh` subcommands + `extract-issue-ref.sh`.
# Collapses the eight-step new-workflow init sequence into a single call so
# the orchestrator SKILL.md can drop the prose ladder.
#
# Execution order (step 6 precedes step 7 so a stop-hook firing mid-composite
# finds the `.active` marker):
#
#   1. Extract <ID> from <artifact-path> filename using TYPE-prefix regex.
#      TYPE / prefix mismatch → exit 1 with `[warn] init-workflow: ...`.
#   2. `mkdir -p .sdlc/workflows` (idempotent).
#   3. workflow-state.sh init <ID> <TYPE>.
#   4. tier=$(workflow-state.sh classify-init <ID> <artifact-path>).
#   5. workflow-state.sh set-complexity <ID> <tier>.
#   6. echo "<ID>" > .sdlc/workflows/.active   # BEFORE advance.
#   7. workflow-state.sh advance <ID> <artifact-path>.
#   8. issueRef=$(extract-issue-ref.sh <artifact-path>) — graceful; empty /
#      failed ref is non-fatal (I6).
#
# Stdout: one JSON object
#   {"id":"FEAT-028","type":"feature","complexity":"medium","issueRef":"#186"}
#
# Uses jq when available; pure-bash fallback for the single flat JSON object.
#
# CLAUDE_PLUGIN_ROOT derivation: three levels up from this script's directory.
#   scripts/ -> orchestrating-workflows/ -> skills/ -> lwndev-sdlc/
#
# Exit codes:
#   0 success (including empty issueRef)
#   1 downstream subcommand failure (stderr relayed) / missing artifact /
#     TYPE-prefix mismatch
#   2 missing / malformed args

set -euo pipefail

# --- arg parsing -------------------------------------------------------------

if [ "$#" -lt 2 ]; then
  echo "[error] init-workflow: usage: init-workflow.sh <TYPE> <artifact-path>" >&2
  exit 2
fi

type="$1"
artifact="$2"

case "$type" in
  feature|chore|bug) ;;
  *)
    echo "[error] init-workflow: invalid TYPE: $type (expected feature|chore|bug)" >&2
    exit 2
    ;;
esac

if [ ! -r "$artifact" ]; then
  echo "[error] init-workflow: artifact not found or unreadable: $artifact" >&2
  exit 1
fi

# --- CLAUDE_PLUGIN_ROOT derivation -------------------------------------------

CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKFLOW_STATE="${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh"
EXTRACT_ISSUE_REF="${CLAUDE_PLUGIN_ROOT}/skills/managing-work-items/scripts/extract-issue-ref.sh"

# PATH-shadow hook for bats: if a `workflow-state.sh` or `extract-issue-ref.sh`
# is found earlier on PATH, prefer those (used by test stubs).
if command -v workflow-state.sh >/dev/null 2>&1; then
  WORKFLOW_STATE="$(command -v workflow-state.sh)"
fi
if command -v extract-issue-ref.sh >/dev/null 2>&1; then
  EXTRACT_ISSUE_REF="$(command -v extract-issue-ref.sh)"
fi

# --- ID extraction from artifact filename ------------------------------------

case "$type" in
  feature) prefix="FEAT" ;;
  chore)   prefix="CHORE" ;;
  bug)     prefix="BUG" ;;
esac

artifact_base="$(basename "$artifact")"

if [[ ! "$artifact_base" =~ (${prefix}-[0-9]+) ]]; then
  echo "[warn] init-workflow: could not extract ${prefix}-NNN ID from filename: $artifact_base" >&2
  exit 1
fi
id="${BASH_REMATCH[1]}"

# --- composite execution -----------------------------------------------------

mkdir -p .sdlc/workflows

# Step 3: init
if ! bash "$WORKFLOW_STATE" init "$id" "$type" >/dev/null 2>&1; then
  # Run once more to surface stderr to the caller.
  bash "$WORKFLOW_STATE" init "$id" "$type" >/dev/null || true
  echo "[error] init-workflow: workflow-state.sh init failed for $id $type" >&2
  exit 1
fi

# Step 4: classify-init — stdout is the tier.
tier=""
if ! tier=$(bash "$WORKFLOW_STATE" classify-init "$id" "$artifact"); then
  echo "[error] init-workflow: workflow-state.sh classify-init failed for $id" >&2
  exit 1
fi
tier="${tier//$'\n'/}"
tier="${tier// /}"
if [ -z "$tier" ]; then
  echo "[error] init-workflow: classify-init returned empty tier for $id" >&2
  exit 1
fi

# Step 5: set-complexity
if ! bash "$WORKFLOW_STATE" set-complexity "$id" "$tier" >/dev/null 2>&1; then
  echo "[error] init-workflow: workflow-state.sh set-complexity failed for $id $tier" >&2
  exit 1
fi

# Step 6: active marker BEFORE advance so stop-hook firing mid-composite
# finds the marker.
printf '%s\n' "$id" > .sdlc/workflows/.active

# Step 7: advance
if ! bash "$WORKFLOW_STATE" advance "$id" "$artifact" >/dev/null 2>&1; then
  echo "[error] init-workflow: workflow-state.sh advance failed for $id" >&2
  exit 1
fi

# Step 8: extract-issue-ref — graceful. Empty or missing script is non-fatal.
issue_ref=""
if [ -x "$EXTRACT_ISSUE_REF" ] || command -v "$(basename "$EXTRACT_ISSUE_REF")" >/dev/null 2>&1; then
  # Suppress both failure and stderr — per I6, graceful degrade to "".
  issue_ref=$(bash "$EXTRACT_ISSUE_REF" "$artifact" 2>/dev/null || true)
  issue_ref="${issue_ref//$'\n'/}"
fi

# --- emit JSON ---------------------------------------------------------------

_have_jq() {
  command -v jq >/dev/null 2>&1
}

if _have_jq; then
  jq -n -c \
    --arg id "$id" \
    --arg type "$type" \
    --arg complexity "$tier" \
    --arg issueRef "$issue_ref" \
    '{id: $id, type: $type, complexity: $complexity, issueRef: $issueRef}'
else
  # None of the four values contain characters that require JSON escaping in
  # the happy paths this script supports; issue_ref is `#<digits>` or
  # `[A-Z][A-Z0-9]*-[0-9]+` or empty. Escape any embedded double-quote just in
  # case (defensive, matches findings-decision.sh's pattern).
  esc_id="${id//\"/\\\"}"
  esc_type="${type//\"/\\\"}"
  esc_complexity="${tier//\"/\\\"}"
  esc_issue_ref="${issue_ref//\"/\\\"}"
  printf '{"id":"%s","type":"%s","complexity":"%s","issueRef":"%s"}\n' \
    "$esc_id" "$esc_type" "$esc_complexity" "$esc_issue_ref"
fi

exit 0
