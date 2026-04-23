#!/usr/bin/env bash
# post-issue-comment.sh — Composite: detect backend, pre-flight, render, post.
#
# Usage: post-issue-comment.sh <issue-ref> <type> <context-json>
#
# Sequence (FR-5):
#   1. backend-detect.sh <issue-ref>
#      - null  → [info] skip, exit 0
#      - github → GitHub pre-flight + post
#      - jira  → Jira tiered pre-flight (Rovo MCP → acli → skip) + post
#   2. Pre-flight (GitHub): `command -v gh` and `gh auth status`.
#   3. Render via render-issue-comment.sh <backend> <type> <context-json> [<tier>].
#      On exit 1 (render failure) emit [warn] and exit 0.
#   4. Post via `gh issue comment <N> --body` (GitHub), `addCommentToJiraIssue`
#      (Jira rovo tier) with acli fallback, or `acli jira workitem
#      comment-create` (Jira acli tier).
#
# Exit codes:
#   0 success, OR any graceful-degradation skip path (no-backend, pre-flight
#     fail, render fail, post fail) — issue ops are supplementary (NFR-1).
#   2 malformed args (missing type, malformed JSON)
#
# NEVER exits non-zero for external-command failure. [warn]/[info] strings
# match the managing-work-items SKILL.md tables verbatim (NFR-1).

set -euo pipefail

# ---------- arg validation ----------

if [ "$#" -lt 3 ]; then
  echo "[error] usage: post-issue-comment.sh <issue-ref> <type> <context-json>" >&2
  exit 2
fi

issue_ref="$1"
type_="$2"
context_json="$3"

# Type must be one of the six recognized types.
case "$type_" in
  phase-start|phase-completion|work-start|work-complete|bug-start|bug-complete) ;;
  *)
    echo "[error] post-issue-comment: invalid type: ${type_}" >&2
    exit 2
    ;;
esac

# JSON parse pre-check — fails fast on malformed context.
if command -v jq >/dev/null 2>&1; then
  if ! printf '%s' "$context_json" | jq -e . >/dev/null 2>&1; then
    err="$(printf '%s' "$context_json" | jq . 2>&1 >/dev/null || true)"
    echo "[error] post-issue-comment: malformed context JSON: ${err}" >&2
    exit 2
  fi
else
  stripped="${context_json#"${context_json%%[![:space:]]*}"}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  case "$stripped" in
    \{*\}) : ;;
    *)
      echo "[error] post-issue-comment: malformed context JSON (jq unavailable; expected object literal)" >&2
      exit 2
      ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"
RENDER="${SCRIPT_DIR}/render-issue-comment.sh"

# ---------- Step 1: backend detection ----------

# Forward issue_ref to backend-detect; its exit-2 (empty ref) is treated as
# "no reference provided" per FR-5 and the SKILL.md detection logic.
detect_out="$(bash "$DETECT" "$issue_ref" 2>/dev/null || true)"

if [ -z "$detect_out" ] || [ "$detect_out" = "null" ]; then
  echo "[info] No issue reference provided, skipping issue operations." >&2
  exit 0
fi

backend=""
issue_number=""
project_key=""

if command -v jq >/dev/null 2>&1; then
  backend="$(printf '%s' "$detect_out" | jq -r '.backend // ""' 2>/dev/null || true)"
  issue_number="$(printf '%s' "$detect_out" | jq -r '.issueNumber // ""' 2>/dev/null || true)"
  project_key="$(printf '%s' "$detect_out" | jq -r '.projectKey // ""' 2>/dev/null || true)"
else
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

# ---------- helper: render + emit warn on failure ----------

render_body() {
  local be="$1" tier="${2:-acli}" rendered rc
  local stderr_file
  stderr_file="$(mktemp)"
  rendered="$(bash "$RENDER" "$be" "$type_" "$context_json" "$tier" 2>"$stderr_file")"
  rc=$?
  local stderr_content
  stderr_content="$(cat "$stderr_file" 2>/dev/null || true)"
  rm -f "$stderr_file"
  if [ "$rc" -ne 0 ]; then
    echo "[warn] Failed to render ${type_} comment for ${issue_ref}: ${stderr_content}. Skipping." >&2
    return 1
  fi
  printf '%s' "$rendered"
  return 0
}

# ---------- GitHub path ----------

if [ "$backend" = "github" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    # Verbatim match to managing-work-items SKILL.md Graceful Degradation table.
    echo '[warn] GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations.' >&2
    exit 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo '[warn] GitHub CLI not authenticated -- run `gh auth login` to enable issue tracking.' >&2
    exit 0
  fi

  if ! rendered="$(render_body github)"; then
    exit 0
  fi

  # Capture stderr only; drop stdout (gh prints comment URL which we don't
  # re-emit to keep success silent on our stdout).
  gh_stderr_file="$(mktemp)"
  if ! gh issue comment "$issue_number" --body "$rendered" >/dev/null 2>"$gh_stderr_file"; then
    gh_err="$(cat "$gh_stderr_file" 2>/dev/null || true)"
    rm -f "$gh_stderr_file"
    echo "[warn] gh: gh issue comment failed: ${gh_err}" >&2
    exit 0
  fi
  rm -f "$gh_stderr_file"
  exit 0
fi

# ---------- Jira path ----------

if [ "$backend" = "jira" ]; then
  issue_key="${project_key}-${issue_number}"

  # Tier 1: Rovo MCP. We don't have direct shell access to MCP tools; detect
  # availability via the `rovo-mcp-invoke` helper convention if present (bats
  # stubs this path). If not present, fall through to Tier 2.
  tier1_available=0
  if command -v rovo-mcp-invoke >/dev/null 2>&1; then
    tier1_available=1
  fi

  if [ "$tier1_available" = "1" ]; then
    # Render ADF for Rovo.
    if rendered_adf="$(render_body jira rovo)"; then
      cloud_id="${ROVO_CLOUD_ID:-}"
      if rovo_err="$(rovo-mcp-invoke addCommentToJiraIssue "${cloud_id}" "${issue_key}" "${rendered_adf}" 2>&1 >/dev/null)"; then
        exit 0
      else
        echo "[warn] Rovo MCP tool \`addCommentToJiraIssue\` returned unexpected response: ${rovo_err}. Falling through to acli." >&2
        # fall through to Tier 2
      fi
    else
      # render failure already warned; fall through to Tier 2
      :
    fi
  fi

  # Tier 2: acli.
  if ! command -v acli >/dev/null 2>&1; then
    # Tier 3 skip — no Jira backend available.
    echo "[warn] No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations." >&2
    exit 0
  fi

  # acli takes markdown (same as GitHub templates).
  if ! rendered_md="$(render_body jira acli)"; then
    exit 0
  fi

  acli_stderr_file="$(mktemp)"
  if ! acli jira workitem comment-create --key "$issue_key" --body "$rendered_md" >/dev/null 2>"$acli_stderr_file"; then
    acli_err="$(cat "$acli_stderr_file" 2>/dev/null || true)"
    rm -f "$acli_stderr_file"
    echo "[warn] acli: acli command failed: ${acli_err}" >&2
    exit 0
  fi
  rm -f "$acli_stderr_file"
  exit 0
fi

# Unknown backend (shouldn't happen) — treat as null/skip.
echo "[info] No issue reference provided, skipping issue operations." >&2
exit 0
