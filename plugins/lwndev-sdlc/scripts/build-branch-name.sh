#!/usr/bin/env bash
# build-branch-name.sh — Assemble the canonical branch name for a work item (FR-4).
#
# Usage: build-branch-name.sh <type> <ID> <summary>
#   <type>    one of: feat, chore, fix
#   <ID>      full work-item ID including prefix (e.g. FEAT-001, CHORE-023, BUG-004)
#   <summary> freeform summary text; slugified internally via sibling slugify.sh
#
# Emits on stdout: <type>/<ID>-<slug>
#
# Exit codes:
#   0 success
#   1 slugify failed (summary slugified to empty)
#   2 usage error (missing args or invalid type)

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "error: usage: build-branch-name.sh <type> <ID> <summary>" >&2
  exit 2
fi

type="$1"
id="$2"
summary="$3"

case "$type" in
  feat|chore|fix) ;;
  *)
    echo "error: invalid type '$type' (expected feat, chore, or fix)" >&2
    exit 2
    ;;
esac

# Call the sibling slugify.sh using its absolute path, so this works regardless of CWD.
slugify="${BASH_SOURCE%/*}/slugify.sh"

# Capture the slug; propagate slugify's exit status (1 = empty slug).
if ! slug=$(bash "$slugify" "$summary"); then
  # slugify already printed its own error to stderr.
  exit 1
fi

printf '%s/%s-%s\n' "$type" "$id" "$slug"
