#!/usr/bin/env bash
# next-id.sh — Allocate the next sequential requirement-doc ID.
#
# Usage: next-id.sh <FEAT|CHORE|BUG>
#
# Scans requirements/<dir>/ for files matching <TYPE>-<NNN>-*.md, parses the
# numeric suffix from each, takes the max, adds 1, and zero-pads to 3 digits.
# If the directory is empty or missing, returns 001.
#
# Exit codes:
#   0 success
#   1 filesystem error
#   2 usage error (missing or invalid type arg)
#
# Idempotent, no side effects. Operates relative to $PWD.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: next-id.sh <FEAT|CHORE|BUG>" >&2
  exit 2
fi

type_arg="$1"

case "$type_arg" in
  FEAT)  dir="requirements/features" ;;
  CHORE) dir="requirements/chores" ;;
  BUG)   dir="requirements/bugs" ;;
  *)
    echo "error: invalid type '$type_arg' (expected FEAT, CHORE, or BUG)" >&2
    exit 2
    ;;
esac

max=0

# If the directory does not exist, return 001.
if [ ! -d "$dir" ]; then
  printf '001\n'
  exit 0
fi

# Iterate over matching files. Pattern: <TYPE>-<digits>-*.md
shopt -s nullglob
for f in "$dir"/"$type_arg"-[0-9]*-*.md; do
  base="${f##*/}"
  # Strip prefix "<TYPE>-"
  rest="${base#"$type_arg"-}"
  # Extract leading digits up to the first non-digit
  num="${rest%%[!0-9]*}"
  if [ -z "$num" ]; then
    continue
  fi
  # Force base-10 parse to avoid octal interpretation of leading zeros.
  n=$((10#$num))
  if [ "$n" -gt "$max" ]; then
    max="$n"
  fi
done
shopt -u nullglob

next=$((max + 1))
printf '%03d\n' "$next"
