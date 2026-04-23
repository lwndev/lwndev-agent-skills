#!/usr/bin/env bash
# pr-link.sh — Emit the PR-body issue-link fragment for an issue ref.
#
# Usage: pr-link.sh <issue-ref>
#
# Invokes `backend-detect.sh <issue-ref>` (sibling script) and maps the result:
#   github backend → stdout `Closes #<N>\n`, exit 0
#   jira backend   → stdout `<PROJ-N>\n`, exit 0 (no `Closes` keyword; Jira
#                    does not support GitHub auto-close semantics)
#   null backend   → empty stdout, exit 0
#
# Pure function: same input → same output, deterministic, no network.
#
# Uses jq when available to parse the backend-detect JSON output; falls back
# to pure-bash string parsing otherwise (matches the branch-id-parse.sh
# precedent).
#
# Exit codes:
#   0 any classification (including empty / null)
#   2 missing arg

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] usage: pr-link.sh <issue-ref>" >&2
  exit 2
fi

ref="$1"

# Reject post-trim empty refs with exit 2, matching backend-detect.sh's
# contract. Without this, an empty-string arg would fall through to
# backend-detect, which would exit 2 — but we swallow that exit on line
# below, producing exit 0 with empty output, an inconsistent arg-shape
# contract.
trimmed="$ref"
# shellcheck disable=SC2295
trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
# shellcheck disable=SC2295
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
if [ -z "$trimmed" ]; then
  echo "[error] usage: pr-link.sh <issue-ref>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

# Intentionally do not propagate backend-detect's exit 2 (missing arg) — our
# own caller has already been validated above. Any non-empty ref is forwarded
# to the detector which may emit `null`.
detect_out="$(bash "$DETECT" "$ref")" || true

if [ "$detect_out" = "null" ]; then
  # Empty stdout, exit 0.
  exit 0
fi

backend=""
issue_number=""
project_key=""

if command -v jq >/dev/null 2>&1; then
  backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""')"
  issue_number="$(printf '%s' "$detect_out" | jq -r '.issueNumber // ""')"
  project_key="$(printf '%s' "$detect_out" | jq -r '.projectKey // ""')"
else
  # Pure-bash fallback: extract fields from known JSON shapes produced by
  # backend-detect.sh. The shapes are fixed and ASCII-only.
  if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
    backend="${BASH_REMATCH[1]}"
  fi
  if [[ "$detect_out" =~ \"issueNumber\":([0-9]+) ]]; then
    issue_number="${BASH_REMATCH[1]}"
  fi
  if [[ "$detect_out" =~ \"projectKey\":\"([^\"]+)\" ]]; then
    project_key="${BASH_REMATCH[1]}"
  fi
fi

case "$backend" in
  github)
    printf 'Closes #%s\n' "$issue_number"
    exit 0
    ;;
  jira)
    printf '%s-%s\n' "$project_key" "$issue_number"
    exit 0
    ;;
  *)
    # Unknown / empty backend — treat as null (empty stdout).
    exit 0
    ;;
esac
