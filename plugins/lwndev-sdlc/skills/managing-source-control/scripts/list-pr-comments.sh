#!/usr/bin/env bash
# list-pr-comments.sh — Dispatcher: list PR comments as NDJSON (one record per
# comment, FR-5 schema, identical field names across backends).
#
# Usage: list-pr-comments.sh <pr-number> [--json]
#
# Behavior (FEAT-034 / FR-5 / FR-6 / NFR-1 / NFR-2):
#   1. Parse args: positional <pr-number> (required, numeric); --json is a
#      no-op reserved flag for forward compat (the script always emits NDJSON).
#   2. Call `backend-detect.sh`; branch on `backend` field.
#   3. GitHub path (FR-5):
#      - NFR-1 skips: `gh` missing, `gh auth status` failing → `[warn]` exit 0
#        with zero NDJSON records.
#      - Invoke `gh api repos/<owner>/<repo>/issues/<pr-number>/comments`.
#      - Non-zero gh exit → `[warn] PR <num> not found on github; skipping
#        comment.` exit 0 with zero records.
#      - For each comment, emit one NDJSON line in chronological order with the
#        FR-5 schema. GitHub does NOT model thread linkage on issue comments,
#        so sentinel values are used: thread_id=0, parent_comment_id=0,
#        thread_status="unknown", status="active", is_deleted=false.
#   4. Azure DevOps path (FR-5):
#      - NFR-1 skips: `az` missing, `az devops` extension missing, `az` not
#        authenticated → `[warn]` exit 0 with zero records.
#      - Resolve repositoryId via `az repos show`.
#      - Reuse the resource-name probe pattern from pr-comment.sh
#        (PullRequestThreads → pullrequestthreads → threads) with a 24h cache
#        at /tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>. Probe exhaustion or
#        `probe-failed` sentinel → `[warn]` exit 0 with zero records.
#      - Invoke `az devops invoke --area git --resource <token>
#        --route-parameters project=<proj> repositoryId=<repoId>
#        pullRequestId=<num> --http-method GET --api-version 7.1`.
#      - Walk .value[] threads; for each, walk .comments[] and emit one NDJSON
#        line per comment with thread_id (thread.id), comment_id, parent
#        (parentCommentId or 0), author (displayName), author_unique_name
#        (uniqueName), published (publishedDate ISO-8601), content,
#        status (commentType-derived: 1 → "active"), is_deleted, and
#        thread_status (thread.status string).
#      - Deleted comments are preserved (is_deleted is a field, not a filter).
#   5. Null / unrecognized backend (Edge 13):
#      `[info] No recognized SCM backend detected from origin. Skipping PR
#      comment.` exit 0 with zero records.
#
# Exit codes:
#   0  success (NDJSON on stdout), graceful-degradation skip ([warn]/[info])
#   1  internal error (jq missing on either backend)
#   2  usage error (missing/invalid <pr-number>)

set -euo pipefail

usage() {
  echo "error: usage: list-pr-comments.sh <pr-number> [--json]" >&2
  exit 2
}

pr_number=""
parsed_pr=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      # no-op reserved flag
      shift
      ;;
    --)
      shift
      if [ "$parsed_pr" -eq 0 ] && [ "$#" -gt 0 ]; then
        pr_number="$1"
        parsed_pr=1
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
        usage
      fi
      shift
      ;;
  esac
done

if [ -z "$pr_number" ]; then
  usage
fi
if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "[error] pr-number must be a numeric PR identifier, got: ${pr_number}" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

detect_out="$(bash "$DETECT" 2>/dev/null || true)"

backend=""
az_org=""
az_project=""
az_repo=""
gh_owner=""
gh_repo=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    az_org="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
    az_project="$(printf '%s' "$detect_out" | jq -r '.project // ""' 2>/dev/null || true)"
    az_repo="$(printf '%s' "$detect_out" | jq -r '.repo // ""' 2>/dev/null || true)"
    gh_owner="$(printf '%s' "$detect_out" | jq -r '.owner // ""' 2>/dev/null || true)"
    gh_repo="$(printf '%s' "$detect_out" | jq -r '.repo // ""' 2>/dev/null || true)"
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
    if [[ "$detect_out" =~ \"repo\":\"([^\"]+)\" ]]; then
      az_repo="${BASH_REMATCH[1]}"
      gh_repo="${BASH_REMATCH[1]}"
    fi
    if [[ "$detect_out" =~ \"owner\":\"([^\"]+)\" ]]; then
      gh_owner="${BASH_REMATCH[1]}"
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

    if ! command -v jq >/dev/null 2>&1; then
      echo "[error] jq is required for list-pr-comments.sh." >&2
      exit 1
    fi

    if [ -z "$gh_owner" ] || [ -z "$gh_repo" ]; then
      echo "[warn] GitHub backend detected but owner/repo missing from backend-detect; skipping." >&2
      exit 0
    fi

    gh_stderr_file="$(mktemp)"
    set +e
    gh_out="$(gh api "repos/${gh_owner}/${gh_repo}/issues/${pr_number}/comments" 2>"$gh_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      rm -f "$gh_stderr_file"
      echo "[warn] PR ${pr_number} not found on github; skipping comment." >&2
      exit 0
    fi
    rm -f "$gh_stderr_file"

    # Flatten GitHub issue comments into FR-5 NDJSON with sentinel values for
    # thread-aware fields. Stream one record per line (jq -c on each element).
    printf '%s' "$gh_out" | jq -c '.[] | {
      thread_id: 0,
      comment_id: .id,
      parent_comment_id: 0,
      author: (.user.login // ""),
      author_unique_name: (.user.login // ""),
      published: (.created_at // ""),
      content: (.body // ""),
      status: "active",
      is_deleted: false,
      thread_status: "unknown"
    }'
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

    if ! command -v jq >/dev/null 2>&1; then
      echo "[error] jq is required for list-pr-comments.sh." >&2
      exit 1
    fi

    if [ -z "$az_org" ] || [ -z "$az_project" ] || [ -z "$az_repo" ]; then
      echo "[warn] ADO backend detected but org/project/repo missing from backend-detect; skipping." >&2
      exit 0
    fi

    az_org_url="https://dev.azure.com/${az_org}/"

    # ----- Resolve repositoryId once. --------------------------------------
    repo_id_stderr_file="$(mktemp)"
    set +e
    repo_id="$(az repos show \
      --repository "$az_repo" \
      --project "$az_project" \
      --organization "$az_org_url" \
      --query id -o tsv 2>"$repo_id_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] || [ -z "$repo_id" ]; then
      repo_err="$(head -n 1 "$repo_id_stderr_file" 2>/dev/null || true)"
      rm -f "$repo_id_stderr_file"
      echo "[warn] az repos show failed: ${repo_err}" >&2
      exit 0
    fi
    rm -f "$repo_id_stderr_file"

    # ----- Resource-name probe + 24h cache (reuses Phase 2 contract). ------
    cache_file="/tmp/sdlc-azdo-pr-thread-resource.${az_org}.${az_repo}"
    cache_ttl=86400  # 24h in seconds
    resource_token=""

    cache_is_fresh=0
    if [ -f "$cache_file" ]; then
      cache_ts="$(head -n 1 "$cache_file" 2>/dev/null || true)"
      if [[ "$cache_ts" =~ ^[0-9]+$ ]]; then
        now="$(date +%s)"
        age=$(( now - cache_ts ))
        if [ "$age" -lt "$cache_ttl" ]; then
          cache_is_fresh=1
        fi
      fi
    fi

    if [ "$cache_is_fresh" -eq 1 ]; then
      cache_payload="$(sed -n '2p' "$cache_file" 2>/dev/null || true)"
      if [ "$cache_payload" = "probe-failed" ]; then
        echo "[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment." >&2
        exit 0
      fi
      if [ -n "$cache_payload" ]; then
        resource_token="$cache_payload"
      fi
    fi

    probe_resource() {
      local token="$1"
      az devops invoke \
        --area git \
        --resource "$token" \
        --route-parameters "project=${az_project}" "repositoryId=${repo_id}" "pullRequestId=${pr_number}" \
        --http-method GET \
        --api-version 7.1 \
        --organization "$az_org_url" \
        >/dev/null 2>&1
    }

    if [ -z "$resource_token" ]; then
      for candidate in PullRequestThreads pullrequestthreads threads; do
        if probe_resource "$candidate"; then
          resource_token="$candidate"
          break
        fi
      done

      if [ -z "$resource_token" ]; then
        printf '%s\n%s\n' "$(date +%s)" "probe-failed" > "$cache_file"
        echo "[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment." >&2
        exit 0
      fi

      printf '%s\n%s\n' "$(date +%s)" "$resource_token" > "$cache_file"
    fi

    # ----- Fetch threads + comments. ---------------------------------------
    list_stderr_file="$(mktemp)"
    set +e
    list_out="$(az devops invoke \
      --area git \
      --resource "$resource_token" \
      --route-parameters "project=${az_project}" "repositoryId=${repo_id}" "pullRequestId=${pr_number}" \
      --http-method GET \
      --api-version 7.1 \
      --organization "$az_org_url" 2>"$list_stderr_file")"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      list_err="$(head -n 1 "$list_stderr_file" 2>/dev/null || true)"
      rm -f "$list_stderr_file"
      echo "[warn] az devops invoke (threads list) failed: ${list_err}" >&2
      exit 0
    fi
    rm -f "$list_stderr_file"

    if [ -z "$list_out" ]; then
      # Empty body: emit zero records.
      exit 0
    fi

    # Map each thread's comments to FR-5 NDJSON, preserving thread linkage.
    # commentType=1 (text) maps to status "active"; otherwise pass through any
    # status field on the comment if present, else default "active".
    # is_deleted: API uses `isDeleted` (camelCase); preserved as boolean.
    # thread_status: thread.status is a string like "active|fixed|wontFix|...";
    # if missing, fall back to "unknown".
    printf '%s' "$list_out" | jq -c '
      .value[]? as $t
      | ($t.status // "unknown") as $tstatus
      | ($t.id // 0) as $tid
      | $t.comments[]? as $c
      | {
          thread_id: $tid,
          comment_id: ($c.id // 0),
          parent_comment_id: ($c.parentCommentId // 0),
          author: (($c.author.displayName) // ""),
          author_unique_name: (($c.author.uniqueName) // ""),
          published: ($c.publishedDate // ""),
          content: ($c.content // ""),
          status: (
            if $c.commentType == 1 then "active"
            elif ($c.status | type) == "string" then $c.status
            else "active"
            end
          ),
          is_deleted: (($c.isDeleted // false) | if type == "boolean" then . else false end),
          thread_status: $tstatus
        }
    '
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
