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
# Behavior (FEAT-034 / FR-1 FR-2 FR-3 FR-4 FR-6):
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
#   4. Azure DevOps path (FR-2 / FR-3 / FR-4):
#      - NFR-1 skips: `az` missing, `az devops` extension missing, `az` not
#        authenticated → `[warn]` + exit 0.
#      - Resolve repositoryId via `az repos show`.
#      - Probe the `az devops invoke` resource-name across
#        `PullRequestThreads → pullrequestthreads → threads`; cache the winner
#        at `/tmp/sdlc-azdo-pr-thread-resource.<org>.<repo>` with 24h TTL.
#      - On probe exhaustion: write `probe-failed` sentinel; `[warn]` + exit 0.
#      - Top-level: POST a new thread; emit
#        `https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<prId>?discussionId=<threadId>`.
#      - Reply (--reply-to <thread-id>): GET existing thread comments, resolve
#        max comment id as parentCommentId, POST to threads/<id>/comments.
#        On 404 emit `[warn] ADO thread <id> not found; skipping reply.` exit 0.
#      - curl fallback (FR-4): `SDLC_AZDO_HTTP=curl` forces, or non-zero `az devops invoke`
#        POST auto-falls-through. Missing `AZURE_DEVOPS_PAT` → `[warn]` + exit 0.
#   5. Null / unrecognized backend:
#      `[info] No recognized SCM backend detected from origin. Skipping PR comment.` exit 0.
#
# Exit codes:
#   0  success (comment URL on stdout), graceful-degradation skip ([warn]/[info])
#   1  internal error (jq missing on ADO path, malformed args otherwise rejected
#      by the parser)
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
az_org=""
az_project=""
az_repo=""
if [ -n "$detect_out" ] && [ "$detect_out" != "null" ]; then
  if command -v jq >/dev/null 2>&1; then
    backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
    az_org="$(printf '%s' "$detect_out" | jq -r '.organization // ""' 2>/dev/null || true)"
    az_project="$(printf '%s' "$detect_out" | jq -r '.project // ""' 2>/dev/null || true)"
    az_repo="$(printf '%s' "$detect_out" | jq -r '.repo // ""' 2>/dev/null || true)"
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
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Resolve the comment body (used by both backends; the GitHub path supports the
# --body-file shortcut but ADO needs a literal string for the JSON payload).
# ---------------------------------------------------------------------------
resolve_body() {
  if [ "$body_file_set" -eq 1 ]; then
    cat "$body_file"
  elif [ "$positional_set" -eq 1 ]; then
    printf '%s' "$positional_body"
  else
    printf '%s' "$body_flag"
  fi
}

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
    # NFR-1: graceful skip paths (verbatim lines from SKILL.md matrix).
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
      echo "[error] jq is required for the ADO pr-comment path." >&2
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

    # ----- Resource-name probe + 24h cache (NFR-3 / Edge 4). ---------------
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
        printf '%s\n%s\n' "$(date +%s)" "probe-failed" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
        echo "[warn] ADO PR-thread resource probe failed across [PullRequestThreads, pullrequestthreads, threads]. Skipping comment." >&2
        exit 0
      fi

      printf '%s\n%s\n' "$(date +%s)" "$resource_token" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
    fi

    # ----- Resolve body now (needed for both top-level + reply paths). ----
    body_content="$(resolve_body)"

    # ----- Helpers shared by the create paths. -----------------------------
    pr_url_base="https://dev.azure.com/${az_org}/${az_project}/_git/${az_repo}/pullrequest/${pr_number}"

    use_curl_path="${SDLC_AZDO_HTTP:-}"
    pat_value="${AZURE_DEVOPS_PAT:-}"

    require_pat_or_skip() {
      if [ -z "$pat_value" ]; then
        echo "[warn] AZURE_DEVOPS_PAT not set; cannot post PR comment via raw HTTP. Skipping." >&2
        exit 0
      fi
    }

    # POST top-level thread via curl (FR-4 fallback).
    curl_create_top_level() {
      require_pat_or_skip
      local payload_file="$1"
      local auth_header
      auth_header="Authorization: Basic $(printf ':%s' "$pat_value" | base64)"
      local url="https://dev.azure.com/${az_org}/${az_project}/_apis/git/repositories/${repo_id}/pullRequests/${pr_number}/threads?api-version=7.1"
      local response
      response="$(curl -sS -X POST "$url" \
        -H "$auth_header" \
        -H 'Content-Type: application/json' \
        --data-binary @"$payload_file" 2>/dev/null || true)"
      if [ -z "$response" ]; then
        echo "[warn] curl POST returned empty response; skipping." >&2
        rm -f "$payload_file"
        exit 0
      fi
      local thread_id
      thread_id="$(printf '%s' "$response" | jq -r '.id // empty' 2>/dev/null || true)"
      if [ -z "$thread_id" ] || [ "$thread_id" = "null" ]; then
        echo "[warn] curl POST response did not contain a thread id; skipping." >&2
        rm -f "$payload_file"
        exit 0
      fi
      printf '%s?discussionId=%s\n' "$pr_url_base" "$thread_id"
      rm -f "$payload_file"
      exit 0
    }

    # POST reply via curl.
    curl_create_reply() {
      require_pat_or_skip
      local thread_id="$1"
      local payload_file="$2"
      local auth_header
      auth_header="Authorization: Basic $(printf ':%s' "$pat_value" | base64)"
      local url="https://dev.azure.com/${az_org}/${az_project}/_apis/git/repositories/${repo_id}/pullRequests/${pr_number}/threads/${thread_id}/comments?api-version=7.1"
      local response
      response="$(curl -sS -X POST "$url" \
        -H "$auth_header" \
        -H 'Content-Type: application/json' \
        --data-binary @"$payload_file" 2>/dev/null || true)"
      if [ -z "$response" ]; then
        echo "[warn] curl POST returned empty response; skipping." >&2
        rm -f "$payload_file"
        exit 0
      fi
      printf '%s?discussionId=%s\n' "$pr_url_base" "$thread_id"
      rm -f "$payload_file"
      exit 0
    }

    # ----- Reply path (FR-3). ---------------------------------------------
    if [ "$reply_to_set" -eq 1 ]; then
      # GET the existing thread.
      get_stderr_file="$(mktemp)"
      set +e
      thread_json="$(az devops invoke \
        --area git \
        --resource "$resource_token" \
        --route-parameters "project=${az_project}" "repositoryId=${repo_id}" "pullRequestId=${pr_number}" "threadId=${reply_to}" \
        --http-method GET \
        --api-version 7.1 \
        --organization "$az_org_url" 2>"$get_stderr_file")"
      rc=$?
      set -e
      if [ "$rc" -ne 0 ]; then
        get_err="$(cat "$get_stderr_file" 2>/dev/null || true)"
        rm -f "$get_stderr_file"
        # Heuristic 404 detection.
        if printf '%s' "$get_err" | grep -qiE '(404|not found|TF401174|does not exist)'; then
          echo "[warn] ADO thread ${reply_to} not found; skipping reply." >&2
          exit 0
        fi
        first_line="$(printf '%s\n' "$get_err" | head -n 1)"
        echo "[warn] az devops invoke (thread GET) failed: ${first_line}" >&2
        exit 0
      fi
      rm -f "$get_stderr_file"

      parent_comment_id=0
      if [ -n "$thread_json" ]; then
        max_id="$(printf '%s' "$thread_json" | jq -r '[.comments[]?.id] | max // 0' 2>/dev/null || true)"
        if [[ "$max_id" =~ ^[0-9]+$ ]]; then
          parent_comment_id="$max_id"
        fi
      fi

      reply_payload_file="$(mktemp)"
      jq -n \
        --arg body "$body_content" \
        --argjson parent "$parent_comment_id" \
        '{parentCommentId: $parent, content: $body, commentType: 1}' \
        > "$reply_payload_file"

      if [ "$use_curl_path" = "curl" ]; then
        curl_create_reply "$reply_to" "$reply_payload_file"
        # curl_create_reply exits.
      fi

      reply_stderr_file="$(mktemp)"
      set +e
      az devops invoke \
        --area git \
        --resource "$resource_token" \
        --route-parameters "project=${az_project}" "repositoryId=${repo_id}" "pullRequestId=${pr_number}" "threadId=${reply_to}" \
        --http-method POST \
        --in-file "$reply_payload_file" \
        --api-version 7.1 \
        --organization "$az_org_url" \
        >/dev/null 2>"$reply_stderr_file"
      rc=$?
      set -e

      if [ "$rc" -ne 0 ]; then
        reply_err="$(cat "$reply_stderr_file" 2>/dev/null || true)"
        rm -f "$reply_stderr_file"
        if [ -n "$pat_value" ]; then
          echo "[warn] az devops invoke failed; falling back to raw HTTP via curl." >&2
          curl_create_reply "$reply_to" "$reply_payload_file"
        else
          first_line="$(printf '%s\n' "$reply_err" | head -n 1)"
          echo "[warn] az devops invoke (reply POST) failed: ${first_line}" >&2
          rm -f "$reply_payload_file"
          exit 0
        fi
      fi
      rm -f "$reply_stderr_file" "$reply_payload_file"

      printf '%s?discussionId=%s\n' "$pr_url_base" "$reply_to"
      exit 0
    fi

    # ----- Top-level thread create (FR-2). --------------------------------
    payload_file="$(mktemp)"
    jq -n \
      --arg body "$body_content" \
      '{comments: [{parentCommentId: 0, content: $body, commentType: 1}], status: 1}' \
      > "$payload_file"

    if [ "$use_curl_path" = "curl" ]; then
      curl_create_top_level "$payload_file"
      # curl_create_top_level exits.
    fi

    post_stderr_file="$(mktemp)"
    set +e
    post_out="$(az devops invoke \
      --area git \
      --resource "$resource_token" \
      --route-parameters "project=${az_project}" "repositoryId=${repo_id}" "pullRequestId=${pr_number}" \
      --http-method POST \
      --in-file "$payload_file" \
      --api-version 7.1 \
      --organization "$az_org_url" 2>"$post_stderr_file")"
    rc=$?
    set -e

    if [ "$rc" -ne 0 ]; then
      post_err="$(cat "$post_stderr_file" 2>/dev/null || true)"
      rm -f "$post_stderr_file"
      if [ -n "$pat_value" ]; then
        echo "[warn] az devops invoke failed; falling back to raw HTTP via curl." >&2
        curl_create_top_level "$payload_file"
      else
        first_line="$(printf '%s\n' "$post_err" | head -n 1)"
        echo "[warn] az devops invoke (thread POST) failed: ${first_line}" >&2
        rm -f "$payload_file"
        exit 0
      fi
    fi
    rm -f "$post_stderr_file"

    thread_id="$(printf '%s' "$post_out" | jq -r '.id // empty' 2>/dev/null || true)"
    rm -f "$payload_file"

    if [ -z "$thread_id" ] || [ "$thread_id" = "null" ]; then
      echo "[warn] ADO thread POST response did not contain an id; skipping." >&2
      exit 0
    fi

    printf '%s?discussionId=%s\n' "$pr_url_base" "$thread_id"
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
