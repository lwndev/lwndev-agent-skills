#!/usr/bin/env bash
# resolve-pr-number.sh — Extract the canonical PR number after an
# executing-chores / executing-bug-fixes / pr-creation fork (FEAT-028 FR-4).
#
# Usage: resolve-pr-number.sh <branch> [subagent-output-file]
#
# Resolution strategy (first match wins):
#   1. If <subagent-output-file> is supplied and exists: scan for `#<digits>`
#      tokens and `https://github.com/<owner>/<repo>/pull/<N>` URLs; the last
#      match wins (forks tend to echo the final PR number near end-of-output).
#      If multiple candidates disagree, the last candidate is canonical.
#   2. Fallback: `gh pr list --head "<branch>" --json number,state` filtered
#      with jq to the first OPEN PR's number. Empty / null result falls
#      through.
#   3. If neither source yields a number: empty stdout, exit 1.
#
# A supplied but non-existent <subagent-output-file> is non-fatal — skip to
# step 2.
#
# `gh` missing or unauthenticated → emit:
#   [warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list.
# to stderr and exit 1.
#
# Emits the resolved PR number as a bare integer on stdout (no JSON).
#
# Exit codes:
#   0 resolved number
#   1 no source yielded a match, or gh unavailable / unauthenticated
#   2 missing <branch> arg

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] resolve-pr-number: usage: resolve-pr-number.sh <branch> [subagent-output-file]" >&2
  exit 2
fi

branch="$1"
subagent_output="${2:-}"

# --- step 1: scan subagent output file ---------------------------------------

if [ -n "$subagent_output" ] && [ -r "$subagent_output" ]; then
  # Collect all `#<digits>` tokens and `/pull/<digits>` URL tails. grep -oE
  # returns one per line; we want the last match across both.
  last_num=""

  # GitHub PR URL match: capture the trailing integer after /pull/.
  while IFS= read -r hit; do
    # hit looks like https://github.com/owner/repo/pull/232; strip to number.
    num="${hit##*/pull/}"
    # trim any trailing non-digit chars (punctuation after URL).
    num="${num%%[^0-9]*}"
    if [[ "$num" =~ ^[0-9]+$ ]]; then
      last_num="$num"
    fi
  done < <(grep -oE 'https://github\.com/[^[:space:]/]+/[^[:space:]/]+/pull/[0-9]+' "$subagent_output" || true)

  # `#<digits>` token match.
  while IFS= read -r hit; do
    # hit looks like #232; strip leading '#'.
    num="${hit#\#}"
    if [[ "$num" =~ ^[0-9]+$ ]]; then
      last_num="$num"
    fi
  done < <(grep -oE '#[0-9]+' "$subagent_output" || true)

  if [ -n "$last_num" ]; then
    printf '%s\n' "$last_num"
    exit 0
  fi
fi

# --- step 2: gh pr list fallback ---------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  echo "[warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list." >&2
  exit 1
fi

# `gh pr list` fails loudly on auth errors; capture and translate to the same
# graceful-fail warn shape so the caller only has to handle one exit path.
gh_output=""
gh_status=0
gh_output=$(gh pr list --head "$branch" --json number,state --jq '[.[] | select(.state=="OPEN")][0].number' 2>/dev/null) || gh_status=$?

if [ "$gh_status" -ne 0 ]; then
  echo "[warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list." >&2
  exit 1
fi

# gh may emit literal "null" or empty string when no match.
gh_output="${gh_output//$'\n'/}"
if [ -z "$gh_output" ] || [ "$gh_output" = "null" ]; then
  exit 1
fi

if [[ ! "$gh_output" =~ ^[0-9]+$ ]]; then
  exit 1
fi

printf '%s\n' "$gh_output"
exit 0
