#!/usr/bin/env bash
set -euo pipefail

# qa-baseline.sh — Manage the HEAD-marker baseline for executing-qa diff guard.
#
# Usage:
#   qa-baseline.sh init <ID>   — write .sdlc/qa/.executing-qa-baseline-<ID>
#                                containing the current git HEAD SHA. Idempotent.
#   qa-baseline.sh clear <ID>  — remove the marker. Exit 0 always.
#
# Exit codes:
#   0 — success
#   2 — missing / invalid args

MARKER_DIR=".sdlc/qa"

subcmd="${1:-}"
id="${2:-}"

if [[ -z "$subcmd" ]]; then
  echo "Error: subcommand required (init|clear)." >&2
  exit 2
fi

if [[ -z "$id" ]]; then
  echo "Error: ID argument required." >&2
  exit 2
fi

MARKER_PATH="${MARKER_DIR}/.executing-qa-baseline-${id}"

case "$subcmd" in
  init)
    mkdir -p "$MARKER_DIR"
    git rev-parse HEAD > "$MARKER_PATH"
    ;;
  clear)
    rm -f "$MARKER_PATH"
    ;;
  *)
    echo "Error: unknown subcommand '${subcmd}' (expected init|clear)." >&2
    exit 2
    ;;
esac
