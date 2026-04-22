#!/usr/bin/env bash
# branch-id-parse.sh — Classify a branch name into its work-item identity.
#
# Usage: branch-id-parse.sh <branch-name>
#
# Applies four regexes in order and emits JSON on match:
#   ^feat/(FEAT-[0-9]+)-          →  {"id":"FEAT-NNN","type":"feature","dir":"requirements/features"}
#   ^chore/(CHORE-[0-9]+)-        →  {"id":"CHORE-NNN","type":"chore","dir":"requirements/chores"}
#   ^fix/(BUG-[0-9]+)-            →  {"id":"BUG-NNN","type":"bug","dir":"requirements/bugs"}
#   ^release/[a-z0-9-]+-vX.Y.Z$   →  {"id":null,"type":"release","dir":null}
#
# Note: for the release classification, `id` and `dir` are emitted as literal
# JSON `null`, not the string `"null"`. Release branches are not tied to a
# work-item identifier or a requirements directory.
#
# Uses jq if available; falls back to hand-assembled JSON otherwise.
#
# Exit codes:
#   0 matched (any of the four patterns)
#   1 no match (`error: branch name does not match any work-item pattern`)
#   2 usage error

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "error: usage: branch-id-parse.sh <branch-name>" >&2
  exit 2
fi

branch="$1"

id=""
type=""
dir=""
is_release=0

if [[ "$branch" =~ ^feat/(FEAT-[0-9]+)- ]]; then
  id="${BASH_REMATCH[1]}"
  type="feature"
  dir="requirements/features"
elif [[ "$branch" =~ ^chore/(CHORE-[0-9]+)- ]]; then
  id="${BASH_REMATCH[1]}"
  type="chore"
  dir="requirements/chores"
elif [[ "$branch" =~ ^fix/(BUG-[0-9]+)- ]]; then
  id="${BASH_REMATCH[1]}"
  type="bug"
  dir="requirements/bugs"
elif [[ "$branch" =~ ^release/[a-z0-9-]+-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  type="release"
  is_release=1
else
  echo "error: branch name does not match any work-item pattern" >&2
  exit 1
fi

# Emit JSON. Prefer jq for correctness; fall back to hand-assembled JSON.
if command -v jq >/dev/null 2>&1; then
  if [ "$is_release" -eq 1 ]; then
    # Release: id and dir are literal JSON null (no --arg for them).
    jq -cn --arg type "$type" '{id: null, type: $type, dir: null}'
  else
    jq -cn --arg id "$id" --arg type "$type" --arg dir "$dir" \
      '{id: $id, type: $type, dir: $dir}'
  fi
else
  # Hand-assembled fallback. All values are ASCII-safe (matched from regex),
  # so we only need to escape backslashes and double-quotes for safety.
  esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
  }
  if [ "$is_release" -eq 1 ]; then
    # Release: emit literal JSON null for id and dir (not the string "null").
    printf '{"id":null,"type":"%s","dir":null}\n' "$(esc "$type")"
  else
    printf '{"id":"%s","type":"%s","dir":"%s"}\n' \
      "$(esc "$id")" "$(esc "$type")" "$(esc "$dir")"
  fi
fi
