#!/usr/bin/env bash
set -euo pipefail

# arm-baseline.sh <id>
#
# Capture-if-absent write-surface baseline for finalizing-workflow (BUG-024).
# Persists the current HEAD SHA, keyed by workflow ID, INSIDE the git dir at
# `$(git rev-parse --git-dir)/sdlc-finalize-baseline-<id>`. Prints the baseline
# SHA on stdout (empty when HEAD cannot be resolved — non-git tree / no commits).
#
# The marker lives in the git dir (not the work tree) so it never shows up in
# `git status --porcelain` — finalize.sh's pre-flight requires a clean tree, and
# it also keeps the marker out of any `git add -A` the adversary might run.
#
# CAPTURE-IF-ABSENT IS LOAD-BEARING. A finalize that is blocked at pre-flight
# exits without merging; the model may then mutate the tree and re-run finalize.
# The re-run MUST reuse the ORIGINAL baseline so the out-of-surface commit made
# between runs is still measured against the clean pre-finalize tip. Recapturing
# on every run would move the baseline past the mutation and defeat the guard.
#
# Exit code: 0 always (arming never fails the finalize).

id="${1:-unknown}"
[ -z "$id" ] && id="unknown"

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [ -z "$git_dir" ]; then
  # Not a git tree — nothing to baseline. The guard is inert.
  exit 0
fi

file="${git_dir}/sdlc-finalize-baseline-${id}"

# Reuse an existing baseline verbatim — never recapture.
if [ -f "$file" ]; then
  cat "$file"
  exit 0
fi

sha="$(git rev-parse HEAD 2>/dev/null || true)"
if [ -z "$sha" ]; then
  # Git tree with no commits — nothing to baseline.
  exit 0
fi

printf '%s\n' "$sha" > "$file"
printf '%s\n' "$sha"
exit 0
