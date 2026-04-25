#!/usr/bin/env bash
# validate-phase-sizes.sh — Phase-size gate composer over
# `phase-complexity-budget.sh` (FEAT-029 / FR-5).
#
# Usage: validate-phase-sizes.sh <plan-file>
#
# Runs `phase-complexity-budget.sh <plan-file>` (FR-3), parses the per-phase
# JSON array, and reports every phase where `overBudget == true` and
# `override == null`. The dominant signal (the axis that scored opus,
# preferring steps > deliverables > files when multiple axes scored opus)
# is named in the warning line so the model can author the fix in one
# pass.
#
# Output:
#   no failing phases   stdout `ok`, exit 0
#   one or more failing stderr lists each on its own line as
#                       `[warn] phase <N>: over budget — <signal>=<value> exceeds opus threshold; either split (see split-phase-suggest.sh) or add **ComplexityOverride:** high to the phase block.`
#                       stdout empty, exit 1
#
# Exit codes:
#   0  ok.
#   1  one or more failing phases, plan I/O error, or upstream failure.
#   2  missing arg.
#
# Bash 3.2-compatible.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "error: usage: validate-phase-sizes.sh <plan-file>" >&2
  exit 2
fi

plan="$1"

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve `phase-complexity-budget.sh` next to this script (sibling).
# ---------------------------------------------------------------------------
script_dir="$(cd "$(dirname "$0")" && pwd)"
budget="${script_dir}/phase-complexity-budget.sh"
if [ ! -f "$budget" ]; then
  echo "error: phase-complexity-budget.sh not found at ${budget}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Invoke the budget script. Forward its stderr verbatim and propagate
# non-zero exits.
# ---------------------------------------------------------------------------
if ! json="$(bash "$budget" "$plan")"; then
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse the JSON. Use jq when available; awk fallback otherwise (the budget
# script's printf fallback emits a flat single-line array).
# ---------------------------------------------------------------------------
fail_lines=""

emit_fail() {
  local n="$1"
  local signal="$2"
  local value="$3"
  local line="[warn] phase ${n}: over budget — ${signal}=${value} exceeds opus threshold; either split (see split-phase-suggest.sh) or add **ComplexityOverride:** high to the phase block."
  if [ -z "$fail_lines" ]; then
    fail_lines="$line"
  else
    fail_lines="${fail_lines}"$'\n'"$line"
  fi
}

if command -v jq >/dev/null 2>&1; then
  # Stream rows of:
  #   <phase>\t<overBudget>\t<override>\t<steps>\t<deliverables>\t<files>
  while IFS=$'\t' read -r p over orv steps deliv files; do
    [ -z "$p" ] && continue
    if [ "$over" != "true" ]; then
      continue
    fi
    if [ "$orv" != "null" ]; then
      continue
    fi
    # Pick the dominant signal: steps > deliverables > files.
    if [ "$steps" -ge 8 ]; then
      emit_fail "$p" "steps" "$steps"
    elif [ "$deliv" -ge 10 ]; then
      emit_fail "$p" "deliverables" "$deliv"
    elif [ "$files" -ge 9 ]; then
      emit_fail "$p" "files" "$files"
    else
      # Defensive fallback — the budget script claimed overBudget but no
      # axis met the opus threshold. Surface the steps count so the model
      # still gets actionable text.
      emit_fail "$p" "steps" "$steps"
    fi
  done < <(printf '%s' "$json" | jq -r '.[] | [.phase,(.overBudget|tostring),(.override|tostring),.signals.steps,.signals.deliverables,.signals.files] | @tsv')
else
  # Pure-awk fallback: split the flat array on `},{` boundaries and grep
  # the numeric fields out of each object. Capture into a variable so the
  # `while read` loop runs in the current shell (the subshell pipe form
  # would lose any `fail_lines` mutations).
  rows="$(printf '%s' "$json" | awk '
    {
      s = $0
      # Strip leading [ and trailing ].
      sub(/^[[:space:]]*\[/, "", s)
      sub(/\][[:space:]]*$/, "", s)
      while (length(s) > 0) {
        # Find the next "}" — objects are flat (no nested braces).
        i = index(s, "}")
        if (i == 0) break
        obj = substr(s, 1, i)
        s = substr(s, i + 1)
        sub(/^[ ,]+/, "", s)
        # Extract phase number.
        if (match(obj, /"phase":[0-9]+/)) {
          p = substr(obj, RSTART + 8, RLENGTH - 8)
        } else { p = "" }
        # overBudget true|false
        ob = (obj ~ /"overBudget":true/) ? "true" : "false"
        # override null vs string
        if (obj ~ /"override":null/) ovr = "null"
        else if (match(obj, /"override":"[^"]*"/)) {
          ovr = substr(obj, RSTART + 12, RLENGTH - 13)
        } else { ovr = "null" }
        # steps, deliverables, files
        st = ""; dv = ""; fl = ""
        if (match(obj, /"steps":[0-9]+/)) st = substr(obj, RSTART + 8, RLENGTH - 8)
        if (match(obj, /"deliverables":[0-9]+/)) dv = substr(obj, RSTART + 15, RLENGTH - 15)
        if (match(obj, /"files":[0-9]+/)) fl = substr(obj, RSTART + 8, RLENGTH - 8)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", p, ob, ovr, st, dv, fl
      }
    }
  ')"
  while IFS=$'\t' read -r p over orv steps deliv files; do
    [ -z "$p" ] && continue
    if [ "$over" != "true" ]; then continue; fi
    if [ "$orv" != "null" ]; then continue; fi
    if [ "$steps" -ge 8 ]; then
      emit_fail "$p" "steps" "$steps"
    elif [ "$deliv" -ge 10 ]; then
      emit_fail "$p" "deliverables" "$deliv"
    elif [ "$files" -ge 9 ]; then
      emit_fail "$p" "files" "$files"
    else
      emit_fail "$p" "steps" "$steps"
    fi
  done <<< "$rows"
fi

if [ -n "$fail_lines" ]; then
  printf '%s\n' "$fail_lines" >&2
  exit 1
fi

echo "ok"
exit 0
