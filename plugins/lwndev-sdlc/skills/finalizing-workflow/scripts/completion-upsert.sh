#!/usr/bin/env bash
# completion-upsert.sh — Upsert the `## Completion` section of a requirement
# doc (FR-5).
#
# Usage: completion-upsert.sh <doc-path> <prNumber> <prUrl>
#
# Behavior:
#   - Detects line-ending (LF vs CRLF) on read; preserves on write.
#   - Fence-aware `## Completion` detection. Headings inside triple-backtick
#     (```) or triple-tilde (~~~) fenced blocks are NOT treated as section
#     markers.
#   - If a real (unfenced) `## Completion` section exists: replace its body
#     in place. The heading line is preserved; everything from the heading
#     (exclusive) to the next unfenced `^## ` heading (exclusive) or EOF is
#     overwritten with the fresh block body. Emits `upserted` on stdout.
#   - If absent: append the full block (heading + body) at the end of the
#     file, preceded by a blank line. Emits `appended` on stdout.
#
# Block body:
#   ## Completion
#
#   **Status:** `Complete`
#
#   **Completed:** YYYY-MM-DD   (date -u +%Y-%m-%d)
#
#   **Pull Request:** [#<prNumber>](<prUrl>)
#
#   `<prNumber>` and `<prUrl>` are substituted literally via parameter
#   expansion — no shell-evaluation, no eval.
#
# Exit codes:
#   0  success (stdout: `upserted` or `appended`)
#   1  file I/O failure (stderr: `[error] completion-upsert: <reason>`)
#   2  missing args or non-existent doc (stderr: usage line)

set -euo pipefail

usage() {
  echo "[error] completion-upsert: usage: completion-upsert.sh <doc-path> <prNumber> <prUrl>" >&2
  exit 2
}

if [ "$#" -ne 3 ]; then
  usage
fi

doc="$1"
pr_number="$2"
pr_url="$3"

if [ ! -f "$doc" ]; then
  echo "[error] completion-upsert: file not found: ${doc}" >&2
  exit 2
fi

if [ ! -r "$doc" ]; then
  echo "[error] completion-upsert: file not readable: ${doc}" >&2
  exit 1
fi

# Detect line ending by sniffing the first line for a trailing CR.
# If the file is empty or has no newline, default to LF.
eol="LF"
if LC_ALL=C head -n 1 "$doc" 2>/dev/null | LC_ALL=C grep -q $'\r$'; then
  eol="CRLF"
fi

# Date (UTC) for the Completed line.
today="$(date -u +%Y-%m-%d)"

# Scan the doc to locate the real (unfenced) `## Completion` section.
# Emits two values:
#   START=<1-based line number of the heading>   (0 if no real section)
#   END=<1-based line number of the next `## ` heading> (0 if EOF)
scan_result="$(awk '
  BEGIN {
    in_fence = 0
    start = 0
    end = 0
  }
  {
    line = $0
    sub(/\r$/, "", line)

    stripped = line
    sub(/^[ \t]+/, "", stripped)
    if (stripped ~ /^(```|~~~)/) {
      in_fence = !in_fence
      next
    }

    if (in_fence) { next }

    # After finding start, look for the next `## ` heading as end marker.
    if (start > 0 && end == 0) {
      if (substr(line, 1, 3) == "## ") {
        end = NR
        exit 0
      }
      next
    }

    if (start == 0 && line == "## Completion") {
      start = NR
    }
  }
  END {
    printf "START=%d\n", start
    printf "END=%d\n", end
  }
' "$doc")"

start_line="$(printf '%s\n' "$scan_result" | sed -n 's/^START=//p')"
end_line="$(printf '%s\n' "$scan_result" | sed -n 's/^END=//p')"
start_line="${start_line:-0}"
end_line="${end_line:-0}"

# Block body lines (no terminator baked in — we add terminators below).
# The heading line is always present as block_lines[0].
block_lines=(
  "## Completion"
  ""
  "**Status:** \`Complete\`"
  ""
  "**Completed:** ${today}"
  ""
  "**Pull Request:** [#${pr_number}](${pr_url})"
)

# Terminator per line-ending.
if [ "$eol" = "CRLF" ]; then
  term=$'\r\n'
else
  term=$'\n'
fi

# Emit block body lines (indexes lo..hi inclusive) separated by `term`,
# with NO terminator after the final line.
emit_block_range() {
  local lo="$1"
  local hi="$2"
  local i
  for ((i = lo; i <= hi; i++)); do
    if [ "$i" -gt "$lo" ]; then
      printf '%s' "$term"
    fi
    printf '%s' "${block_lines[$i]}"
  done
}

# Whether the original file ends with a newline (LF or CRLF trailing).
has_trailing_newline() {
  # LC_ALL=C makes grep treat bytes literally.
  LC_ALL=C tail -c 1 "$doc" 2>/dev/null | LC_ALL=C grep -q $'\n'
}

# Write atomically via tempfile in the same directory.
tmpdir="$(dirname "$doc")"
tmpfile="$(mktemp "${tmpdir}/.completion-upsert.XXXXXX")" || {
  echo "[error] completion-upsert: unable to create temp file" >&2
  exit 1
}
# Cleanup tempfile on error exits.
trap 'rm -f "$tmpfile"' EXIT

mode=""

if [ "${start_line:-0}" -gt 0 ]; then
  mode="upserted"
  # Splice: pre-heading lines + heading (verbatim) + fresh body (lines 1..end of block_lines)
  # + (tail starting at end_line if any).
  last_idx=$((${#block_lines[@]} - 1))
  {
    # Head: lines 1..start_line inclusive (includes the heading verbatim).
    awk -v start="$start_line" 'NR <= start { print; next } NR > start { exit 0 }' "$doc"
    # Fresh body: block_lines[1..last_idx].
    emit_block_range 1 "$last_idx"
    if [ "${end_line:-0}" -gt 0 ]; then
      # Tail follows. Emit a terminator (closes last body line) plus a
      # blank-line separator before the next heading, then the tail verbatim.
      printf '%s%s' "$term" "$term"
      awk -v end="$end_line" 'NR >= end { print }' "$doc"
    else
      # No tail; match original trailing newline if it had one.
      if has_trailing_newline; then
        printf '%s' "$term"
      fi
    fi
  } > "$tmpfile" 2> "${tmpfile}.err" || {
    err="$(cat "${tmpfile}.err" 2>/dev/null || echo "write failed")"
    rm -f "${tmpfile}.err"
    echo "[error] completion-upsert: ${err}" >&2
    exit 1
  }
  rm -f "${tmpfile}.err"
else
  mode="appended"
  last_idx=$((${#block_lines[@]} - 1))
  {
    # Copy original content verbatim.
    cat "$doc"
    # Ensure a newline terminates the original before our blank separator.
    if ! has_trailing_newline; then
      printf '%s' "$term"
    fi
    # Blank-line separator.
    printf '%s' "$term"
    # Block body: all block_lines[0..last_idx].
    emit_block_range 0 "$last_idx"
    # Final terminator.
    printf '%s' "$term"
  } > "$tmpfile" 2> "${tmpfile}.err" || {
    err="$(cat "${tmpfile}.err" 2>/dev/null || echo "write failed")"
    rm -f "${tmpfile}.err"
    echo "[error] completion-upsert: ${err}" >&2
    exit 1
  }
  rm -f "${tmpfile}.err"
fi

# Preserve original permissions on the doc.
if command -v stat >/dev/null 2>&1; then
  # BSD (macOS) vs GNU stat — try both.
  orig_mode=""
  if orig_mode="$(stat -f '%Lp' "$doc" 2>/dev/null)"; then :
  elif orig_mode="$(stat -c '%a' "$doc" 2>/dev/null)"; then :
  fi
  if [ -n "$orig_mode" ]; then
    chmod "$orig_mode" "$tmpfile" 2>/dev/null || true
  fi
fi

# Atomic replace.
if ! mv "$tmpfile" "$doc" 2>/dev/null; then
  echo "[error] completion-upsert: unable to write ${doc}" >&2
  exit 1
fi
trap - EXIT

printf '%s\n' "$mode"
exit 0
