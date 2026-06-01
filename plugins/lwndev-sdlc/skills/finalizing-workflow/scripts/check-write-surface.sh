#!/usr/bin/env bash
set -euo pipefail

# check-write-surface.sh <baseline-sha>
#
# Pre-merge write-surface guard for finalizing-workflow (BUG-024). `finalize.sh`
# runs this on the feature branch, BEFORE the merge dispatch, so a violation
# aborts the finalize and the unauthorized change never lands in the merge.
#
# Blocks (exit 2) when ANY change touches a path outside the allowed surface:
#   - committed since the baseline  (git diff --name-status <baseline> HEAD)
#   - staged                        (git diff --cached --name-status)
#   - in the working tree           (git diff --name-status)
# This catches the documented overreach (git rm / git mv -> commit -> push) and
# the AC's staged/working-tree cases (e.g. a bare `rm <file>` left unstaged).
#
# Allowed write surface: requirements/{features,chores,bugs}/<ID>-*.md only —
# the requirement doc the BK-5 bookkeeping commit legitimately mutates. Every
# other mutation (git rm, git mv, rm, git restore --staged, content edit) is a
# violation; both rename source AND destination are checked.
#
# Exit codes:
#   0  clean — no out-of-surface change (or no baseline supplied → cannot verify)
#   2  violation — offending paths enumerated on stderr

baseline="${1:-}"
if [ -z "$baseline" ]; then
  # No baseline to diff against — cannot verify; do NOT block a legit finalize.
  exit 0
fi

# Returns 0 if the path is within the allowed write surface.
path_in_write_surface() {
  case "$1" in
    requirements/features/*-*.md) return 0 ;;
    requirements/chores/*-*.md)   return 0 ;;
    requirements/bugs/*-*.md)     return 0 ;;
  esac
  return 1
}

# Normalize `--name-status` output to a fixed 3-field tab record
# (status<TAB>path1<TAB>path2). Rename/copy rows carry both paths; all others
# carry one path in field 2 and an empty field 3.
NORMALIZE='
  /^[RC][0-9]*\t/ {
    n = split($0, a, "\t")
    if (n >= 3) print a[1] "\t" a[2] "\t" a[3]
    next
  }
  {
    n = split($0, a, "\t")
    if (n >= 2) print a[1] "\t" a[2] "\t"
  }
'

offending=()

# scan <suffix> <git diff command...> — append out-of-surface paths to offending.
scan() {
  local suffix="$1"; shift
  local status old_path new_path
  while IFS=$'\t' read -r status old_path new_path; do
    [ -z "$status" ] && continue
    if [[ "$status" == R* || "$status" == C* ]]; then
      path_in_write_surface "$old_path" || offending+=("${old_path}${suffix}")
      path_in_write_surface "$new_path" || offending+=("${new_path}${suffix}")
      continue
    fi
    path_in_write_surface "$old_path" || offending+=("${old_path}${suffix}")
  done < <("$@" 2>/dev/null | awk "$NORMALIZE" || true)
}

scan ""               git diff --name-status "$baseline" HEAD
scan " (staged)"      git diff --cached --name-status
scan " (working tree)" git diff --name-status

if [ ${#offending[@]} -gt 0 ]; then
  {
    echo "[error] finalize write-surface guard: mutation(s) detected outside the allowed write surface."
    echo "Allowed write surface: requirements/{features,chores,bugs}/<ID>-*.md (requirement doc only)."
    echo "Forbidden: git rm, git mv, rm, git restore --staged, and content edits outside that surface."
    echo "Offending path(s):"
    for p in "${offending[@]}"; do
      echo "  $p"
    done
    echo "Revert all mutations outside the write surface, then re-run finalize."
    echo "If these path(s) are a legitimate fix made after an earlier preflight block,"
    echo "do NOT self-bypass — stop and report 'failed | preflight blocked' to the user"
    echo "for authorization."
  } >&2
  exit 2
fi

exit 0
