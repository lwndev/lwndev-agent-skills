#!/usr/bin/env bash
# create-pr.sh — Thin dispatcher shim (FEAT-033 Phase 3 transition).
#
# This shim delegates to the skill-scoped dispatcher:
#   plugins/lwndev-sdlc/skills/managing-source-control/scripts/create-pr.sh
#
# It exists for one phase so consumers that still reference the old plugin-level
# path (executing-chores, executing-bug-fixes, implementing-plan-phases) keep
# working while Phase 5 updates their SKILL.md path references. Phase 5 removes
# this shim.
#
# Args are forwarded verbatim. Exit code is the dispatcher's exit code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DELEGATE="${PLUGIN_ROOT}/skills/managing-source-control/scripts/create-pr.sh"

if [ ! -x "$DELEGATE" ]; then
  echo "error: skill-scoped create-pr.sh not found: ${DELEGATE}" >&2
  exit 1
fi

exec bash "$DELEGATE" "$@"
