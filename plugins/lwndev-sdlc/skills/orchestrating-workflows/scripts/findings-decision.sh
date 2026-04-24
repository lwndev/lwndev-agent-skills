#!/usr/bin/env bash
# findings-decision.sh — Resolve the reviewing-requirements Decision Flow
# branch for a given workflow (FEAT-028 FR-3).
#
# Usage: findings-decision.sh <ID> <stepIndex> <counts-json>
#
# Reads `.sdlc/workflows/<ID>.json` to pull `type` (feature|chore|bug) and
# `complexity` (low|medium|high). Applies the three-way Decision Flow
# (FEAT-015 semantics) using the counts JSON supplied on the command line:
#
#   1. errors == 0 && warnings == 0 && info == 0
#        → action: "advance",       reason: "zero findings"
#   2. errors > 0
#        → action: "pause-errors",  reason: "errors present"
#   3. errors == 0 && (warnings > 0 || info > 0)
#        - type in {chore, bug} AND complexity in {low, medium}
#            → action: "auto-advance",
#              reason: "chore|bug chain with complexity <= medium"
#        - otherwise (type == feature OR complexity == high)
#            → action: "prompt-user",
#              reason: "feature chain or high-complexity chore|bug"
#
# `<stepIndex>` is accepted for caller-audit consistency with every other
# workflow-state.sh-interacting subcommand. It is echoed into any stderr
# [info] / [warn] line the script emits; it does not affect the branch
# selection or the output JSON shape.
#
# Emits one JSON object on stdout:
#   {"action":"advance|auto-advance|prompt-user|pause-errors",
#    "reason":"<one-line>",
#    "type":"feature|chore|bug",
#    "complexity":"low|medium|high"}
#
# Uses jq when available; pure-bash fallback.
#
# Exit codes:
#   0 success (any of the four actions)
#   1 state file missing / unreadable / malformed / missing type or
#     complexity fields after FR-13 migration, or unparseable counts JSON
#   2 missing / malformed args (including invalid ID format)

set -euo pipefail

# --- arg parsing -------------------------------------------------------------

if [ "$#" -lt 3 ]; then
  echo "[error] findings-decision: usage: findings-decision.sh <ID> <stepIndex> <counts-json>" >&2
  exit 2
fi

id="$1"
step_index="$2"
counts_json="$3"

if [[ ! "$id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  echo "[error] findings-decision: invalid ID format: $id (expected FEAT-NNN, CHORE-NNN, or BUG-NNN)" >&2
  exit 2
fi

if [[ ! "$step_index" =~ ^[0-9]+$ ]]; then
  echo "[error] findings-decision: invalid stepIndex: $step_index (expected non-negative integer)" >&2
  exit 2
fi

# --- state file read ---------------------------------------------------------

state_file=".sdlc/workflows/${id}.json"

if [ ! -r "$state_file" ]; then
  echo "[error] findings-decision: state file not readable: $state_file (step $step_index)" >&2
  exit 1
fi

_have_jq() {
  command -v jq >/dev/null 2>&1
}

type=""
complexity=""

if _have_jq; then
  if ! jq -e '.type and .complexity' "$state_file" >/dev/null 2>&1; then
    echo "[error] findings-decision: state file malformed or missing type/complexity: $state_file (step $step_index)" >&2
    exit 1
  fi
  type="$(jq -r '.type' "$state_file")"
  complexity="$(jq -r '.complexity' "$state_file")"
else
  # pure-bash fallback: grep the two fields out with a tolerant regex.
  # Accept '"type":"feature"' / '"type": "feature"'.
  if ! type_line=$(grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | head -n1); then
    echo "[error] findings-decision: state file malformed or missing type: $state_file (step $step_index)" >&2
    exit 1
  fi
  type="${type_line#*\"type\"*:*\"}"
  type="${type%\"}"

  if ! complexity_line=$(grep -oE '"complexity"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" | head -n1); then
    echo "[error] findings-decision: state file malformed or missing complexity: $state_file (step $step_index)" >&2
    exit 1
  fi
  complexity="${complexity_line#*\"complexity\"*:*\"}"
  complexity="${complexity%\"}"
fi

if [ -z "$type" ] || [ "$type" = "null" ]; then
  echo "[error] findings-decision: state file missing type field after FR-13 migration: $state_file (step $step_index)" >&2
  exit 1
fi

if [ -z "$complexity" ] || [ "$complexity" = "null" ]; then
  echo "[error] findings-decision: state file missing complexity field after FR-13 migration: $state_file (step $step_index)" >&2
  exit 1
fi

# --- counts JSON parse -------------------------------------------------------

errors=""
warnings=""
info=""

if _have_jq; then
  if ! printf '%s' "$counts_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "[error] findings-decision: counts JSON unparseable or not an object: $counts_json (step $step_index)" >&2
    exit 1
  fi
  errors="$(printf '%s' "$counts_json" | jq -r '.errors // empty')"
  warnings="$(printf '%s' "$counts_json" | jq -r '.warnings // empty')"
  info="$(printf '%s' "$counts_json" | jq -r '.info // empty')"
else
  # Extremely tolerant pure-bash parse: '"errors":<int>'.
  parse_count() {
    local key="$1"
    local m
    m=$(printf '%s' "$counts_json" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*[0-9]+" | head -n1 || true)
    [ -z "$m" ] && return 1
    # Strip leading `"key" : ` portion, keep digits.
    echo "${m##*:}" | tr -d '[:space:]'
  }
  if ! errors=$(parse_count errors); then
    echo "[error] findings-decision: counts JSON missing errors field: $counts_json (step $step_index)" >&2
    exit 1
  fi
  if ! warnings=$(parse_count warnings); then
    echo "[error] findings-decision: counts JSON missing warnings field: $counts_json (step $step_index)" >&2
    exit 1
  fi
  if ! info=$(parse_count info); then
    echo "[error] findings-decision: counts JSON missing info field: $counts_json (step $step_index)" >&2
    exit 1
  fi
fi

# Validate each count is a non-negative integer.
for name in errors warnings info; do
  val="${!name}"
  if [[ -z "$val" || ! "$val" =~ ^[0-9]+$ ]]; then
    echo "[error] findings-decision: counts JSON field '$name' not a non-negative integer: $counts_json (step $step_index)" >&2
    exit 1
  fi
done

# --- Decision Flow -----------------------------------------------------------

action=""
reason=""

if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ] && [ "$info" -eq 0 ]; then
  action="advance"
  reason="zero findings"
elif [ "$errors" -gt 0 ]; then
  action="pause-errors"
  reason="errors present"
else
  # warnings > 0 || info > 0 (errors == 0 already known here)
  case "$type" in
    chore|bug)
      case "$complexity" in
        low|medium)
          action="auto-advance"
          reason="chore|bug chain with complexity <= medium"
          ;;
        *)
          action="prompt-user"
          reason="feature chain or high-complexity chore|bug"
          ;;
      esac
      ;;
    *)
      action="prompt-user"
      reason="feature chain or high-complexity chore|bug"
      ;;
  esac
fi

# --- emit JSON ---------------------------------------------------------------

if _have_jq; then
  jq -n -c \
    --arg action "$action" \
    --arg reason "$reason" \
    --arg type "$type" \
    --arg complexity "$complexity" \
    '{action: $action, reason: $reason, type: $type, complexity: $complexity}'
else
  # pure-bash JSON emission (no special chars in any of the four values)
  printf '{"action":"%s","reason":"%s","type":"%s","complexity":"%s"}\n' \
    "$action" "$reason" "$type" "$complexity"
fi

exit 0
