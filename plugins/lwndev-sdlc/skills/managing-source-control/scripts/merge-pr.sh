#!/usr/bin/env bash
# merge-pr.sh — Dispatcher: merge a pull request and delete the source branch.
#
# Usage: merge-pr.sh [<pr-number>]
#
# Behavior (FEAT-033 / FR-3, FR-7):
#   1. Call `backend-detect.sh`; branch on `backend` field.
#   2. GitHub path: `gh pr merge [<N>] --merge --delete-branch`.
#   3. Azure DevOps path: `az repos pr update --id <N> --status completed
#                          --delete-source-branch true --squash false`.
#   4. NFR-1 graceful-skip paths for both backends.
#   5. Unrecognized / null backend → `[info]` skip; exit 0.
#
# `--merge` on the gh path forces a merge commit (parity with the existing
# finalize.sh behavior). `--squash false` on the az path opts out of squash
# to maximize parity with `gh --merge` (the AzDO branch policy may still
# override; see Risk Assessment in the implementation plan).
#
# Preserves the finalize.sh stderr-capture pattern: on non-zero CLI exit,
# emit the first line of stderr as `[warn]` and exit 0 (graceful skip per
# NFR-1) so the workflow continues.
#
# Exit codes:
#   0 success or graceful skip ([warn]/[info])
#   2 usage error

set -euo pipefail

pr_number=""
if [ "$#" -ge 1 ]; then
  pr_number="$1"
fi

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
    set +e
    if [ -n "$pr_number" ]; then
      gh pr merge "$pr_number" --merge --delete-branch 2>"$gh_stderr_file"
    else
      gh pr merge --merge --delete-branch 2>"$gh_stderr_file"
    fi
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
      rm -f "$gh_stderr_file"
      echo "[warn] gh pr merge failed: ${gh_err}" >&2
      exit 0
    fi
    rm -f "$gh_stderr_file"
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

    if [ -z "$pr_number" ]; then
      echo "[warn] Azure DevOps merge requires --id; pr_number argument missing." >&2
      exit 0
    fi

    az_org_url=""
    if [ -n "$organization" ]; then
      az_org_url="https://dev.azure.com/${organization}/"
    fi

    az_stderr_file="$(mktemp)"
    set +e
    az repos pr update \
      --id "$pr_number" \
      --status completed \
      --delete-source-branch true \
      --squash false \
      ${az_org_url:+--organization "$az_org_url"} \
      >/dev/null 2>"$az_stderr_file"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      az_err="$(head -n 1 "$az_stderr_file" 2>/dev/null || true)"
      rm -f "$az_stderr_file"
      echo "[warn] az repos pr update failed: ${az_err}" >&2
      exit 0
    fi
    rm -f "$az_stderr_file"
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
