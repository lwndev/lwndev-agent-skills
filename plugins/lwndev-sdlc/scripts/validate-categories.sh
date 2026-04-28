#!/usr/bin/env bash
# validate-categories.sh — Validate a chore/bug category against its enum.
#
# Usage: validate-categories.sh <FEAT|CHORE|BUG> <category>
#
# Behavior:
#   FEAT  — exits 0 silently. Features have no category enum; the CLI-level
#           rejection of `--category` for FEAT lives in `new-requirement.sh`,
#           not here. This script is callable directly and a no-op result for
#           FEAT is the correct lower-level behavior.
#   CHORE — accepts: dependencies, documentation, refactoring, configuration,
#           cleanup. Anything else is rejected.
#   BUG   — accepts: runtime-error, logic-error, ui-defect, performance,
#           security, regression. Anything else is rejected.
#
#   Rejection emits `error: invalid <type> category '<category>' (expected:
#   <a>, <b>, ...)` on stderr.
#
# Exit codes:
#   0 valid (or N/A for FEAT)
#   2 usage error or unknown category

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "error: usage: validate-categories.sh <FEAT|CHORE|BUG> <category>" >&2
  exit 2
fi

type_arg="$1"
category="$2"

chore_values=(dependencies documentation refactoring configuration cleanup)
bug_values=(runtime-error logic-error ui-defect performance security regression)

join_csv() {
  # Comma+space separator. IFS only takes the first char on join, so build
  # the joined string manually for predictability.
  local sep=""
  local out=""
  local item
  for item in "$@"; do
    out+="${sep}${item}"
    sep=", "
  done
  printf '%s' "$out"
}

case "$type_arg" in
  FEAT)
    # No enum; silent no-op.
    exit 0
    ;;
  CHORE)
    for v in "${chore_values[@]}"; do
      if [ "$category" = "$v" ]; then
        exit 0
      fi
    done
    echo "error: invalid chore category '$category' (expected: $(join_csv "${chore_values[@]}"))" >&2
    exit 2
    ;;
  BUG)
    for v in "${bug_values[@]}"; do
      if [ "$category" = "$v" ]; then
        exit 0
      fi
    done
    echo "error: invalid bug category '$category' (expected: $(join_csv "${bug_values[@]}"))" >&2
    exit 2
    ;;
  *)
    echo "error: invalid type '$type_arg' (expected FEAT, CHORE, or BUG)" >&2
    exit 2
    ;;
esac
