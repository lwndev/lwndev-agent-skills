#!/usr/bin/env bash
# next-pending-phase.sh — Pick the next actionable phase from an implementation plan (FEAT-027 / FR-1).
#
# Usage: next-pending-phase.sh <plan-file>
#
# Parses `### Phase <N>: <name>` headings and each block's `**Status:**` line.
# Fence-aware: `**Status:**` lines inside ``` / ~~~ fenced blocks are ignored.
# Recognizes the three canonical states: `Pending`, `🔄 In Progress`, `✅ Complete`.
#
# Selection rule (two-tier):
#   1. If a phase is `🔄 In Progress`, resume it.
#   2. Otherwise pick the lowest-numbered `Pending` phase whose prerequisites
#      are satisfied (all lower-numbered phases Complete, AND any explicit
#      `**Depends on:** Phase <N>[, Phase <M>...]` line adjacent to the status
#      is satisfied).
#
# Exit codes:
#   0  success — stdout is one JSON object describing the outcome:
#         {"phase":<N>,"name":"<name>"}                            (happy path)
#         {"phase":null,"reason":"all-complete"}                   (all complete)
#         {"phase":<N>,"name":"<name>","reason":"resume-in-progress"} (resume)
#         {"phase":null,"reason":"blocked","blockedOn":[<N>,...]}  (blocked)
#   1  plan file missing / unreadable, OR no phase blocks found,
#      OR a phase block has no `**Status:**` line.
#   2  missing arg (usage error).
#
# Dependencies:
#   Optional `jq` for JSON assembly; pure-bash `printf` fallback otherwise.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "error: usage: next-pending-phase.sh <plan-file>" >&2
  exit 2
fi

plan="$1"

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# Parse phases into three parallel arrays via awk:
#   phase_nums[]   — phase numbers in document order
#   phase_names[]  — phase names
#   phase_states[] — one of: Pending | in-progress | complete | <empty>
#   phase_deps[]   — semicolon-joined dependency phase numbers (may be empty)
#
# awk emits one record per phase to stdout, tab-separated:
#   <num>\t<name>\t<state>\t<deps-joined>
parsed=$(
  tr -d '\r' < "$plan" \
    | awk '
        BEGIN {
          in_fence = 0
          have_phase = 0
          cur_num = ""
          cur_name = ""
          cur_state = ""
          cur_deps = ""
        }
        function emit() {
          if (have_phase) {
            printf "%s\t%s\t%s\t%s\n", cur_num, cur_name, cur_state, cur_deps
          }
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)
          # Fence toggles are detected BEFORE any other match.
          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next

          # Phase heading.
          if (match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            emit()
            # Extract number and name.
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            name = line
            sub(/^###[ ]+Phase[ ]+[0-9]+:[ ]*/, "", name)
            cur_num = num
            cur_name = name
            cur_state = ""
            cur_deps = ""
            have_phase = 1
            next
          }

          if (!have_phase) next

          # **Status:** line — pick the first one in this phase block.
          if (cur_state == "" && match(line, /^\*\*Status:\*\*[ ]+/)) {
            val = line
            sub(/^\*\*Status:\*\*[ ]+/, "", val)
            # Trim trailing whitespace.
            sub(/[ \t]+$/, "", val)
            # Canonicalize.
            if (val == "Pending") {
              cur_state = "Pending"
            } else if (index(val, "In Progress") > 0) {
              cur_state = "in-progress"
            } else if (index(val, "Complete") > 0) {
              cur_state = "complete"
            } else {
              cur_state = "unknown:" val
            }
            next
          }

          # **Depends on:** Phase N[, Phase M...] — collect referenced numbers.
          if (match(line, /^\*\*Depends on:\*\*[ ]+/)) {
            val = line
            sub(/^\*\*Depends on:\*\*[ ]+/, "", val)
            # Find every "Phase <N>" occurrence.
            tmp = val
            while (match(tmp, /Phase[ ]+[0-9]+/)) {
              tok = substr(tmp, RSTART, RLENGTH)
              sub(/^Phase[ ]+/, "", tok)
              if (cur_deps == "") cur_deps = tok
              else cur_deps = cur_deps ";" tok
              tmp = substr(tmp, RSTART + RLENGTH)
            }
            next
          }
        }
        END { emit() }
      '
)

if [ -z "$parsed" ]; then
  echo "error: no \`### Phase\` blocks found in ${plan}" >&2
  exit 1
fi

# Read parsed records into arrays.
phase_nums=()
phase_names=()
phase_states=()
phase_deps=()

while IFS=$'\t' read -r num name state deps; do
  [ -z "$num" ] && continue
  phase_nums+=("$num")
  phase_names+=("$name")
  phase_states+=("$state")
  phase_deps+=("$deps")
done <<< "$parsed"

total=${#phase_nums[@]}

# Validate every phase has a recognized status.
for i in "${!phase_nums[@]}"; do
  state="${phase_states[$i]}"
  num="${phase_nums[$i]}"
  if [ -z "$state" ]; then
    echo "error: phase ${num} has no \`**Status:**\` line" >&2
    exit 1
  fi
  case "$state" in
    Pending|in-progress|complete) : ;;
    *)
      echo "error: phase ${num} has unrecognized status: ${state#unknown:}" >&2
      exit 1
      ;;
  esac
done

# Helper: emit a JSON object via jq when available, printf fallback otherwise.
emit_happy() {
  local num="$1" name="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson phase "$num" --arg name "$name" \
      '{phase:$phase,name:$name}'
  else
    # Escape double quotes + backslashes in name for JSON.
    local esc="${name//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"phase":%s,"name":"%s"}\n' "$num" "$esc"
  fi
}

emit_resume() {
  local num="$1" name="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson phase "$num" --arg name "$name" \
      '{phase:$phase,name:$name,reason:"resume-in-progress"}'
  else
    local esc="${name//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"phase":%s,"name":"%s","reason":"resume-in-progress"}\n' "$num" "$esc"
  fi
}

emit_all_complete() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn '{phase:null,reason:"all-complete"}'
  else
    printf '{"phase":null,"reason":"all-complete"}\n'
  fi
}

emit_blocked() {
  local blocked_csv="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson blockedOn "[${blocked_csv}]" \
      '{phase:null,reason:"blocked",blockedOn:$blockedOn}'
  else
    printf '{"phase":null,"reason":"blocked","blockedOn":[%s]}\n' "$blocked_csv"
  fi
}

# Rule 1: resume in-progress phase if any (first one wins).
for i in "${!phase_nums[@]}"; do
  if [ "${phase_states[$i]}" = "in-progress" ]; then
    emit_resume "${phase_nums[$i]}" "${phase_names[$i]}"
    exit 0
  fi
done

# Rule 2: if all complete, report all-complete.
all_complete=1
for s in "${phase_states[@]}"; do
  if [ "$s" != "complete" ]; then
    all_complete=0
    break
  fi
done
if [ "$all_complete" -eq 1 ]; then
  emit_all_complete
  exit 0
fi

# Build lookup: phase-number → state (for dependency satisfaction checks).
# Bash 3.2 lacks associative arrays on some installs, so we use a positional map.
num_to_state_lookup() {
  local want="$1"
  local j
  for j in "${!phase_nums[@]}"; do
    if [ "${phase_nums[$j]}" = "$want" ]; then
      printf '%s\n' "${phase_states[$j]}"
      return 0
    fi
  done
  printf 'missing\n'
}

# Rule 3: pick lowest-numbered Pending phase whose prereqs are satisfied.
# Prereqs = (all lower-numbered phases are complete) AND (all Depends-on refs are complete).
collected_blockers=()
for i in "${!phase_nums[@]}"; do
  if [ "${phase_states[$i]}" != "Pending" ]; then
    continue
  fi
  target_num="${phase_nums[$i]}"
  blockers=""

  # Lower-numbered must be complete.
  for j in "${!phase_nums[@]}"; do
    other_num="${phase_nums[$j]}"
    if [ "$other_num" -lt "$target_num" ] && [ "${phase_states[$j]}" != "complete" ]; then
      if [ -z "$blockers" ]; then blockers="$other_num"
      else blockers="$blockers,$other_num"
      fi
    fi
  done

  # Explicit Depends-on references.
  deps="${phase_deps[$i]}"
  if [ -n "$deps" ]; then
    IFS=';' read -ra dep_arr <<< "$deps"
    for dep in "${dep_arr[@]}"; do
      [ -z "$dep" ] && continue
      dep_state=$(num_to_state_lookup "$dep")
      if [ "$dep_state" != "complete" ]; then
        # Only add if not already present in blockers.
        case ",$blockers," in
          *",$dep,"*) : ;;
          *)
            if [ -z "$blockers" ]; then blockers="$dep"
            else blockers="$blockers,$dep"
            fi
            ;;
        esac
      fi
    done
  fi

  if [ -z "$blockers" ]; then
    emit_happy "$target_num" "${phase_names[$i]}"
    exit 0
  else
    # Track the first Pending phase's blockers as the canonical blocked report.
    if [ "${#collected_blockers[@]}" -eq 0 ]; then
      collected_blockers=("$blockers")
    fi
  fi
done

# No pending phase was selectable. Report blockers for the earliest Pending phase.
if [ "${#collected_blockers[@]}" -gt 0 ]; then
  emit_blocked "${collected_blockers[0]}"
  exit 0
fi

# Fallback: shouldn't reach here — all_complete was not 1 yet no Pending phase found.
echo "error: unexpected state — no Pending, in-progress, or all-complete classification" >&2
exit 1
