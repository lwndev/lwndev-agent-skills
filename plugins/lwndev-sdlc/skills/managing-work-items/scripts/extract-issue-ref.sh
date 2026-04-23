#!/usr/bin/env bash
# extract-issue-ref.sh — Extract the first issue reference from a requirements doc.
#
# Usage: extract-issue-ref.sh <requirements-doc>
#
# Scans the markdown document for the first level-2 heading matching exactly one of:
#   `## GitHub Issue`
#   `## Issue`
#   `## Issue Tracker`
#
# Within the section body (heading line excluded, bounded by the next `##`
# heading or EOF) the script emits the first matching markdown link:
#   [#N](URL)       → emit `#N`
#   [PROJ-NNN](URL) → emit `PROJ-NNN` (PROJ-NNN must match ^[A-Z][A-Z0-9]*-[0-9]+$)
#
# If the section is missing, empty, or contains no matching link, the script
# emits nothing on stdout and exits 0. Empty stdout + exit 0 is the
# "no reference found" contract.
#
# Exit codes:
#   0 ref found OR section present with no ref OR section absent
#   1 file does not exist / is unreadable
#   2 missing arg

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] extract-issue-ref: usage: extract-issue-ref.sh <requirements-doc>" >&2
  exit 2
fi

path="$1"

if [ ! -r "$path" ]; then
  echo "[error] extract-issue-ref: file not found: $path" >&2
  exit 1
fi

# State machine: scan line by line.
# - Before finding a matching heading, skip.
# - After matching heading, scan body for link patterns until the next ## heading.
in_section=0

while IFS= read -r line || [ -n "$line" ]; do
  if [ "$in_section" -eq 0 ]; then
    # Look for exact heading matches.
    if [[ "$line" =~ ^\#\#\ (GitHub\ Issue|Issue|Issue\ Tracker)$ ]]; then
      in_section=1
      continue
    fi
  else
    # Exit the section when we hit the next level-2 heading.
    if [[ "$line" =~ ^\#\# ]]; then
      break
    fi
    # Look for [#N](URL) first.
    if [[ "$line" =~ \[#([0-9]+)\]\([^\)]+\) ]]; then
      printf '#%s\n' "${BASH_REMATCH[1]}"
      exit 0
    fi
    # Then [PROJ-NNN](URL).
    if [[ "$line" =~ \[([A-Z][A-Z0-9]*-[0-9]+)\]\([^\)]+\) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      exit 0
    fi
  fi
done < "$path"

# No match: empty stdout, exit 0.
exit 0
