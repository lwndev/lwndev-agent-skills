#!/usr/bin/env bash
# validate-plan-dag.sh — Validate the phase dependency graph in an
# implementation plan (FEAT-029 / FR-2).
#
# Usage: validate-plan-dag.sh <plan-file>
#
# Scans `### Phase <N>: <name>` headings, extracts each block's first
# `**Depends on:**` line outside fenced code blocks, parses the references,
# and runs two checks:
#
#   1. Reference resolution: every `Phase <N>` token must reference a phase
#      that exists in the plan. Tokens that don't match `Phase <N>` (e.g.,
#      `PR #123`) are silently ignored — this lets free-text rationale
#      coexist with the strict parser. `none` and the absence of a
#      `**Depends on:**` line both mean "no dependencies".
#
#   2. Cycle detection: Kahn's algorithm topological sort. On cycle, every
#      phase still in the residual graph is listed (NFR-2: the model needs
#      the full cycle to fix it in one pass).
#
# Exit codes:
#   0  ok — stdout `ok`.
#   1  cycle, unresolved reference, or I/O error. Stderr describes the
#      offender(s).
#   2  missing arg.
#
# Bash 3.2-compatible (macOS ships /bin/bash 3.2). No associative arrays,
# no mapfile, no ${var,,}.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "error: usage: validate-plan-dag.sh <plan-file>" >&2
  exit 2
fi

plan="$1"

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse phases. awk emits one tab-separated record per phase:
#   <num>\t<deps-joined-by-semicolon>
# Deps may be empty.
# ---------------------------------------------------------------------------
parsed=$(
  tr -d '\r' < "$plan" \
    | awk '
        BEGIN {
          in_fence = 0
          have_phase = 0
          cur_num = ""
          cur_deps = ""
          deps_seen = 0
        }
        function emit() {
          if (have_phase) {
            printf "%s\t%s\n", cur_num, cur_deps
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
            cur_num = num
            cur_deps = ""
            deps_seen = 0
            have_phase = 1
            next
          }

          if (!have_phase) next

          # Only the FIRST **Depends on:** line counts.
          if (!deps_seen && match(line, /^\*\*Depends on:\*\*[ ]+/)) {
            deps_seen = 1
            val = line
            sub(/^\*\*Depends on:\*\*[ ]+/, "", val)
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

phase_nums=()
phase_deps=()

while IFS=$'\t' read -r num deps; do
  [ -z "$num" ] && continue
  phase_nums+=("$num")
  phase_deps+=("$deps")
done <<< "$parsed"

total=${#phase_nums[@]}

# ---------------------------------------------------------------------------
# Reference resolution: every dep must name an existing phase.
# ---------------------------------------------------------------------------
phase_exists() {
  local want="$1"
  local j
  for j in "${!phase_nums[@]}"; do
    if [ "${phase_nums[$j]}" = "$want" ]; then
      return 0
    fi
  done
  return 1
}

for i in "${!phase_nums[@]}"; do
  num="${phase_nums[$i]}"
  deps="${phase_deps[$i]}"
  [ -z "$deps" ] && continue
  IFS=';' read -ra dep_arr <<< "$deps"
  for dep in "${dep_arr[@]}"; do
    [ -z "$dep" ] && continue
    if ! phase_exists "$dep"; then
      echo "error: phase ${num} depends on non-existent phase ${dep}" >&2
      exit 1
    fi
  done
done

# ---------------------------------------------------------------------------
# Cycle detection via Kahn's algorithm.
#
# In-degrees: positional array `indeg[i]` parallel to phase_nums[i].
# At each iteration, drain a node with indeg==0, decrement indegrees of
# every dependent (i.e., every phase whose deps include this node).
# If the residual count after draining is non-zero, the residual is the
# cycle (or part of it).
# ---------------------------------------------------------------------------
indeg=()
for i in "${!phase_nums[@]}"; do
  deps="${phase_deps[$i]}"
  if [ -z "$deps" ]; then
    indeg+=("0")
  else
    # Count non-empty dep tokens.
    count=0
    IFS=';' read -ra dep_arr <<< "$deps"
    for dep in "${dep_arr[@]}"; do
      [ -z "$dep" ] && continue
      count=$((count + 1))
    done
    indeg+=("$count")
  fi
done

# `removed[i]` tracks whether the node has been drained.
removed=()
for i in "${!phase_nums[@]}"; do
  removed+=("0")
done

drained_count=0
while :; do
  picked=-1
  for i in "${!phase_nums[@]}"; do
    if [ "${removed[$i]}" = "0" ] && [ "${indeg[$i]}" = "0" ]; then
      picked=$i
      break
    fi
  done
  if [ "$picked" -lt 0 ]; then
    break
  fi
  removed[$picked]=1
  drained_count=$((drained_count + 1))
  drained_num="${phase_nums[$picked]}"
  # Decrement indeg of every still-present node whose deps contain drained_num.
  for j in "${!phase_nums[@]}"; do
    [ "${removed[$j]}" = "1" ] && continue
    deps="${phase_deps[$j]}"
    [ -z "$deps" ] && continue
    IFS=';' read -ra dep_arr <<< "$deps"
    for dep in "${dep_arr[@]}"; do
      if [ "$dep" = "$drained_num" ]; then
        indeg[$j]=$((${indeg[$j]} - 1))
      fi
    done
  done
done

if [ "$drained_count" -lt "$total" ]; then
  # Residual nodes form (or contain) the cycle.
  cycle_list=""
  for i in "${!phase_nums[@]}"; do
    if [ "${removed[$i]}" = "0" ]; then
      if [ -z "$cycle_list" ]; then cycle_list="${phase_nums[$i]}"
      else cycle_list="${cycle_list}, ${phase_nums[$i]}"
      fi
    fi
  done
  echo "error: cycle detected involving phases ${cycle_list}" >&2
  exit 1
fi

echo "ok"
exit 0
