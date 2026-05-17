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

# slugify.sh lives at the plugin root scripts/ dir (not moved with this script).
# Resolve via CLAUDE_PLUGIN_ROOT when provided (skill runtime contract); otherwise
# fall back to the on-disk plugin-root layout: skills/managing-source-control/scripts/
# is three levels deep, so ../../../scripts/ resolves to plugins/lwndev-sdlc/scripts/.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  slugify="${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh"
else
  slugify="${BASH_SOURCE%/*}/../../../scripts/slugify.sh"
fi

# Capture the slug; propagate slugify's exit status (1 = empty slug).
if ! slug=$(bash "$slugify" "$summary"); then
  # slugify already printed its own error to stderr.
  exit 1
fi

printf '%s/%s-%s\n' "$type" "$id" "$slug"
