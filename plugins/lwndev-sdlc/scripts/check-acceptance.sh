#!/usr/bin/env bash
# check-acceptance.sh — Flip a single `- [ ]` checkbox by literal-substring match (FR-6).
#
# Usage: check-acceptance.sh <doc-path> <matcher>
#
# Behavior:
#   - Walks the file line by line, tracking fenced-code-block state.
#     A fence opens or closes on a line whose first non-whitespace run is
#     ``` or ~~~ (with optional language tag). Fences toggle state.
#   - Lines INSIDE a fenced block are ignored for checkbox matching.
#   - Finds the first `- [ ] ` line outside any fence that contains <matcher>
#     as a LITERAL substring (not a regex).
#   - CRLF is stripped on read so Windows-style line endings do not break the
#     walker (per FEAT-019 a8c3ab8 prior art).
#
# Exit codes:
#   0 success — either a line was flipped (prints `checked`)
#     or a matching `- [x] ` line was already present (prints `already checked`)
#   1 no matching `- [ ] ` or `- [x] ` line outside fences
#   2 ambiguous — multiple `- [ ] ` lines match
#   3 usage error (missing args)

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "error: usage: check-acceptance.sh <doc-path> <matcher>" >&2
  exit 3
fi

doc="$1"
matcher="$2"

if [ ! -f "$doc" ]; then
  echo "error: file not found: ${doc}" >&2
  exit 1
fi

# Scan pass: classify lines into unchecked-matches / checked-matches.
# awk is used so substring matching uses index() (literal, no regex).
# The matcher is passed in via -v to keep it out of the awk program text.
# Output is two space-separated lists of line numbers (unchecked, checked).
scan_output=$(
  tr -d '\r' < "$doc" \
    | awk -v m="$matcher" '
        BEGIN { in_fence = 0; u = ""; c = "" }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)
          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next
          if (match(line, /-[ ]\[[ ]\][ ]/) && index(line, m) > 0) {
            u = (u == "" ? NR : u " " NR)
            next
          }
          if (match(line, /-[ ]\[[xX]\][ ]/) && index(line, m) > 0) {
            c = (c == "" ? NR : c " " NR)
          }
        }
        END {
          print u
          print c
        }
      '
)

unchecked_raw=$(printf '%s\n' "$scan_output" | sed -n '1p')
checked_raw=$(printf '%s\n' "$scan_output" | sed -n '2p')

unchecked_lines=()
checked_lines=()
if [ -n "$unchecked_raw" ]; then
  # shellcheck disable=SC2206
  unchecked_lines=( $unchecked_raw )
fi
if [ -n "$checked_raw" ]; then
  # shellcheck disable=SC2206
  checked_lines=( $checked_raw )
fi

u_count=${#unchecked_lines[@]}
c_count=${#checked_lines[@]}

if [ "$u_count" -eq 0 ] && [ "$c_count" -eq 0 ]; then
  echo "error: criterion not found" >&2
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

# Exactly one unchecked line: flip it in place by line number.
target_line="${unchecked_lines[0]}"

# Preserve original file's EOL style? The script normalizes on read only for
# matching purposes; write-back uses the file's current bytes with a sed-style
# substitution on the target line number. We rewrite using awk so we can
# target the exact NR and replace the FIRST occurrence of "- [ ] " with
# "- [x] " on that line (leaving surrounding whitespace intact).
tmp="$(mktemp)"
awk -v target="$target_line" '
  NR == target {
    # Replace the first "- [ ] " on this line with "- [x] ".
    # Done with sub() using a fixed pattern.
    sub(/-[ ]\[[ ]\][ ]/, "- [x] ")
  }
  { print }
' "$doc" > "$tmp"
mv "$tmp" "$doc"

echo "checked"
