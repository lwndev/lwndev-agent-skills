#!/usr/bin/env bash
# plan-status-marker.sh — Update the `**Status:**` line for a specific phase (FEAT-027 / FR-2).
#
# Usage: plan-status-marker.sh <plan-file> <phase-N> <state>
#
# <state> tokens (canonical input → written value):
#   Pending       → `**Status:** Pending`
#   in-progress   → `**Status:** 🔄 In Progress`   (emoji emitted by script)
#   complete      → `**Status:** ✅ Complete`       (emoji emitted by script)
#
# Scope: the edit applies only inside the `### Phase <phase-N>:` block,
# bounded by the next `### Phase` heading or EOF. `**Status:**` lines inside
# fenced ``` / ~~~ code blocks are not considered real status and never edited.
#
# Idempotent: if the target line already matches the requested state, emit
# `already set` and exit 0 without rewriting.
#
# Exit codes:
#   0  success — stdout is `transitioned` (wrote) or `already set` (no-op).
#   1  plan missing / unreadable, no matching phase block, or no `**Status:**`
#      line inside the matched block (outside fences).
#   2  missing / malformed args (non-positive-integer phase; unknown state).

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "error: usage: plan-status-marker.sh <plan-file> <phase-N> <state>" >&2
  exit 2
fi

plan="$1"
phase_n="$2"
state="$3"

if [[ ! "$phase_n" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: <phase-N> must be a positive integer, got: ${phase_n}" >&2
  exit 2
fi

case "$state" in
  Pending)     target_status='Pending' ;;
  in-progress) target_status=$'\xf0\x9f\x94\x84 In Progress' ;;  # 🔄
  complete)    target_status=$'\xe2\x9c\x85 Complete' ;;           # ✅
  *)
    echo "error: <state> must be one of: Pending | in-progress | complete (got: ${state})" >&2
    exit 2
    ;;
esac

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# Single-pass awk:
#   1. Track fenced-block state.
#   2. Find `### Phase <phase_n>:` heading.
#   3. Inside that block (until next `### Phase` heading or EOF), find the
#      FIRST `**Status:**` line that is not inside a fenced block.
#   4. Write "transitioned" or "already set" to stderr via a marker prefix,
#      emit rewritten file to stdout, then the orchestration below splits.
#
# Marker is emitted to stdout as a first line with a sentinel so the outer
# shell knows whether a rewrite happened or it was already set. We then strip
# the marker line before writing back.

tmp="$(mktemp)"
tmp_marker="$(mktemp)"

# Normalize line endings on read; preserve original on write would require
# sniffing. Per the plan, we CRLF-safe normalize on read and emit LF on write.
# Note: this may change CRLF files to LF. The plan's fixtures are LF-only.
tr -d '\r' < "$plan" | awk -v phase_n="$phase_n" -v target="$target_status" -v marker_file="$tmp_marker" '
  BEGIN {
    in_fence = 0
    in_target_block = 0
    status_written = 0
    phase_seen = 0
    marker = "not-found"
  }
  function write_marker(value) {
    print value > marker_file
    close(marker_file)
  }
  {
    line = $0
    stripped = line
    sub(/^[ \t]+/, "", stripped)

    if (stripped ~ /^(```|~~~)/) {
      in_fence = !in_fence
      print line
      next
    }

    # Match any `### Phase <N>:` heading.
    if (!in_fence && match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
      # Extract number.
      num = line
      sub(/^###[ ]+Phase[ ]+/, "", num)
      sub(/:.*$/, "", num)

      if (in_target_block && !status_written) {
        # Left the target block without finding a Status line.
        marker = "no-status"
      }

      if (num == phase_n) {
        in_target_block = 1
        phase_seen = 1
      } else {
        in_target_block = 0
      }
      print line
      next
    }

    # Status line inside the target block (outside fences).
    if (in_target_block && !in_fence && !status_written && match(line, /^\*\*Status:\*\*[ ]+/)) {
      val = line
      sub(/^\*\*Status:\*\*[ ]+/, "", val)
      sub(/[ \t]+$/, "", val)
      if (val == target) {
        marker = "already-set"
        print line
      } else {
        marker = "transitioned"
        print "**Status:** " target
      }
      status_written = 1
      next
    }

    print line
  }
  END {
    # If EOF hit inside target block with no status line, signal no-status.
    if (in_target_block && !status_written) {
      marker = "no-status"
    }
    if (!phase_seen) {
      marker = "no-phase"
    }
    write_marker(marker)
  }
' > "$tmp"

marker=""
if [ -s "$tmp_marker" ]; then
  marker=$(cat "$tmp_marker")
fi
rm -f "$tmp_marker"

case "$marker" in
  transitioned)
    mv "$tmp" "$plan"
    echo "transitioned"
    exit 0
    ;;
  already-set)
    # No rewrite needed — leave original file on disk untouched.
    rm -f "$tmp"
    echo "already set"
    exit 0
    ;;
  no-phase)
    rm -f "$tmp"
    echo "error: phase ${phase_n} not found in plan" >&2
    exit 1
    ;;
  no-status)
    rm -f "$tmp"
    echo "error: phase ${phase_n} block has no \`**Status:**\` line" >&2
    exit 1
    ;;
  *)
    rm -f "$tmp"
    echo "error: unexpected marker state: ${marker}" >&2
    exit 1
    ;;
esac
