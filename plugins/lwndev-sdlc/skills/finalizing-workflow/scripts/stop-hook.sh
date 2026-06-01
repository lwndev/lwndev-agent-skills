#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Write-surface diff guard for finalizing-workflow.
#
# Reads Claude Code stop-hook JSON from stdin. When a finalize session is
# active (active-marker present), diffs ALL commits made since the
# finalize-start baseline SHA (baseline..HEAD) and blocks Stop if any path
# outside the allowed write surface was mutated.
#
# Allowed write surface: requirements/{features,chores,bugs}/<ID>-*.md only.
# The BK-5 bookkeeping commit (requirement doc alone) MUST pass.
#
# Exit codes:
#   0 — allow stop (no violation; or finalize not active; or stop_hook_active)
#   2 — block stop (mutation outside write surface; actionable error on stderr)
#
# Baseline wiring: SKILL.md Usage section writes:
#   mkdir -p .sdlc/finalize
#   touch .sdlc/finalize/.finalize-active
#   git rev-parse HEAD > .sdlc/finalize/.finalize-baseline-<ID>
# before invoking finalize.sh. This hook reads those markers.

ACTIVE_FILE=".sdlc/finalize/.finalize-active"
BASELINE_DIR=".sdlc/finalize"

# ---------------------------------------------------------------------------
# Active-marker guard.
# ---------------------------------------------------------------------------
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

INPUT="$(cat)" || exit 0
if [[ -z "$INPUT" ]]; then
  exit 0
fi

STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Locate the baseline SHA. Glob for .finalize-baseline-<ID>.
# If the active marker is present but no baseline exists, fail closed.
# ---------------------------------------------------------------------------
BASELINE_FILE=""
FINALIZE_ID=""

# Find a baseline file. There should be exactly one per session.
while IFS= read -r -d '' f; do
  BASELINE_FILE="$f"
  # Extract ID from filename suffix.
  BASENAME="$(basename "$f")"
  FINALIZE_ID="${BASENAME#.finalize-baseline-}"
done < <(find "$BASELINE_DIR" -maxdepth 1 -name '.finalize-baseline-*' -print0 2>/dev/null)

if [[ -z "$BASELINE_FILE" ]]; then
  echo "Stop hook (finalize): active marker present but no baseline file found in '${BASELINE_DIR}'. Cannot verify write surface. Re-run finalizing-workflow from the start." >&2
  exit 2
fi

BASELINE_SHA="$(cat "$BASELINE_FILE")"
if [[ -z "$BASELINE_SHA" ]]; then
  echo "Stop hook (finalize): baseline file '${BASELINE_FILE}' is empty. Cannot compute diff. Re-run finalizing-workflow from the start." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Write-surface check. Allowed: requirements/{features,chores,bugs}/<ID>-*.md
# Any other path is a violation. Covers committed changes (baseline..HEAD),
# plus staged (cached) and working-tree changes to catch incomplete commits.
# ---------------------------------------------------------------------------

# Returns 0 if the path is within the allowed write surface.
path_in_write_surface() {
  local p="$1"
  case "$p" in
    requirements/features/*-*.md) return 0 ;;
    requirements/chores/*-*.md)   return 0 ;;
    requirements/bugs/*-*.md)     return 0 ;;
  esac
  return 1
}

offending=()

# --- Committed changes since baseline (the primary check — overreach commits). ---
while IFS=$'\t' read -r status old_path new_path; do
  [[ -z "$status" ]] && continue

  if [[ "$status" == R* || "$status" == C* ]]; then
    # Rename/copy: both old and new paths are checked.
    if ! path_in_write_surface "$old_path"; then
      offending+=("$old_path")
    fi
    if ! path_in_write_surface "$new_path"; then
      offending+=("$new_path")
    fi
    continue
  fi

  # Non-rename: single path in old_path field.
  if ! path_in_write_surface "$old_path"; then
    offending+=("$old_path")
  fi
done < <(
  git diff --name-status "${BASELINE_SHA}" HEAD 2>/dev/null | awk '
    /^[RC][0-9]*\t/ {
      n = split($0, a, "\t")
      if (n >= 3) print a[1] "\t" a[2] "\t" a[3]
      next
    }
    {
      n = split($0, a, "\t")
      if (n >= 2) print a[1] "\t" a[2] "\t"
    }
  ' || true
)

# --- Staged (cached) changes not yet committed. ---
while IFS=$'\t' read -r status old_path new_path; do
  [[ -z "$status" ]] && continue

  if [[ "$status" == R* || "$status" == C* ]]; then
    if ! path_in_write_surface "$old_path"; then
      offending+=("$old_path (staged)")
    fi
    if ! path_in_write_surface "$new_path"; then
      offending+=("$new_path (staged)")
    fi
    continue
  fi

  if ! path_in_write_surface "$old_path"; then
    offending+=("$old_path (staged)")
  fi
done < <(
  git diff --cached --name-status 2>/dev/null | awk '
    /^[RC][0-9]*\t/ {
      n = split($0, a, "\t")
      if (n >= 3) print a[1] "\t" a[2] "\t" a[3]
      next
    }
    {
      n = split($0, a, "\t")
      if (n >= 2) print a[1] "\t" a[2] "\t"
    }
  ' || true
)

# ---------------------------------------------------------------------------
# Result.
# ---------------------------------------------------------------------------
if [[ ${#offending[@]} -gt 0 ]]; then
  {
    echo "Stop hook (finalize): mutation(s) detected outside the allowed write surface."
    echo "Allowed write surface: requirements/{features,chores,bugs}/<ID>-*.md (requirement doc only)."
    echo "Forbidden operations: git rm, git mv, rm, git restore --staged, and content edits outside that surface."
    echo "Offending path(s):"
    for p in "${offending[@]}"; do
      echo "  $p"
    done
    echo "Revert all mutations outside the write surface before stopping."
  } >&2
  # Do NOT clean up markers — let the user fix the violations first.
  exit 2
fi

# All checks passed. Clean up markers.
rm -f "$ACTIVE_FILE"
rm -f "$BASELINE_FILE"
exit 0
