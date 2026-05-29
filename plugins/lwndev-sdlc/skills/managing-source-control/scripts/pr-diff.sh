#!/usr/bin/env bash
# pr-diff.sh — Dispatcher: emit a unified diff of a pull request vs its base.
#
# Usage: pr-diff.sh <pr-number>
#
# Behavior (FEAT-033 / FR-4):
#   1. Call `backend-detect.sh`; branch on `backend` field.
#   2. GitHub path: `gh pr diff <N>` — emit unified diff on stdout.
#   3. Azure DevOps path:
#      a. base=$(az repos pr show --id <N> --query targetRefName -o tsv)
#         then strip `refs/heads/` prefix.
#      b. `git fetch origin "$base"` (Edge Case 6 — avoid stale diffs).
#      c. `git diff "origin/${base}...HEAD"` → unified diff on stdout.
#   4. NFR-1 graceful-skip paths for both backends.
#   5. Unrecognized / null backend → `[info]` skip; exit 0.
#
# Exit codes:
#   0 success or graceful skip ([warn]/[info])
#   2 usage error

set -euo pipefail

usage() {
  echo "error: usage: pr-diff.sh <pr-number>" >&2
  exit 2
}

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  usage
fi

pr_number="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
organization=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    organization="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
  else
    if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
      backend="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"organization\":\"([^\"]+)\" ]]; then
      organization="${BASH_REMATCH[1]}"
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
    if ! gh_out="$(gh pr diff "$pr_number" 2>"$gh_stderr_file")"; then
      gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
      rm -f "$gh_stderr_file"
      echo "[warn] gh pr diff failed: ${gh_err}" >&2
      exit 0
    fi
    rm -f "$gh_stderr_file"
    printf '%s\n' "$gh_out"
    exit 0
    ;;
  azdo)
    if ! command -v az >/dev/null 2>&1; then
      echo "[warn] Azure CLI (az) not found on PATH." >&2
      exit 0
    fi
    if ! az repos pr -h >/dev/null 2>&1; then
      echo "[warn] az devops extension not available -- run az extension add --name azure-devops." >&2
      exit 0
    fi
    if ! az account show >/dev/null 2>&1; then
      echo "[warn] Azure CLI not authenticated -- run az login (Azure AD) or az devops login --pat <token>." >&2
      exit 0
    fi

    az_org_url=""
    if [ -n "$organization" ]; then
      az_org_url="https://dev.azure.com/${organization}/"
    fi

    az_stderr_file="$(mktemp)"
    set +e
    base_raw="$(az repos pr show \
        --id "$pr_number" \
        --query targetRefName -o tsv \
        ${az_org_url:+--organization "$az_org_url"} \
        2>"$az_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] || [ -z "$base_raw" ]; then
      az_err="$(head -n 1 "$az_stderr_file" 2>/dev/null || true)"
      rm -f "$az_stderr_file"
      echo "[warn] az repos pr show failed: ${az_err}" >&2
      exit 0
    fi
    rm -f "$az_stderr_file"

    base="${base_raw#refs/heads/}"
    base="${base%$'\n'}"
    base="${base%$'\r'}"

    # Edge Case 6: pre-fetch to avoid stale-diff against origin/<base>.
    git fetch origin "$base" >/dev/null 2>&1 || true

    if ! git diff "origin/${base}...HEAD"; then
      echo "[warn] git diff failed for origin/${base}...HEAD" >&2
      exit 0
    fi
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
