#!/usr/bin/env bash
# fetch-issue.sh — Fetch issue details and emit normalized JSON on stdout.
#
# Usage: fetch-issue.sh <issue-ref>
#
# Sequence (FR-6):
#   1. backend-detect.sh <issue-ref>
#      - null   → stdout `null`, exit 0
#      - github → GitHub pre-flight + `gh issue view <N> --json ...`
#      - jira   → Jira tiered fetch (Rovo MCP → acli → skip)
#   2. Output shape (normalized across backends):
#      { "title", "body", "labels", "state", "assignees" }
#
# Exit codes:
#   0 success, OR any graceful-degradation skip (stdout is empty; stderr
#     carries the [warn] line per the SKILL.md Graceful Degradation table).
#     On no-reference input, stdout is the literal string `null`.
#   2 missing arg
#
# NEVER exits non-zero for external-command failure. [warn] strings match
# the managing-work-items SKILL.md tables verbatim (NFR-1).

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "[error] usage: fetch-issue.sh <issue-ref>" >&2
  exit 2
fi

issue_ref="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/backend-detect.sh"

# ---------- backend detection ----------

detect_out="$(bash "$DETECT" "$issue_ref" 2>/dev/null || true)"

if [ -z "$detect_out" ] || [ "$detect_out" = "null" ]; then
  printf 'null\n'
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

# ---------- GitHub path ----------

if [ "$backend" = "github" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo '[warn] GitHub CLI (`gh`) not found on PATH. Skipping GitHub issue operations.' >&2
    exit 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo '[warn] GitHub CLI not authenticated -- run `gh auth login` to enable issue tracking.' >&2
    exit 0
  fi

  gh_stderr_file="$(mktemp)"
  if ! gh_out="$(gh issue view "$issue_number" --json title,body,labels,state,assignees 2>"$gh_stderr_file")"; then
    gh_err="$(cat "$gh_stderr_file" 2>/dev/null || true)"
    rm -f "$gh_stderr_file"
    # Match the SKILL.md Graceful Degradation table for "Issue does not exist"
    # and generic command failures — both use [warn] skip pattern.
    if printf '%s' "$gh_err" | grep -qi 'not found\|could not resolve'; then
      echo "[warn] \`gh issue view\` returned not found for #${issue_number}. Skipping." >&2
    else
      echo "[warn] gh: gh issue view failed: ${gh_err}. Skipping." >&2
    fi
    exit 0
  fi
  rm -f "$gh_stderr_file"
  printf '%s\n' "$gh_out"
  exit 0
fi

# ---------- Jira path ----------

if [ "$backend" = "jira" ]; then
  issue_key="${project_key}-${issue_number}"

  tier1_available=0
  if command -v rovo-mcp-invoke >/dev/null 2>&1; then
    tier1_available=1
  fi

  if [ "$tier1_available" = "1" ]; then
    cloud_id="${ROVO_CLOUD_ID:-}"
    rovo_stderr_file="$(mktemp)"
    if rovo_out="$(rovo-mcp-invoke getJiraIssue "${cloud_id}" "${issue_key}" 2>"$rovo_stderr_file")"; then
      rm -f "$rovo_stderr_file"
      # Project the Jira issue object into the normalized shape.
      if command -v jq >/dev/null 2>&1; then
        normalized="$(printf '%s' "$rovo_out" | jq -c '{
          title: (.fields.summary // ""),
          body: (.fields.description // ""),
          labels: (.fields.labels // []),
          state: (.fields.status.name // ""),
          assignees: (
            if .fields.assignee then [.fields.assignee.displayName] else [] end
          )
        }' 2>/dev/null)" || normalized=""
        if [ -n "$normalized" ]; then
          printf '%s\n' "$normalized"
          exit 0
        fi
      fi
      # jq missing or projection failed — fall through to Tier 2.
    else
      rovo_err="$(cat "$rovo_stderr_file" 2>/dev/null || true)"
      rm -f "$rovo_stderr_file"
      echo "[warn] Rovo MCP tool \`getJiraIssue\` returned unexpected response: ${rovo_err}. Falling through to acli." >&2
      # fall through to Tier 2
    fi
  fi

  # Tier 2: acli.
  if ! command -v acli >/dev/null 2>&1; then
    echo "[warn] No Jira backend available (Rovo MCP not registered, acli not found). Skipping Jira operations." >&2
    exit 0
  fi

  acli_stderr_file="$(mktemp)"
  if ! acli_out="$(acli jira workitem view --key "$issue_key" 2>"$acli_stderr_file")"; then
    acli_err="$(cat "$acli_stderr_file" 2>/dev/null || true)"
    rm -f "$acli_stderr_file"
    if printf '%s' "$acli_err" | grep -qi 'not found'; then
      echo "[warn] Jira issue ${issue_key} not found. Skipping." >&2
    else
      echo "[warn] acli: acli command failed: ${acli_err}. Skipping." >&2
    fi
    exit 0
  fi
  rm -f "$acli_stderr_file"

  # Parse `acli jira workitem view` structured text into normalized JSON.
  # acli emits lines like:  Summary: Foo / Description: Bar / Status: Done /
  # Labels: a, b / Assignee: Alice  — tolerant parse, missing fields → "".
  title=""
  body=""
  state=""
  labels_csv=""
  assignee=""
  while IFS= read -r line; do
    case "$line" in
      Summary:*|summary:*|Title:*|title:*)
        title="${line#*:}"
        title="${title# }"
        ;;
      Description:*|description:*|Body:*|body:*)
        body="${line#*:}"
        body="${body# }"
        ;;
      Status:*|status:*|State:*|state:*)
        state="${line#*:}"
        state="${state# }"
        ;;
      Labels:*|labels:*)
        labels_csv="${line#*:}"
        labels_csv="${labels_csv# }"
        ;;
      Assignee:*|assignee:*)
        assignee="${line#*:}"
        assignee="${assignee# }"
        ;;
    esac
  done <<< "$acli_out"

  # Build normalized JSON. Prefer jq for proper escaping; fall back to a
  # best-effort string concat when jq is unavailable.
  if command -v jq >/dev/null 2>&1; then
    labels_json="[]"
    if [ -n "$labels_csv" ]; then
      labels_json="$(printf '%s' "$labels_csv" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')"
    fi
    assignees_json="[]"
    if [ -n "$assignee" ]; then
      assignees_json="$(printf '%s' "$assignee" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')"
    fi
    jq -cn \
      --arg title "$title" \
      --arg body "$body" \
      --argjson labels "$labels_json" \
      --arg state "$state" \
      --argjson assignees "$assignees_json" \
      '{title: $title, body: $body, labels: $labels, state: $state, assignees: $assignees}'
  else
    # Pure-bash JSON (no embedded-quote escaping beyond basic safety).
    printf '{"title":"%s","body":"%s","labels":[],"state":"%s","assignees":[]}\n' \
      "${title//\"/\\\"}" "${body//\"/\\\"}" "${state//\"/\\\"}"
  fi
  exit 0
fi

# Unknown backend (shouldn't happen) — behave like null.
printf 'null\n'
exit 0
