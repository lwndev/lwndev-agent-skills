#!/usr/bin/env bash
# commit-and-push-phase.sh — Commit and push a completed phase with canonical message (FEAT-027 / FR-5).
#
# Usage: commit-and-push-phase.sh <FEAT-ID> <phase-N> <phase-name>
#
# Canonical commit message:
#   <type-prefix>(<FEAT-ID>): complete phase <N> - <phase-name>
# where <type-prefix> is derived from the ID prefix:
#   FEAT-  → feat
#   CHORE- → chore
#   BUG-   → fix
#
# Execution sequence (fails fast):
#   1. `git status --porcelain=v1` — empty → `error: no changes to commit`, exit 1.
#   2. `git add -A`.
#   3. `git commit -m "<canonical>"` — hook rejection surfaces stderr verbatim, exit 1.
#   4. `git rev-parse --abbrev-ref HEAD` — determine branch.
#   5. `git rev-parse --abbrev-ref --symbolic-full-name @{u}` — probe for upstream.
#      Non-zero exit → no upstream set; use `git push -u origin <branch>`.
#      Zero exit     → upstream exists; use bare `git push`.
#   6. On push success: stdout `pushed <branch>`, exit 0.
#   7. On push failure: surface `git push` stderr verbatim, emit
#      `[error] push failed; see Push Failure Recovery in SKILL.md` to stderr,
#      exit 1.
#
# Push-failure recovery contract:
#   Callers that get a non-zero exit from this script MUST resolve conflicts
#   via `git fetch origin` + `git rebase origin/<branch>` + `git push` directly.
#   Do NOT re-run this script after resolving — the working tree will be clean
#   post-rebase, which trips the `no changes to commit` gate.
#
# Exit codes:
#   0  commit created and pushed successfully.
#   1  nothing to commit / commit failed / push failed.
#   2  missing / malformed args.

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "error: usage: commit-and-push-phase.sh <FEAT-ID> <phase-N> <phase-name>" >&2
  exit 2
fi

feat_id="$1"
phase_n="$2"
phase_name="$3"

if [[ ! "$feat_id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  echo "error: <FEAT-ID> must match ^(FEAT|CHORE|BUG)-[0-9]+$, got: ${feat_id}" >&2
  exit 2
fi

if [[ ! "$phase_n" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: <phase-N> must be a positive integer, got: ${phase_n}" >&2
  exit 2
fi

# Non-empty / non-whitespace phase name.
trimmed_name="${phase_name#"${phase_name%%[![:space:]]*}"}"
trimmed_name="${trimmed_name%"${trimmed_name##*[![:space:]]}"}"
if [ -z "$trimmed_name" ]; then
  echo "error: <phase-name> must be non-empty / non-whitespace" >&2
  exit 2
fi

# Derive commit type prefix.
case "$feat_id" in
  FEAT-*)  type_prefix="feat" ;;
  CHORE-*) type_prefix="chore" ;;
  BUG-*)   type_prefix="fix" ;;
  *)
    echo "error: unexpected <FEAT-ID> prefix: ${feat_id}" >&2
    exit 2
    ;;
esac

message="${type_prefix}(${feat_id}): complete phase ${phase_n} - ${phase_name}"

# Step 1: check for changes.
status_output=$(git status --porcelain=v1)
if [ -z "$status_output" ]; then
  echo "error: no changes to commit" >&2
  exit 1
fi

# Step 2: stage.
if ! git add -A; then
  echo "[error] git add failed" >&2
  exit 1
fi

# Step 3: commit (hook stderr surfaces verbatim).
if ! git commit -m "$message"; then
  exit 1
fi

# Step 4: determine branch.
branch=$(git rev-parse --abbrev-ref HEAD)

# Step 5: probe upstream.
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  push_cmd=(git push)
else
  push_cmd=(git push -u origin "$branch")
fi

# Step 6/7: push + surface stderr verbatim on failure.
if "${push_cmd[@]}"; then
  echo "pushed ${branch}"
  exit 0
else
  echo "[error] push failed; see Push Failure Recovery in SKILL.md" >&2
  exit 1
fi
