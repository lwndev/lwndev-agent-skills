#!/usr/bin/env bash
# resolve-requirement-doc.sh — Map a requirement ID to its single doc path (FR-3).
#
# Usage: resolve-requirement-doc.sh <ID>
#   <ID> is case-sensitive and must match FEAT-NNN, CHORE-NNN, or BUG-NNN.
#
# Behavior:
#   1. Parse the prefix → directory map:
#        FEAT  → requirements/features
#        CHORE → requirements/chores
#        BUG   → requirements/bugs
#   2. Glob <dir>/<ID>-*.md relative to $PWD.
#   3. Exactly one match → print path to stdout, exit 0.
#   4. Zero matches      → stderr "error: no file matches <ID>", exit 1.
#   5. Multiple matches  → stderr "error: ambiguous — multiple files match <ID>:"
#                          followed by each candidate on its own line, exit 2.
#
# Exit codes:
#   0 single match (path printed to stdout)
#   1 no match
#   2 ambiguous (multiple matches)
#   3 usage error (missing / malformed ID)

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: resolve-requirement-doc.sh <ID>" >&2
  exit 3
fi

id="$1"

# Case-sensitive match on the canonical prefixes.
if [[ "$id" =~ ^FEAT-[0-9]+$ ]]; then
  dir="requirements/features"
elif [[ "$id" =~ ^CHORE-[0-9]+$ ]]; then
  dir="requirements/chores"
elif [[ "$id" =~ ^BUG-[0-9]+$ ]]; then
  dir="requirements/bugs"
else
  echo "error: malformed ID '$id' (expected FEAT-NNN, CHORE-NNN, or BUG-NNN)" >&2
  exit 3
fi

# Collect matches without relying on nullglob side effects on the caller.
matches=()
shopt -s nullglob
for f in "${dir}"/"${id}"-*.md; do
  matches+=("$f")
done
shopt -u nullglob

case "${#matches[@]}" in
  0)
    echo "error: no file matches ${id}" >&2
    exit 1
    ;;
  1)
    printf '%s\n' "${matches[0]}"
    exit 0
    ;;
  *)
    echo "error: ambiguous — multiple files match ${id}:" >&2
    for m in "${matches[@]}"; do
      printf '%s\n' "$m" >&2
    done
    exit 2
    ;;
esac
