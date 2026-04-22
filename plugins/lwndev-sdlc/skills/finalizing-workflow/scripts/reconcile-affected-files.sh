#!/usr/bin/env bash
# reconcile-affected-files.sh — Reconcile `## Affected Files` section of a
# requirement doc against the PR file list (FR-6).
#
# Usage: reconcile-affected-files.sh <doc-path> <prNumber>
#
# Behavior:
#   - Fetches PR file list via `gh pr view <prNumber> --json files --jq
#     '.files[].path' | sort`. On `gh` failure: exit 1, stderr
#     `[warn] reconcile-affected-files: gh failure — <first line>`, no stdout.
#   - If `## Affected Files` section is absent (real, unfenced): exit 0,
#     stdout `0 0`, no diff.
#   - If present:
#     - Scan the section body for bullet lines `- `path`` (or
#       `- `path` (planned but not modified)`) OUTSIDE fenced blocks. Skip
#       fenced-example bullets entirely.
#     - Files in PR but not in doc → append as `- `path`` bullets inside the
#       section (before the next `## ` heading or EOF).
#     - Files in doc not in PR → annotate: `- `path`` → `- `path` (planned
#       but not modified)`. Idempotent: already-annotated lines are skipped.
#     - Files in both → untouched.
#   - Preserves line endings (LF/CRLF) per line.
#   - Emits `<appended-count> <annotated-count>` on stdout.
#
# Exit codes:
#   0  success
#   1  gh failure
#   2  missing args / non-existent doc / non-integer prNumber

set -euo pipefail

usage() {
  echo "[error] reconcile-affected-files: usage: reconcile-affected-files.sh <doc-path> <prNumber>" >&2
  exit 2
}

if [ "$#" -ne 2 ]; then
  usage
fi

doc="$1"
pr_number_arg="$2"

if ! [[ "$pr_number_arg" =~ ^[0-9]+$ ]] || [ "$pr_number_arg" -le 0 ]; then
  usage
fi

if [ ! -f "$doc" ]; then
  echo "[error] reconcile-affected-files: file not found: ${doc}" >&2
  exit 2
fi

if [ ! -r "$doc" ]; then
  echo "[error] reconcile-affected-files: file not readable: ${doc}" >&2
  exit 2
fi

# Fetch PR file list.
gh_stderr_file="$(mktemp)"
cleanup() {
  rm -f "${gh_stderr_file:-}" "${tmpfile:-}" "${new_bullets_file:-}"
}
trap cleanup EXIT

if ! pr_files="$(gh pr view "$pr_number_arg" --json files --jq '.files[].path' 2>"$gh_stderr_file" | LC_ALL=C sort)"; then
  first_err_line="$(head -n 1 "$gh_stderr_file" 2>/dev/null || echo "gh failure")"
  echo "[warn] reconcile-affected-files: gh failure — ${first_err_line}" >&2
  exit 1
fi

# Detect line-ending (by sniffing the first line).
eol="LF"
if LC_ALL=C head -n 1 "$doc" 2>/dev/null | LC_ALL=C grep -q $'\r$'; then
  eol="CRLF"
fi

# Locate the real `## Affected Files` section.
#   START = heading line (1-based), 0 if absent
#   END   = next `## ` heading line number (1-based), 0 if EOF
scan_result="$(awk '
  BEGIN { in_fence = 0; start = 0; end = 0 }
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

    if (start > 0 && end == 0) {
      if (substr(line, 1, 3) == "## ") {
        end = NR
        exit 0
      }
      next
    }

    if (start == 0 && line == "## Affected Files") {
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

if [ "${start_line:-0}" -eq 0 ]; then
  printf '0 0\n'
  exit 0
fi

# Extract bullets in the section body (outside fenced blocks).
# Emits:
#   LINE=<NR>|ANNOTATED=<0|1>|PATH=<path>
# plus BODY_LAST=<NR> = last line number still in the body (0 if empty body).
bullet_rows="$(awk -v start="$start_line" -v end="$end_line" '
  BEGIN { in_fence = 0; body_last = 0 }
  {
    line = $0
    sub(/\r$/, "", line)

    stripped = line
    sub(/^[ \t]+/, "", stripped)
    if (stripped ~ /^(```|~~~)/) {
      in_fence = !in_fence
      next
    }

    if (NR <= start) { next }
    if (end > 0 && NR >= end) { next }

    # Track last non-blank body line (outside fences) as the insertion
    # anchor for new bullets. Blank trailing lines before the next heading
    # are preserved; new bullets appear immediately after the last bullet.
    if (!in_fence) {
      trimmed = line
      sub(/^[ \t]+/, "", trimmed)
      sub(/[ \t]+$/, "", trimmed)
      if (trimmed != "") body_last = NR
    }

    if (in_fence) { next }

    if (match(line, /^[ \t]*- `[^`]+`/)) {
      m = substr(line, RSTART, RLENGTH)
      first_bt = index(m, "`")
      rest = substr(m, first_bt + 1)
      second_bt = index(rest, "`")
      if (second_bt <= 1) { next }
      path = substr(rest, 1, second_bt - 1)
      tail = substr(line, RSTART + RLENGTH)
      annotated = (tail ~ /^[ \t]*\(planned but not modified\)[ \t]*$/) ? 1 : 0
      printf "LINE=%d|ANNOTATED=%d|PATH=%s\n", NR, annotated, path
    }
  }
  END { printf "BODY_LAST=%d\n", body_last }
' "$doc")"

declare -a doc_paths=()
declare -a doc_lines=()
declare -a doc_annotated=()
body_last=0

while IFS= read -r row; do
  case "$row" in
    LINE=*)
      ln="${row#LINE=}"
      ln="${ln%%|*}"
      rest="${row#*|}"
      ann="${rest#ANNOTATED=}"
      ann="${ann%%|*}"
      path="${row##*PATH=}"
      doc_lines+=("$ln")
      doc_annotated+=("$ann")
      doc_paths+=("$path")
      ;;
    BODY_LAST=*)
      body_last="${row#BODY_LAST=}"
      ;;
  esac
done <<EOF
$bullet_rows
EOF

# Parse PR paths.
declare -a pr_paths=()
if [ -n "$pr_files" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] && pr_paths+=("$p")
  done <<EOF
$pr_files
EOF
fi

# Build delimited set strings for bash 3.2 compatibility (no associative
# arrays). Wrap each path with record delimiters to prevent prefix/substring
# false matches. Format: "\x1fpath1\x1fpath2\x1f…".
RS=$'\x1f'
doc_path_set="$RS"
for p in "${doc_paths[@]+"${doc_paths[@]}"}"; do
  doc_path_set="${doc_path_set}${p}${RS}"
done

pr_path_set="$RS"
for p in "${pr_paths[@]+"${pr_paths[@]}"}"; do
  pr_path_set="${pr_path_set}${p}${RS}"
done

in_set() {
  local set="$1" val="$2"
  case "$set" in
    *"${RS}${val}${RS}"*) return 0 ;;
  esac
  return 1
}

# Compute diffs.
declare -a to_append=()
for p in "${pr_paths[@]+"${pr_paths[@]}"}"; do
  if ! in_set "$doc_path_set" "$p"; then
    to_append+=("$p")
  fi
done

declare -a to_annotate_lines=()
for i in "${!doc_paths[@]}"; do
  p="${doc_paths[$i]}"
  ln="${doc_lines[$i]}"
  ann="${doc_annotated[$i]}"
  if ! in_set "$pr_path_set" "$p" && [ "$ann" = "0" ]; then
    to_annotate_lines+=("$ln")
  fi
done

appended_count=${#to_append[@]}
annotated_count=${#to_annotate_lines[@]}

if [ "$appended_count" -eq 0 ] && [ "$annotated_count" -eq 0 ]; then
  printf '%d %d\n' "$appended_count" "$annotated_count"
  exit 0
fi

# Insertion point for new bullets.
#   - If body_last > 0: after body_last (which lies inside the section).
#   - Otherwise: right after the heading line.
insertion_after=0
if [ "${body_last:-0}" -gt 0 ]; then
  insertion_after="$body_last"
else
  insertion_after="$start_line"
fi

# Write new_bullets file (one bullet per line, no terminator — awk adds EOL).
tmpdir="$(dirname "$doc")"
new_bullets_file="$(mktemp "${tmpdir}/.reconcile-new-bullets.XXXXXX")" || {
  echo "[warn] reconcile-affected-files: unable to create temp file" >&2
  exit 1
}
{
  for p in "${to_append[@]+"${to_append[@]}"}"; do
    printf '%s\n' "- \`${p}\`"
  done
} > "$new_bullets_file"

# Build annotate line set as CSV for awk.
annotate_csv=""
for ln in "${to_annotate_lines[@]+"${to_annotate_lines[@]}"}"; do
  if [ -z "$annotate_csv" ]; then
    annotate_csv="$ln"
  else
    annotate_csv="$annotate_csv,$ln"
  fi
done

tmpfile="$(mktemp "${tmpdir}/.reconcile-affected-files.XXXXXX")" || {
  echo "[warn] reconcile-affected-files: unable to create temp file" >&2
  exit 1
}

has_trailing_newline() {
  LC_ALL=C tail -c 1 "$doc" 2>/dev/null | LC_ALL=C grep -q $'\n'
}

# Stream: preserve per-line endings; annotate target lines; splice bullets in
# after `insertion_after`. awk reads with default RS so CR is stripped before
# comparison; we recover the original CR state per line.
awk -v ann_csv="$annotate_csv" \
    -v insert_after="$insertion_after" \
    -v new_bullets_path="$new_bullets_file" '
BEGIN {
  n = split(ann_csv, arr, ",")
  for (i = 1; i <= n; i++) {
    if (arr[i] != "") ann_set[arr[i]+0] = 1
  }
}
{
  raw = $0
  scan_line = raw
  has_cr = 0
  if (sub(/\r$/, "", scan_line)) has_cr = 1
  eol_bytes = has_cr ? "\r\n" : "\n"

  if ((NR in ann_set)) {
    if (match(scan_line, /^[ \t]*- `[^`]+`/)) {
      prefix = substr(scan_line, RSTART, RLENGTH)
      tail = substr(scan_line, RSTART + RLENGTH)
      if (tail ~ /^[ \t]*\(planned but not modified\)[ \t]*$/) {
        printf "%s%s", scan_line, eol_bytes
      } else {
        printf "%s (planned but not modified)%s", prefix, eol_bytes
      }
    } else {
      printf "%s%s", scan_line, eol_bytes
    }
  } else {
    printf "%s%s", scan_line, eol_bytes
  }

  if (NR == insert_after) {
    while ((getline nb < new_bullets_path) > 0) {
      printf "%s%s", nb, eol_bytes
    }
    close(new_bullets_path)
  }
}
' "$doc" > "$tmpfile" 2> "${tmpfile}.err" || {
  err="$(cat "${tmpfile}.err" 2>/dev/null || echo "write failed")"
  rm -f "${tmpfile}.err"
  echo "[warn] reconcile-affected-files: ${err}" >&2
  exit 1
}
rm -f "${tmpfile}.err"

# If the original file had no trailing newline, strip the terminal one we
# added. Matches the detected eol.
if ! has_trailing_newline; then
  if [ "$eol" = "CRLF" ]; then
    last_bytes="$(LC_ALL=C tail -c 2 "$tmpfile" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    if [ "$last_bytes" = "0d0a" ]; then
      size="$(wc -c < "$tmpfile" | tr -d ' ')"
      new_size=$((size - 2))
      dd if="$tmpfile" of="${tmpfile}.trunc" bs=1 count="$new_size" 2>/dev/null
      mv "${tmpfile}.trunc" "$tmpfile"
    fi
  else
    last_byte="$(LC_ALL=C tail -c 1 "$tmpfile" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    if [ "$last_byte" = "0a" ]; then
      size="$(wc -c < "$tmpfile" | tr -d ' ')"
      new_size=$((size - 1))
      dd if="$tmpfile" of="${tmpfile}.trunc" bs=1 count="$new_size" 2>/dev/null
      mv "${tmpfile}.trunc" "$tmpfile"
    fi
  fi
fi

# Preserve doc permissions.
if command -v stat >/dev/null 2>&1; then
  orig_mode=""
  if orig_mode="$(stat -f '%Lp' "$doc" 2>/dev/null)"; then :
  elif orig_mode="$(stat -c '%a' "$doc" 2>/dev/null)"; then :
  fi
  if [ -n "$orig_mode" ]; then
    chmod "$orig_mode" "$tmpfile" 2>/dev/null || true
  fi
fi

if ! mv "$tmpfile" "$doc" 2>/dev/null; then
  echo "[warn] reconcile-affected-files: unable to write ${doc}" >&2
  exit 1
fi

printf '%d %d\n' "$appended_count" "$annotated_count"
exit 0
