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
#   3. Azure DevOps path (FEAT-033 / Phase 4):
#      a. NFR-1 skips: `az` missing, `az devops` extension missing, `az` not
#         authenticated, network/non-zero CLI exit → `[warn]` + exit 0.
#      b. When <pr-number> omitted, resolve via
#         `az repos pr list --source-branch $(git rev-parse --abbrev-ref HEAD)
#         --status active --top 1 --query '[0].pullRequestId' -o tsv`.
#         No open PR → `[warn] no open PR for current branch` exit 0.
#      c. `az repos pr show --id <N>` → transform to gh shape via
#         `az-shape-transform.sh show` (FR-5).
#      d. Reconstruct `files` via `git diff --name-only
#         origin/<targetRefName-stripped>...HEAD` and splice into the
#         normalized JSON (NFR-3).
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
TRANSFORM="${SCRIPT_DIR}/az-shape-transform.sh"

detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
az_org=""
az_project=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    az_org="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
    az_project="$(printf '%s' "$detect_out" | jq -r '.project // ""' 2>/dev/null || true)"
  else
    if [[ "$detect_out" =~ \"backend\":\"([^\"]+)\" ]]; then
      backend="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"organization\":\"([^\"]+)\" ]]; then
      az_org="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"project\":\"([^\"]+)\" ]]; then
      az_project="${BASH_REMATCH[1]}"
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
    if [ -n "$az_org" ]; then
      az_org_url="https://dev.azure.com/${az_org}/"
    fi

    # Resolve PR ID if not provided.
    resolved_pr="$pr_number"
    if [ -z "$resolved_pr" ]; then
      cur_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      if [ -n "$cur_branch" ]; then
        az_stderr_file="$(mktemp)"
        set +e
        resolved_pr="$(az repos pr list \
          --source-branch "$cur_branch" \
          --status active \
          --top 1 \
          --query '[0].pullRequestId' \
          -o tsv \
          ${az_org_url:+--organization "$az_org_url"} \
          ${az_project:+--project "$az_project"} \
          2>"$az_stderr_file")"
        rc=$?
        set -e
        rm -f "$az_stderr_file"
        if [ "$rc" -ne 0 ]; then
          resolved_pr=""
        fi
        # Normalize the tsv output: strip trailing newline/whitespace; treat
        # literal "null" (jq query miss) as empty.
        resolved_pr="${resolved_pr%$'\n'}"
        resolved_pr="${resolved_pr%$'\r'}"
        if [ "$resolved_pr" = "null" ]; then
          resolved_pr=""
        fi
      fi
      if [ -z "$resolved_pr" ]; then
        echo "[warn] no open PR for current branch" >&2
        exit 0
      fi
    fi

    # Fetch PR JSON via az repos pr show.
    az_stderr_file="$(mktemp)"
    set +e
    az_out="$(az repos pr show \
      --id "$resolved_pr" \
      ${az_org_url:+--organization "$az_org_url"} \
      ${az_project:+--project "$az_project"} \
      2>"$az_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      az_err="$(head -n 1 "$az_stderr_file" 2>/dev/null || true)"
      rm -f "$az_stderr_file"
      echo "[warn] az repos pr show failed: ${az_err}" >&2
      exit 0
    fi
    rm -f "$az_stderr_file"

    # Transform to gh shape.
    if ! command -v jq >/dev/null 2>&1; then
      echo "[warn] jq required for AzDO shape transformation" >&2
      exit 0
    fi

    normalized="$(bash "$TRANSFORM" show - <<<"$az_out" 2>/dev/null || true)"
    if [ -z "$normalized" ]; then
      echo "[warn] az-shape-transform failed to normalize PR JSON" >&2
      exit 0
    fi

    # Reconstruct files via `git diff --name-only origin/<base>...HEAD`.
    target_ref="$(printf '%s' "$az_out" | jq -r '.targetRefName // ""' 2>/dev/null || true)"
    base_branch="${target_ref#refs/heads/}"
    files_json="[]"
    if [ -n "$base_branch" ]; then
      git fetch origin "$base_branch" >/dev/null 2>&1 || true
      files_raw="$(git diff --name-only "origin/${base_branch}...HEAD" 2>/dev/null || true)"
      if [ -n "$files_raw" ]; then
        files_json="$(printf '%s\n' "$files_raw" | jq -Rcn '[ inputs | { path: . } ]' 2>/dev/null || true)"
        if [ -z "$files_json" ]; then
          files_json="[]"
        fi
      fi
    fi

    # Splice files into the normalized JSON.
    final="$(printf '%s' "$normalized" | jq -c --argjson files "$files_json" '.files = $files' 2>/dev/null || true)"
    if [ -z "$final" ]; then
      final="$normalized"
    fi
    printf '%s\n' "$final"
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
