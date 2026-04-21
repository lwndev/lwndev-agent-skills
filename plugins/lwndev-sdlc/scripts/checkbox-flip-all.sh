#!/usr/bin/env bash
# checkbox-flip-all.sh — Flip every `- [ ]` in a named section (FR-7).
#
# Usage: checkbox-flip-all.sh <doc-path> <section-heading>
#
# Behavior:
#   - Locates the first line matching exactly `## <section-heading>` (H2).
#   - Section ends at the next `## ` heading or EOF (H2-level boundary).
#   - Within the section, walks line by line tracking fenced-code-block state
#     (toggle on a line whose first non-whitespace run is ``` or ~~~).
#   - For every `- [ ] ` line OUTSIDE fences within the section, rewrites to
#     `- [x] `.
#   - Writes the file back in place. Prints `checked N lines` where N is the
#     number of lines flipped (may be 0 — idempotent on re-run).
#   - CRLF is detected on read; if the file used CRLF endings, the rewrite
#     preserves CRLF on every line (FEAT-019 contract: "normalize on read and
#     restore the original ending on write").
#
# Exit codes:
#   0 success (`checked N lines` printed, file possibly mutated)
#   1 section not found
#   2 usage error (missing args)

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "error: usage: checkbox-flip-all.sh <doc-path> <section-heading>" >&2
  exit 2
fi

doc="$1"
heading="$2"

if [ ! -f "$doc" ]; then
  echo "error: file not found: ${doc}" >&2
  exit 1
fi

# Detect line-ending style so we can restore CRLF on write when the input
# used it (FEAT-019 rule).
if grep -q $'\r$' "$doc"; then
  eol=$'\r'
else
  eol=""
fi

# Look for the section and flip in a single awk pass.
# The awk program exits with status 9 if the section was not seen (so we can
# distinguish from "section found but no boxes to flip").
tmp="$(mktemp)"
set +e
awk -v heading="$heading" -v eol="$eol" '
  BEGIN { in_fence = 0; in_section = 0; saw_section = 0; flipped = 0 }
  function emit(s) { printf "%s%s\n", s, eol }
  {
    # Strip trailing CR for matching purposes; we re-append "eol" on output.
    sub(/\r$/, "")
    line = $0

    # Section-boundary detection happens BEFORE fence toggling
    # (a fence cannot straddle an H2 heading in well-formed markdown,
    # but defensively, a heading outside a fence is what we care about).
    if (!in_fence && line == "## " heading) {
      in_section = 1
      saw_section = 1
      emit(line)
      next
    }

    if (in_section && !in_fence && substr(line, 1, 3) == "## ") {
      # Next H2 heading closes the section.
      in_section = 0
      emit(line)
      next
    }

    if (in_section) {
      stripped = line
      sub(/^[ \t]+/, "", stripped)
      if (stripped ~ /^(```|~~~)/) {
        in_fence = !in_fence
        print line
        next
      }
      if (!in_fence) {
        # Flip first occurrence of "- [ ] " on this line, count if changed.
        new = line
        sub(/-[ ]\[[ ]\][ ]/, "- [x] ", new)
        if (new != line) {
          flipped++
          emit(new)
          next
        }
      }
    }
    emit(line)
  }
  END {
    if (!saw_section) exit 9
    print "__FLIPPED__=" flipped > "/dev/stderr"
  }
' "$doc" > "$tmp" 2> "${tmp}.meta"
awk_rc=$?
set -e

if [ "$awk_rc" -eq 9 ]; then
  rm -f "$tmp" "${tmp}.meta"
  echo "error: section not found" >&2
  exit 1
fi

if [ "$awk_rc" -ne 0 ]; then
  rm -f "$tmp" "${tmp}.meta"
  echo "error: awk failure (rc=${awk_rc})" >&2
  exit 1
fi

# Recover flipped count from meta channel.
flipped_line=$(grep '^__FLIPPED__=' "${tmp}.meta" || true)
rm -f "${tmp}.meta"
flipped="${flipped_line#__FLIPPED__=}"
[ -z "$flipped" ] && flipped=0

mv "$tmp" "$doc"
echo "checked ${flipped} lines"
