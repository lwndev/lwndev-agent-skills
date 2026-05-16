#!/usr/bin/env bash
# resolve-pr-number.sh — Extract the canonical PR number after an
# executing-chores / executing-bug-fixes / pr-creation fork (FEAT-028 FR-4).
#
# Usage: resolve-pr-number.sh <branch> [subagent-output-file]
#
# Resolution strategy (first match wins):
#   1. Delegate to the managing-source-control `list-pr.sh --head <branch>`
#      dispatcher (FEAT-033 FR-4). The dispatcher returns a normalized JSON
#      array of `{number, state}` entries (NFR-3); we filter for `state ==
#      "OPEN"` and take the first element when exactly one OPEN PR exists.
#      This is the authoritative source — the underlying SCM (GitHub or
#      Azure DevOps) knows which PR the branch currently tracks.
#   2. Fallback: scan <subagent-output-file> (if supplied and readable) for
#      `#<digits>` tokens and `https://github.com/<owner>/<repo>/pull/<N>`
#      URLs. Fenced markdown code blocks (```...```) are skipped so example
#      snippets don't pollute the match. The last match in line-order wins.
#   3. If neither source yields a number: empty stdout, exit 1.
#
# Dispatcher graceful-skip ([warn]/[info]) or `jq` missing → skip step 1 and
# fall through to step 2. If step 2 also fails AND the dispatcher was
# unavailable, emit:
#   [warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list.
# to stderr and exit 1.
#
# A supplied but non-existent <subagent-output-file> is non-fatal — skip to
# the next step.
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

# --- step 1: list-pr.sh authoritative lookup ---------------------------------

_RPN_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST_PR_DISPATCHER=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh" ]; then
  LIST_PR_DISPATCHER="${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh"
elif [ -f "${_RPN_SCRIPT_DIR}/../../managing-source-control/scripts/list-pr.sh" ]; then
  LIST_PR_DISPATCHER="$(cd "${_RPN_SCRIPT_DIR}/../../managing-source-control/scripts" && pwd)/list-pr.sh"
fi

gh_available=0
if [ -n "$LIST_PR_DISPATCHER" ] && command -v jq >/dev/null 2>&1; then
  gh_available=1
  _rpn_stderr_tmp="$(mktemp)"
  gh_out="$(bash "$LIST_PR_DISPATCHER" --head "$branch" 2>"$_rpn_stderr_tmp" || true)"
  gh_stderr="$(cat "$_rpn_stderr_tmp" 2>/dev/null || true)"
  rm -f "$_rpn_stderr_tmp"

  # Treat dispatcher graceful-skip ([warn]/[info]) as unavailable.
  if printf '%s' "$gh_stderr" | grep -Eq '^\[(warn|info)\]'; then
    gh_available=0
  else
    # Filter for OPEN entries only — the dispatcher returns all states on the
    # GitHub path (`--state open` was previously a gh flag; we replicate via
    # post-filter for cross-backend consistency).
    open_entries=$(printf '%s' "$gh_out" | jq -c '[.[] | select(.state=="OPEN")]' 2>/dev/null || echo "")
    open_count=$(printf '%s' "$open_entries" | jq -r 'length' 2>/dev/null || echo "err")
    if [ "$open_count" = "1" ]; then
      gh_num=$(printf '%s' "$open_entries" | jq -r '.[0].number' 2>/dev/null || echo "")
      if [[ "$gh_num" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$gh_num"
        exit 0
      fi
    fi
    # 0 or 2+ results → fall through to subagent-output parsing.
  fi
fi

# --- step 2: scan subagent output with fence filter + line-order match -------

if [ -n "$subagent_output" ] && [ -r "$subagent_output" ]; then
  last_num=""
  in_fence=0
  while IFS= read -r line; do
    # Toggle fence state on any line starting with three backticks. The
    # marker line itself is not scanned.
    if [[ "$line" =~ ^\`\`\` ]]; then
      in_fence=$((1 - in_fence))
      continue
    fi
    [ "$in_fence" -eq 1 ] && continue

    # URL first (more specific), then bare `#N`, on the same line.
    while IFS= read -r hit; do
      num="${hit##*/pull/}"
      num="${num%%[^0-9]*}"
      [[ "$num" =~ ^[0-9]+$ ]] && last_num="$num"
    done < <(printf '%s\n' "$line" | grep -oE 'https://github\.com/[^[:space:]/]+/[^[:space:]/]+/pull/[0-9]+' || true)

    while IFS= read -r hit; do
      num="${hit#\#}"
      [[ "$num" =~ ^[0-9]+$ ]] && last_num="$num"
    done < <(printf '%s\n' "$line" | grep -oE '#[0-9]+' || true)
  done < "$subagent_output"

  if [ -n "$last_num" ]; then
    printf '%s\n' "$last_num"
    exit 0
  fi
fi

# --- step 3: no match from either source -------------------------------------

if [ "$gh_available" -eq 0 ]; then
  echo "[warn] resolve-pr-number: gh unavailable; could not fall back to gh pr list." >&2
fi
exit 1
