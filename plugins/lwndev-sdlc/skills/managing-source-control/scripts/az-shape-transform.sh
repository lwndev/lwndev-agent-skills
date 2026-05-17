#!/usr/bin/env bash
# az-shape-transform.sh — Normalize `az repos pr show` / `az repos pr list`
# output to the GitHub `gh pr view --json` / `gh pr list --json` shape so
# downstream consumers can parse one canonical JSON shape (FEAT-033 / FR-5,
# NFR-3).
#
# This script is normally **sourced** by the PR dispatchers (`view-pr.sh`,
# `list-pr.sh`) so the transform functions are available in the caller's
# shell. It is also runnable as a standalone command for Bats coverage:
#
#   Usage: az-shape-transform.sh <subcommand> [args...]
#     show <az-show-json>           Transform `az repos pr show` JSON to
#                                   gh pr view --json shape. Reads from
#                                   stdin when the JSON arg is `-`.
#     list <az-list-json>           Transform `az repos pr list` JSON array
#                                   to gh pr list --json shape. Reads from
#                                   stdin when the JSON arg is `-`.
#     state <az-status>             Map azdo status → gh state.
#     mergeable <az-mergeStatus>    Map azdo mergeStatus → gh mergeable.
#
# Field map (per the FR-5 transform table):
#   pullRequestId     → number
#   title             → title
#   status            → state
#                         active     → OPEN
#                         abandoned  → CLOSED
#                         completed  → MERGED
#                         (other)    → UNKNOWN
#   mergeStatus       → mergeable
#                         succeeded  → MERGEABLE
#                         conflicts  → CONFLICTING
#                         queued     → UNKNOWN
#                         notSet     → UNKNOWN
#                         (other)    → UNKNOWN
#   _links.web.href   → url
#   files             → reconstructed via `git diff --name-only
#                       origin/<targetRefName-stripped>...HEAD` and emitted
#                       as [{"path":"a"},{"path":"b"},...]. The transform
#                       script itself takes `targetRefName` only and emits
#                       a stub `files: []`; the caller is expected to
#                       splice in the file list via jq if it has one
#                       (see `view-pr.sh`).
#
# Exit codes:
#   0 success (JSON on stdout)
#   2 missing arg / unrecognized subcommand
#   3 jq missing or parse failure

set -euo pipefail

usage() {
  echo "error: usage: az-shape-transform.sh <show|list|state|mergeable> [args...]" >&2
  exit 2
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[error] jq required for az-shape-transform.sh" >&2
    exit 3
  fi
}

# Pure-bash mappings so callers don't need jq to map a single value.
map_state() {
  case "$1" in
    active)    printf 'OPEN\n' ;;
    abandoned) printf 'CLOSED\n' ;;
    completed) printf 'MERGED\n' ;;
    *)         printf 'UNKNOWN\n' ;;
  esac
}

map_mergeable() {
  case "$1" in
    succeeded) printf 'MERGEABLE\n' ;;
    conflicts) printf 'CONFLICTING\n' ;;
    queued)    printf 'UNKNOWN\n' ;;
    notSet)    printf 'UNKNOWN\n' ;;
    *)         printf 'UNKNOWN\n' ;;
  esac
}

# Read an arg or stdin into a variable. If $1 is "-", read stdin.
read_json_arg() {
  local arg="${1:-}"
  if [ -z "$arg" ]; then
    echo "[error] expected JSON arg or '-' to read stdin" >&2
    exit 2
  fi
  if [ "$arg" = "-" ]; then
    cat
  else
    printf '%s' "$arg"
  fi
}

# Transform `az repos pr show` JSON to gh pr view --json shape.
# Input: az repos pr show object (single PR).
# Output: gh pr view --json {number,title,state,mergeable,url,files} shape.
# The files array is emitted empty `[]` here; callers splice in the git-diff
# reconstruction via jq.
transform_show() {
  local json
  json="$(read_json_arg "${1:-}")"
  require_jq

  printf '%s' "$json" | jq -c '{
    number: (.pullRequestId // null),
    title:  (.title // ""),
    state:  (
      .status as $s |
      if   $s == "active"     then "OPEN"
      elif $s == "abandoned"  then "CLOSED"
      elif $s == "completed"  then "MERGED"
      else "UNKNOWN" end
    ),
    mergeable: (
      .mergeStatus as $m |
      if   $m == "succeeded" then "MERGEABLE"
      elif $m == "conflicts" then "CONFLICTING"
      elif $m == "queued"    then "UNKNOWN"
      elif $m == "notSet"    then "UNKNOWN"
      else "UNKNOWN" end
    ),
    url: ((._links.web.href) // ""),
    files: []
  }'
}

# Transform `az repos pr list` JSON array to gh pr list --json shape:
# array of {number, state}.
transform_list() {
  local json
  json="$(read_json_arg "${1:-}")"
  require_jq

  printf '%s' "$json" | jq -c '[ .[] | {
    number: (.pullRequestId // null),
    state: (
      .status as $s |
      if   $s == "active"     then "OPEN"
      elif $s == "abandoned"  then "CLOSED"
      elif $s == "completed"  then "MERGED"
      else "UNKNOWN" end
    )
  } ]'
}

# When sourced, expose the functions but do not run any subcommand.
# Detect "sourced" by checking BASH_SOURCE[0] vs $0.
sourced=0
if [ "${BASH_SOURCE[0]:-}" != "${0:-}" ]; then
  sourced=1
fi

if [ "$sourced" -eq 1 ]; then
  # Sourced: just return — caller invokes functions directly.
  return 0 2>/dev/null || true
fi

# Standalone invocation.
if [ "$#" -lt 1 ]; then
  usage
fi

sub="$1"
shift

case "$sub" in
  show)
    transform_show "${1:-}"
    ;;
  list)
    transform_list "${1:-}"
    ;;
  state)
    if [ "$#" -lt 1 ]; then
      echo "error: state subcommand requires an arg" >&2
      exit 2
    fi
    map_state "$1"
    ;;
  mergeable)
    if [ "$#" -lt 1 ]; then
      echo "error: mergeable subcommand requires an arg" >&2
      exit 2
    fi
    map_mergeable "$1"
    ;;
  *)
    usage
    ;;
esac
