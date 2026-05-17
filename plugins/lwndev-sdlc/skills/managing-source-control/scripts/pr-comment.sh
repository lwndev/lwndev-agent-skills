#!/usr/bin/env bash
# pr-comment.sh — Dispatcher: post a top-level comment (or reply) on a pull request.
#
# Usage:
#   pr-comment.sh <pr-number> <body>
#   pr-comment.sh <pr-number> --body <body>
#   pr-comment.sh <pr-number> --body-file <path>
#   pr-comment.sh <pr-number> --body <body> --reply-to <thread-id>
#   pr-comment.sh <pr-number> --body-file <path> --reply-to <thread-id>
#
# Behavior (FEAT-034 / FR-1 FR-2 FR-6):
#   1. Parse args: positional body, --body, --body-file, --reply-to.
#      Mutual-exclusion: at most one of positional / --body / --body-file (Edge 11).
#      --reply-to must be numeric (Edge 12).
#      --body-file must exist (Edge 3).
#   2. Call `backend-detect.sh`; branch on `backend` field.
#   3. GitHub path (FR-1):
#      - `command -v gh` missing → `[warn] GitHub CLI (gh) not found on PATH.` exit 0.
#      - `gh auth status` failing → `[warn] GitHub CLI not authenticated -- run gh auth login.` exit 0.
#      - --reply-to set → `[warn] --reply-to not supported on GitHub backend; skipping.` exit 0.
#      - Invoke `gh pr comment <pr> --body <body>` or `gh pr comment <pr> --body-file <path>`.
#      - Non-zero gh exit → `[warn]` + first stderr line, exit 0 (NFR-1).
#   4. Azure DevOps path (Phase 2 placeholder):
#      - Emit `[info] ADO pr-comment.sh arriving in Phase 2.` exit 0.
#   5. Null / unrecognized backend:
#      - `[info] No recognized SCM backend detected from origin. Skipping PR comment.` exit 0.
#
# Exit codes:
#   0  success (comment URL on stdout), graceful-degradation skip ([warn]/[info]),
#      or Phase-2 ADO stub
#   1  empty-body rejection or other non-usage CLI error
#   2  usage error (missing/invalid args, mutual-exclusion violation, non-numeric id)

set -euo pipefail

usage() {
  echo "error: usage: pr-comment.sh <pr-number> (<body> | --body <body> | --body-file <path>) [--reply-to <thread-id>]" >&2
  exit 2
}

# Argument parsing.
pr_number=""
positional_body=""
body_flag=""
body_file=""
reply_to=""
positional_set=0
body_flag_set=0
body_file_set=0
reply_to_set=0
parsed_pr=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --body)
      if [ "$#" -lt 2 ]; then
        echo "error: --body requires an argument" >&2
        exit 2
      fi
      body_flag="$2"
      body_flag_set=1
      shift 2
      ;;
    --body=*)
      body_flag="${1#--body=}"
      body_flag_set=1
      shift
      ;;
    --body-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --body-file requires an argument" >&2
        exit 2
      fi
      body_file="$2"
      body_file_set=1
      shift 2
      ;;
    --body-file=*)
      body_file="${1#--body-file=}"
      body_file_set=1
      shift
      ;;
    --reply-to)
      if [ "$#" -lt 2 ]; then
        echo "error: --reply-to requires an argument" >&2
        exit 2
      fi
      reply_to="$2"
      reply_to_set=1
      shift 2
      ;;
    --reply-to=*)
      reply_to="${1#--reply-to=}"
      reply_to_set=1
      shift
      ;;
    --)
      shift
      # Remaining positional args after --
      if [ "$parsed_pr" -eq 0 ] && [ "$#" -gt 0 ]; then
        pr_number="$1"
        parsed_pr=1
        shift
      fi
      if [ "$#" -gt 0 ]; then
        positional_body="$1"
        positional_set=1
        shift
      fi
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ "$parsed_pr" -eq 0 ]; then
        pr_number="$1"
        parsed_pr=1
      else
        positional_body="$1"
        positional_set=1
      fi
      shift
      ;;
  esac
done

# Validate pr-number present and numeric.
if [ -z "$pr_number" ]; then
  usage
fi
if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "[error] pr-number must be a numeric PR identifier, got: ${pr_number}" >&2
  exit 2
fi

# Mutual-exclusion: at most one body source (Edge 11).
body_sources=$(( positional_set + body_flag_set + body_file_set ))
if [ "$body_sources" -gt 1 ]; then
  echo "[error] body source ambiguous: pass exactly one of <positional> / --body / --body-file" >&2
  exit 2
fi

# At least one body source required.
if [ "$body_sources" -eq 0 ]; then
  usage
fi

# --reply-to numeric check (Edge 12).
if [ "$reply_to_set" -eq 1 ]; then
  if ! [[ "$reply_to" =~ ^[0-9]+$ ]]; then
    echo "[error] --reply-to must be a numeric thread id" >&2
    exit 2
  fi
fi

# --body-file existence check (Edge 3).
if [ "$body_file_set" -eq 1 ] && [ ! -f "$body_file" ]; then
  echo "[error] body file not found: ${body_file}" >&2
  exit 2
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
    # NFR-1: graceful skip paths.
    if ! command -v gh >/dev/null 2>&1; then
      echo "[warn] GitHub CLI (gh) not found on PATH." >&2
      exit 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
      echo "[warn] GitHub CLI not authenticated -- run gh auth login." >&2
      exit 0
    fi

    # --reply-to on GitHub is a graceful skip (FR-1).
    if [ "$reply_to_set" -eq 1 ]; then
      echo "[warn] --reply-to not supported on GitHub backend; skipping." >&2
      exit 0
    fi

    gh_stderr_file="$(mktemp)"
    set +e
    if [ "$body_file_set" -eq 1 ]; then
      gh_out="$(gh pr comment "$pr_number" --body-file "$body_file" 2>"$gh_stderr_file")"
    else
      # Resolve body from positional or --body flag.
      if [ "$positional_set" -eq 1 ]; then
        body="$positional_body"
      else
        body="$body_flag"
      fi
      gh_out="$(gh pr comment "$pr_number" --body "$body" 2>"$gh_stderr_file")"
    fi
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
      rm -f "$gh_stderr_file"
      echo "[warn] gh pr comment failed: ${gh_err}" >&2
      exit 0
    fi
    rm -f "$gh_stderr_file"
    printf '%s\n' "$gh_out"
    exit 0
    ;;
  azdo)
    # Phase 1 placeholder — full ADO implementation arrives in Phase 2.
    echo "[info] ADO pr-comment.sh arriving in Phase 2." >&2
    exit 0
    ;;
  "")
    echo "[info] No recognized SCM backend detected from origin. Skipping PR comment." >&2
    exit 0
    ;;
  *)
    echo "[info] No recognized SCM backend detected from origin. Skipping PR comment." >&2
    exit 0
    ;;
esac
