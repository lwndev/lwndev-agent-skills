#!/usr/bin/env bash
# list-pr.sh — Dispatcher: list pull requests filtered by head/source branch.
#
# Usage: list-pr.sh --head <branch>
#
# Behavior (FEAT-033 / FR-4, NFR-3):
#   1. Call `backend-detect.sh`; branch on `backend` field.
#   2. GitHub path: `gh pr list --head <branch> --json number,state`.
#      Emits a JSON array on stdout (gh's stdout).
#   3. Azure DevOps path: `az repos pr list --source-branch <branch>
#      --status active`. Normalize to `[{"number":<N>,"state":...},...]`
#      via the FR-5 transform table (`az-shape-transform.sh list`).
#   4. NFR-1 graceful-skip paths for both backends.
#   5. Unrecognized / null backend → `[info]` skip; exit 0.
#
# `--source-branch` on the az path takes the BARE branch name (NOT
# `refs/heads/<branch>`) per `az repos pr` reference docs. `--status active`
# matches the gh default of listing open PRs only.
#
# Exit codes:
#   0 success or graceful skip ([warn]/[info])
#   2 usage error

set -euo pipefail

usage() {
  echo "error: usage: list-pr.sh --head <branch>" >&2
  exit 2
}

head_branch=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --head)
      if [ "$#" -lt 2 ]; then usage; fi
      head_branch="$2"
      shift 2
      ;;
    --head=*)
      head_branch="${1#--head=}"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$head_branch" ]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"
TRANSFORM="${SCRIPT_DIR}/az-shape-transform.sh"

detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
organization=""
project=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    organization="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
    project="$(printf '%s' "$detect_out" | jq -r '.project // ""' 2>/dev/null || true)"
  else
    if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
      backend="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"organization\":\"([^\"]+)\" ]]; then
      organization="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"project\":\"([^\"]+)\" ]]; then
      project="${BASH_REMATCH[1]}"
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
    if ! gh_out="$(gh pr list --head "$head_branch" --json number,state 2>"$gh_stderr_file")"; then
      gh_err="$(head -n 1 "$gh_stderr_file" 2>/dev/null || true)"
      rm -f "$gh_stderr_file"
      echo "[warn] gh pr list failed: ${gh_err}" >&2
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
    if ! az_out="$(az repos pr list \
        --source-branch "$head_branch" \
        --status active \
        ${az_org_url:+--organization "$az_org_url"} \
        ${project:+--project "$project"} \
        2>"$az_stderr_file")"; then
      az_err="$(head -n 1 "$az_stderr_file" 2>/dev/null || true)"
      rm -f "$az_stderr_file"
      echo "[warn] az repos pr list failed: ${az_err}" >&2
      exit 0
    fi
    rm -f "$az_stderr_file"

    # Normalize to gh pr list --json {number,state} shape.
    if [ -z "$az_out" ]; then
      printf '[]\n'
      exit 0
    fi
    normalized="$(bash "$TRANSFORM" list - <<<"$az_out" 2>/dev/null || true)"
    if [ -z "$normalized" ]; then
      # Transform failed (jq missing or parse error) — emit empty array.
      printf '[]\n'
      exit 0
    fi
    printf '%s\n' "$normalized"
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
