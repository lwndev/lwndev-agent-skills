#!/usr/bin/env bash
# view-pr.sh — Dispatcher: fetch PR state and emit normalized JSON.
#
# Usage: view-pr.sh [<pr-number>]
#
# Behavior (FEAT-033 / FR-4):
#   1. Call `backend-detect.sh`; branch on `backend` field.
#   2. GitHub path:
#      - `command -v gh` missing → `[warn] GitHub CLI (gh) not found on PATH.` exit 0.
#      - `gh auth status` failing → `[warn] GitHub CLI not authenticated -- run gh auth login.` exit 0.
#      - `gh pr view [<N>] --json number,title,state,mergeable,url,files` — projection
#        chosen to be the union of all consumer reads:
#          preflight-checks.sh:152      reads number,title,state,mergeable,url
#          reconcile-affected-files.sh  reads files
#      - When <pr-number> is omitted, `gh pr view` infers PR from the current branch.
#      - Emit JSON on stdout (gh's stdout) on success; exit 0.
#      - On non-zero `gh` exit, surface stderr's first line as `[warn]` and exit 0
#        (graceful degradation — NFR-1).
#   3. Azure DevOps path (Phase 3 stub): `[warn] Azure DevOps PR view not yet implemented.` exit 0.
#   4. Unrecognized / null backend: `[info] No recognized SCM backend detected from origin.` exit 0.
#
# Exit codes:
#   0 success (PR JSON on stdout), graceful-degradation skip ([warn]/[info]),
#     or stubbed AzDO path

set -euo pipefail

# Positional: optional <pr-number>.
pr_number=""
if [ "$#" -ge 1 ]; then
  pr_number="$1"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
  else
    if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
      backend="${BASH_REMATCH[1]}"
    fi
  fi
fi

case "$backend" in
  github)
    if ! command -v gh >/dev/null 2>&1; then
      echo "[warn] GitHub CLI (gh) not found on PATH." >&2
      exit 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
      echo "[warn] GitHub CLI not authenticated -- run gh auth login." >&2
      exit 0
    fi

    gh_stderr_file="$(mktemp)"
    if [ -n "$pr_number" ]; then
      if ! gh_out="$(gh pr view "$pr_number" --json number,title,state,mergeable,url,files 2>"$gh_stderr_file")"; then
        gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
        rm -f "$gh_stderr_file"
        echo "[warn] gh pr view failed: ${gh_err}" >&2
        exit 0
      fi
    else
      if ! gh_out="$(gh pr view --json number,title,state,mergeable,url,files 2>"$gh_stderr_file")"; then
        gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
        rm -f "$gh_stderr_file"
        echo "[warn] gh pr view failed: ${gh_err}" >&2
        exit 0
      fi
    fi
    rm -f "$gh_stderr_file"
    printf '%s\n' "$gh_out"
    exit 0
    ;;
  azdo)
    echo "[warn] Azure DevOps PR view not yet implemented." >&2
    exit 0
    ;;
  "")
    echo "[info] No recognized SCM backend detected from origin." >&2
    exit 0
    ;;
  *)
    echo "[info] No recognized SCM backend detected from origin." >&2
    exit 0
    ;;
esac
