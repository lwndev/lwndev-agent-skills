#!/usr/bin/env bash
# check-deliverable.sh — Phase-scoped deliverable checkoff (FEAT-027 / FR-3).
#
# Usage: check-deliverable.sh <plan-file> <phase-N> <idx-or-text>
#
# Sibling to the plugin-shared check-acceptance.sh. Adds:
#   - Phase-scoping: all matching is restricted to the `### Phase <phase-N>:`
#     block (bounded by the next `### Phase` heading or EOF).
#   - Numeric-index dispatch: if <idx-or-text> matches ^[0-9]+$, it is treated
#     as a 1-based index into the phase block's deliverable lines (both `- [ ]`
#     and `- [x]` in document order, outside fenced code blocks). Anything with
#     a non-digit character is treated as a literal substring matcher with
#     identical semantics to check-acceptance.sh.
#
# Fence-aware: `- [ ]` / `- [x]` lines inside ``` / ~~~ fenced code blocks are
# never counted, enumerated, or flipped.
#
# Exit codes (mirrors check-acceptance.sh — one-off shape per NFR-2):
#   0  success — stdout is `checked` (flipped) or `already checked` (idempotent)
#   1  not found / plan missing / phase missing / index out of range
#   2  ambiguous — text matcher hits multiple unchecked `- [ ]` lines
#   3  usage error (missing / malformed args)

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "error: usage: check-deliverable.sh <plan-file> <phase-N> <idx-or-text>" >&2
  exit 3
fi

plan="$1"
phase_n="$2"
selector="$3"

if [[ ! "$phase_n" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: <phase-N> must be a positive integer, got: ${phase_n}" >&2
  exit 3
fi

if [ -z "$selector" ]; then
  echo "error: <idx-or-text> must be non-empty" >&2
  exit 3
fi

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# Determine dispatch mode: numeric index vs. literal substring.
is_index=0
if [[ "$selector" =~ ^[0-9]+$ ]]; then
  is_index=1
fi

# Scan pass:
#   Emits tab-separated records for deliverable lines within the target phase
#   block, outside fences:
#     <NR>\t<state>\t<line-text>
#   where <state> is `u` (unchecked `- [ ]`) or `c` (checked `- [x]`).
#
#   Also emits a trailing marker record `MARKER\t<code>` where <code> is one of:
#     phase-found   — the target phase heading was seen
#     no-phase      — no matching `### Phase <phase-N>:` heading
#
# Phase bounds: from the `### Phase <phase-N>:` heading up to (but not
# including) the next `### Phase` heading or EOF.
scan_output=$(
  tr -d '\r' < "$plan" \
    | awk -v phase_n="$phase_n" '
        BEGIN {
          in_fence = 0
          in_target = 0
          phase_seen = 0
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)

          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }

          # Phase heading detection (outside fences).
          if (!in_fence && match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            if (num == phase_n) {
              in_target = 1
              phase_seen = 1
            } else {
              in_target = 0
            }
            next
          }

          if (!in_target || in_fence) next

          # Deliverable detection — the standard `- [ ] ` / `- [x] ` form,
          # allowing leading indentation.
          if (match(line, /-[ ]\[[ ]\][ ]/)) {
            printf "%d\tu\t%s\n", NR, line
            next
          }
          if (match(line, /-[ ]\[[xX]\][ ]/)) {
            printf "%d\tc\t%s\n", NR, line
            next
          }
        }
        END {
          printf "MARKER\t%s\n", (phase_seen ? "phase-found" : "no-phase")
        }
      '
)

# Extract marker line (last MARKER record).
marker=$(printf '%s\n' "$scan_output" | awk -F'\t' '/^MARKER\t/ { m=$2 } END { print m }')

if [ "$marker" = "no-phase" ]; then
  echo "error: phase ${phase_n} not found in plan" >&2
  exit 1
fi

# Collect deliverable records (drop MARKER line).
records=$(printf '%s\n' "$scan_output" | awk -F'\t' '$1 != "MARKER" { print }')

# Count all deliverables in the phase block (u + c together), in document order.
total=0
if [ -n "$records" ]; then
  total=$(printf '%s\n' "$records" | grep -c . || true)
fi

if [ "$is_index" -eq 1 ]; then
  # Numeric index dispatch: 1-based into the phase's deliverable list.
  idx="$selector"
  if [ "$total" -eq 0 ] || [ "$idx" -lt 1 ] || [ "$idx" -gt "$total" ]; then
    echo "error: deliverable index ${idx} out of range (phase has ${total} deliverables)" >&2
    exit 1
  fi

  # Pick the idx-th record.
  chosen=$(printf '%s\n' "$records" | sed -n "${idx}p")
  chosen_nr=$(printf '%s' "$chosen" | awk -F'\t' '{ print $1 }')
  chosen_state=$(printf '%s' "$chosen" | awk -F'\t' '{ print $2 }')

  if [ "$chosen_state" = "c" ]; then
    echo "already checked"
    exit 0
  fi

  # Flip the targeted line.
  tmp="$(mktemp)"
  awk -v target="$chosen_nr" '
    NR == target { sub(/-[ ]\[[ ]\][ ]/, "- [x] ") }
    { print }
  ' "$plan" > "$tmp"
  mv "$tmp" "$plan"
  echo "checked"
  exit 0
fi

# Text-substring dispatch — mirror check-acceptance.sh semantics within the
# phase block. Collect unchecked and checked lines that contain the substring.
unchecked_nrs=()
checked_nrs=()
if [ -n "$records" ]; then
  while IFS=$'\t' read -r nr state text; do
    [ -z "$nr" ] && continue
    case "$text" in
      *"$selector"*)
        case "$state" in
          u) unchecked_nrs+=("$nr") ;;
          c) checked_nrs+=("$nr") ;;
        esac
        ;;
    esac
  done <<< "$records"
fi

u_count=${#unchecked_nrs[@]}
c_count=${#checked_nrs[@]}

if [ "$u_count" -eq 0 ] && [ "$c_count" -eq 0 ]; then
  echo "error: deliverable not found" >&2
  exit 1
fi

if [ "$u_count" -eq 0 ] && [ "$c_count" -gt 0 ]; then
  echo "already checked"
  exit 0
fi

if [ "$u_count" -gt 1 ]; then
  echo "error: ambiguous — ${u_count} lines match" >&2
  exit 2
fi

# Exactly one unchecked match — flip it.
target_line="${unchecked_nrs[0]}"
tmp="$(mktemp)"
awk -v target="$target_line" '
  NR == target { sub(/-[ ]\[[ ]\][ ]/, "- [x] ") }
  { print }
' "$plan" > "$tmp"
mv "$tmp" "$plan"
echo "checked"
exit 0
