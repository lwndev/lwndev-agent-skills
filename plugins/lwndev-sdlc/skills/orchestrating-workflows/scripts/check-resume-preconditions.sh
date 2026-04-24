#!/usr/bin/env bash
# check-resume-preconditions.sh — Resume-gate composite (FEAT-028 FR-6).
#
# Usage: check-resume-preconditions.sh <ID>
#
# Pass-through composite: reads `.sdlc/workflows/<ID>.json` via
# `workflow-state.sh status`, re-runs the persisted-complexity recompute via
# `workflow-state.sh resume-recompute`, and projects a single flat JSON object
# to stdout the orchestrator can feed directly into its resume branch.
#
# NOTE: this script does NOT re-read the requirement document, does NOT
# downgrade complexity, and does NOT expose a manual-override knob. The
# FEAT-014 escape-hatch for an explicit downgrade is
# `workflow-state.sh set-complexity` (not `set-model-override`), which is
# out of scope for this script.
#
# `resume-recompute`'s stderr (including any
#   `[model] Work-item complexity upgraded ...`
# line it may emit) is relayed verbatim to the script's stderr for the
# orchestrator to echo to the user.
#
# CLAUDE_PLUGIN_ROOT derivation: three levels up from this script's directory.
#   scripts/ -> orchestrating-workflows/ -> skills/ -> lwndev-sdlc/
#
# Stdout: one JSON object
#   {
#     "type": "feature|chore|bug",
#     "status": "in-progress|paused|failed|complete",
#     "pauseReason": "plan-approval|pr-review|review-findings|null",
#     "currentStep": <int>,
#     "chainTable": "feature|chore|bug",
#     "complexity": "low|medium|high",
#     "complexityStage": "init|post-plan"
#   }
#
# `pauseReason` is JSON `null` when `status != "paused"`.
# `chainTable` always equals `type`.
#
# Uses jq when available; pure-bash fallback.
#
# Exit codes:
#   0 any recognised state
#   1 missing / unreadable state file, malformed downstream JSON, or
#     downstream subcommand non-zero exit
#   2 missing / malformed args

set -euo pipefail

# --- arg parsing -------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  echo "[error] check-resume-preconditions: usage: check-resume-preconditions.sh <ID>" >&2
  exit 2
fi

id="$1"

if [[ ! "$id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  echo "[error] check-resume-preconditions: invalid ID format: $id (expected FEAT-NNN, CHORE-NNN, or BUG-NNN)" >&2
  exit 2
fi

# --- state file sanity check -------------------------------------------------

state_file=".sdlc/workflows/${id}.json"

if [ ! -r "$state_file" ]; then
  echo "[error] check-resume-preconditions: state file not readable: $state_file" >&2
  exit 1
fi

# --- CLAUDE_PLUGIN_ROOT derivation -------------------------------------------

CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKFLOW_STATE="${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh"

# PATH-shadow hook for bats: if a `workflow-state.sh` is found earlier on
# PATH, prefer that (used by test stubs).
if command -v workflow-state.sh >/dev/null 2>&1; then
  WORKFLOW_STATE="$(command -v workflow-state.sh)"
fi

_have_jq() {
  command -v jq >/dev/null 2>&1
}

# --- step 1: workflow-state.sh status ---------------------------------------

status_json=""
if ! status_json=$(bash "$WORKFLOW_STATE" status "$id" 2>&1); then
  echo "[error] check-resume-preconditions: workflow-state.sh status failed for $id" >&2
  # Relay the stub/real stderr verbatim if present.
  printf '%s\n' "$status_json" >&2
  exit 1
fi

# --- step 2: resume-recompute (stderr relayed verbatim) ---------------------

recompute_err=""
recompute_tmp=$(mktemp)
if ! bash "$WORKFLOW_STATE" resume-recompute "$id" >/dev/null 2>"$recompute_tmp"; then
  # Relay captured stderr then fail.
  cat "$recompute_tmp" >&2
  rm -f "$recompute_tmp"
  echo "[error] check-resume-preconditions: workflow-state.sh resume-recompute failed for $id" >&2
  exit 1
fi
# Relay stderr verbatim even on success (captures [model] upgrade lines).
cat "$recompute_tmp" >&2
rm -f "$recompute_tmp"

# --- step 3: read projected fields -------------------------------------------
#
# `resume-recompute` may have mutated the state file (upgrade-only). Re-read
# complexity/complexityStage from the file of record, and read everything
# else from the earlier `status` JSON.

_extract_field() {
  # _extract_field <json-blob> <key> — pure-bash fallback extractor.
  local blob="$1"
  local key="$2"
  local line
  line=$(printf '%s' "$blob" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[0-9]+|null)" | head -n1 || true)
  if [ -z "$line" ]; then
    return 1
  fi
  local val="${line#*:}"
  val="${val## }"
  val="${val#\"}"
  val="${val%\"}"
  printf '%s' "$val"
}

type=""
status=""
pause_reason=""
current_step=""
complexity=""
complexity_stage=""

if _have_jq; then
  # Validate status JSON is parseable.
  if ! printf '%s' "$status_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "[error] check-resume-preconditions: malformed JSON from workflow-state.sh status" >&2
    exit 1
  fi
  type=$(printf '%s' "$status_json" | jq -r '.type // empty')
  status=$(printf '%s' "$status_json" | jq -r '.status // empty')
  pause_reason=$(printf '%s' "$status_json" | jq -r '.pauseReason // ""')
  current_step=$(printf '%s' "$status_json" | jq -r '.currentStep // 0')

  # Re-read mutable fields from the state file after resume-recompute.
  complexity=$(jq -r '.complexity // ""' "$state_file")
  complexity_stage=$(jq -r '.complexityStage // "init"' "$state_file")
else
  type=$(_extract_field "$status_json" type) || {
    echo "[error] check-resume-preconditions: missing type in status output" >&2
    exit 1
  }
  status=$(_extract_field "$status_json" status) || {
    echo "[error] check-resume-preconditions: missing status in status output" >&2
    exit 1
  }
  pause_reason=$(_extract_field "$status_json" pauseReason || true)
  current_step=$(_extract_field "$status_json" currentStep || echo "0")

  complexity=$(_extract_field "$(cat "$state_file")" complexity || echo "")
  complexity_stage=$(_extract_field "$(cat "$state_file")" complexityStage || echo "init")
fi

# Validate required fields.
case "$type" in
  feature|chore|bug) ;;
  *)
    echo "[error] check-resume-preconditions: invalid type '$type' in state for $id" >&2
    exit 1
    ;;
esac

case "$status" in
  in-progress|paused|failed|complete) ;;
  *)
    echo "[error] check-resume-preconditions: invalid status '$status' in state for $id" >&2
    exit 1
    ;;
esac

if [[ ! "$current_step" =~ ^[0-9]+$ ]]; then
  current_step="0"
fi

# When status != "paused", pauseReason becomes JSON null.
if [ "$status" != "paused" ]; then
  pause_reason=""
fi
# Normalise jq's sentinel for absent values.
if [ "$pause_reason" = "null" ]; then
  pause_reason=""
fi

# complexityStage defaults to init if the field is absent.
if [ -z "$complexity_stage" ]; then
  complexity_stage="init"
fi

# chainTable always equals type.
chain_table="$type"

# --- emit JSON ---------------------------------------------------------------

if _have_jq; then
  if [ -n "$pause_reason" ]; then
    jq -n -c \
      --arg type "$type" \
      --arg status "$status" \
      --arg pauseReason "$pause_reason" \
      --argjson currentStep "$current_step" \
      --arg chainTable "$chain_table" \
      --arg complexity "$complexity" \
      --arg complexityStage "$complexity_stage" \
      '{type: $type, status: $status, pauseReason: $pauseReason, currentStep: $currentStep, chainTable: $chainTable, complexity: $complexity, complexityStage: $complexityStage}'
  else
    jq -n -c \
      --arg type "$type" \
      --arg status "$status" \
      --argjson currentStep "$current_step" \
      --arg chainTable "$chain_table" \
      --arg complexity "$complexity" \
      --arg complexityStage "$complexity_stage" \
      '{type: $type, status: $status, pauseReason: null, currentStep: $currentStep, chainTable: $chainTable, complexity: $complexity, complexityStage: $complexityStage}'
  fi
else
  # Pure-bash JSON emission.
  if [ -n "$pause_reason" ]; then
    pause_field="\"${pause_reason//\"/\\\"}\""
  else
    pause_field="null"
  fi
  printf '{"type":"%s","status":"%s","pauseReason":%s,"currentStep":%s,"chainTable":"%s","complexity":"%s","complexityStage":"%s"}\n' \
    "$type" "$status" "$pause_field" "$current_step" "$chain_table" "$complexity" "$complexity_stage"
fi

exit 0
