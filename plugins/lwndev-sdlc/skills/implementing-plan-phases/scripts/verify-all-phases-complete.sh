#!/usr/bin/env bash
# verify-all-phases-complete.sh — Gate PR creation on all phases being complete (FEAT-027 / FR-6).
#
# Usage: verify-all-phases-complete.sh <plan-file>
#
# Parses every `### Phase <N>: <name>` heading and the first `**Status:**`
# line inside each phase block. Fence-aware: `**Status:**` lines inside
# ``` / ~~~ fenced blocks are ignored.
#
# Exit codes:
#   0  all phases `✅ Complete` — stdout `all phases complete`.
#   1  one or more phases not complete — stdout is a JSON object:
#        {"incomplete":[{"phase":<N>,"name":"...","status":"Pending|in-progress"},...]}
#      OR the plan file is missing / unreadable / has no `### Phase` blocks
#      (stderr `[error] no phase blocks found in plan`).
#   2  missing arg (usage error).
#
# Dependencies:
#   Optional `jq` for JSON assembly; pure-bash `printf` fallback otherwise.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "error: usage: verify-all-phases-complete.sh <plan-file>" >&2
  exit 2
fi

plan="$1"

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

parsed=$(
  tr -d '\r' < "$plan" \
    | awk '
        BEGIN {
          in_fence = 0
          have_phase = 0
          cur_num = ""
          cur_name = ""
          cur_state = ""
        }
        function emit() {
          if (have_phase) {
            printf "%s\t%s\t%s\n", cur_num, cur_name, cur_state
          }
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)
          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next

          if (match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            emit()
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            name = line
            sub(/^###[ ]+Phase[ ]+[0-9]+:[ ]*/, "", name)
            cur_num = num
            cur_name = name
            cur_state = ""
            have_phase = 1
            next
          }

          if (!have_phase) next

          if (cur_state == "" && match(line, /^\*\*Status:\*\*[ ]+/)) {
            val = line
            sub(/^\*\*Status:\*\*[ ]+/, "", val)
            sub(/[ \t]+$/, "", val)
            if (val == "Pending") {
              cur_state = "Pending"
            } else if (index(val, "In Progress") > 0) {
              cur_state = "in-progress"
            } else if (index(val, "Complete") > 0) {
              cur_state = "complete"
            } else {
              cur_state = "unknown"
            }
          }
        }
        END { emit() }
      '
)

if [ -z "$parsed" ]; then
  echo "[error] no phase blocks found in plan" >&2
  exit 1
fi

# Build incomplete list.
incomplete_entries=()
while IFS=$'\t' read -r num name state; do
  [ -z "$num" ] && continue
  if [ "$state" != "complete" ]; then
    # Default unknown/empty state to Pending for reporting.
    report_state="$state"
    if [ -z "$report_state" ] || [ "$report_state" = "unknown" ]; then
      report_state="Pending"
    fi
    incomplete_entries+=("${num}"$'\t'"${name}"$'\t'"${report_state}")
  fi
done <<< "$parsed"

if [ "${#incomplete_entries[@]}" -eq 0 ]; then
  echo "all phases complete"
  exit 0
fi

# Emit the incomplete JSON object.
if command -v jq >/dev/null 2>&1; then
  # Build an array of objects via jq -s + input transformation.
  json=$(
    printf '%s\n' "${incomplete_entries[@]}" \
      | jq -R -s '
          split("\n")
          | map(select(length > 0))
          | map(split("\t"))
          | map({phase: (.[0] | tonumber), name: .[1], status: .[2]})
          | {incomplete: .}
        '
  )
  printf '%s\n' "$json"
else
  # Pure-bash JSON assembly.
  printf '{"incomplete":['
  first=1
  for entry in "${incomplete_entries[@]}"; do
    IFS=$'\t' read -r num name state <<< "$entry"
    esc="${name//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf ','
    fi
    printf '{"phase":%s,"name":"%s","status":"%s"}' "$num" "$esc" "$state"
  done
  printf ']}\n'
fi

exit 1
