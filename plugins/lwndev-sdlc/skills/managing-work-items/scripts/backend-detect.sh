#!/usr/bin/env bash
# backend-detect.sh — Classify an issue reference into a backend identity.
#
# Usage: backend-detect.sh <issue-ref>
#
# Applies two regexes to the trimmed argument and emits JSON on match:
#   ^#([0-9]+)$                 → {"backend":"github","issueNumber":<N>}
#   ^([A-Z][A-Z0-9]*)-([0-9]+)$ → {"backend":"jira","projectKey":"<KEY>","issueNumber":<N>}
# No match → emit the literal string `null` on stdout (no quotes).
#
# Trimming: leading/trailing whitespace is stripped before regex matching.
# A post-trim empty string is a usage error.
#
# This script is the shared primitive consumed by pr-link.sh,
# post-issue-comment.sh, and fetch-issue.sh. It has no external dependencies
# (no jq, no gh, no acli, no network) — pure string matching.
#
# Exit codes:
#   0 any classification (including `null`)
#   2 missing/empty arg (post-trim)

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] usage: backend-detect.sh <issue-ref>" >&2
  exit 2
fi

raw="$1"

# Trim leading/trailing whitespace (spaces, tabs, newlines).
ref="$raw"
# shellcheck disable=SC2295
ref="${ref#"${ref%%[![:space:]]*}"}"
# shellcheck disable=SC2295
ref="${ref%"${ref##*[![:space:]]}"}"

if [ -z "$ref" ]; then
  echo "[error] usage: backend-detect.sh <issue-ref>" >&2
  exit 2
fi

if [[ "$ref" =~ ^#([0-9]+)$ ]]; then
  # Force base-10 interpretation so leading zeros are stripped; JSON numbers
  # with a leading zero (e.g., 007) are invalid per RFC 8259.
  n=$((10#${BASH_REMATCH[1]}))
  printf '{"backend":"github","issueNumber":%d}\n' "$n"
  exit 0
fi

if [[ "$ref" =~ ^([A-Z][A-Z0-9]*)-([0-9]+)$ ]]; then
  key="${BASH_REMATCH[1]}"
  n=$((10#${BASH_REMATCH[2]}))
  printf '{"backend":"jira","projectKey":"%s","issueNumber":%d}\n' "$key" "$n"
  exit 0
fi

printf 'null\n'
exit 0
