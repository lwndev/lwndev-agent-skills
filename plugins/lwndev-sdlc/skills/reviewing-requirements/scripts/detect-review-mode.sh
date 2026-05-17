#!/usr/bin/env bash
# detect-review-mode.sh — Mode-precedence resolver for `reviewing-requirements`
# (FEAT-026 / FR-1).
#
# Applies the mode-precedence chain to emit one of:
#   {"mode":"code-review","prNumber":N}
#   {"mode":"test-plan","testPlanPath":"..."}
#   {"mode":"standard"}
#
# Precedence (first match wins):
#   1. --pr <N> flag (explicit user override; does NOT probe gh).
#   2. Open PR via the managing-source-control `list-pr.sh --head <prefix>/<ID>-*`
#      dispatcher (FEAT-033 FR-4), where prefix is feat|chore|fix by ID prefix
#      (FEAT-|CHORE-|BUG-). The dispatcher returns a normalized JSON array of
#      `{number, state}` entries (NFR-3); we filter for `state == "OPEN"` and
#      take the first match.
#   3. Test plan at qa/test-plans/QA-plan-<ID>.md exists.
#   4. Fallback: standard.
#
# When the dispatcher emits a `[warn]`/`[info]` (e.g. `gh` missing, not
# authenticated, no backend), step 2 is silently skipped. When the response
# is a non-empty array whose first OPEN element has no `number` field, a
# [warn] line is emitted and detection falls through to step 3.
#
# Usage:
#   detect-review-mode.sh <ID> [--pr <N>]
#
# Exit codes:
#   0  any recognized outcome (including the `standard` fallback)
#   1  reserved for malformed `gh` response JSON (not reached in practice)
#   2  missing / malformed args (e.g., empty ID, lowercase ID, `FEAT-` with no
#      digits, --pr with a non-numeric value)
#
# Dependencies:
#   bash, test. `gh` optional (graceful skip on missing/unauth). `jq` is
#   optional — when present, used for JSON assembly.

set -euo pipefail

usage() {
  echo "[error] usage: detect-review-mode.sh <ID> [--pr <N>]" >&2
}

# --- Argument parsing ---------------------------------------------------------

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

ID="$1"
shift || true
PR_NUM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      if [[ $# -lt 2 ]]; then
        echo "[warn] detect-review-mode: --pr value must be numeric" >&2
        exit 2
      fi
      PR_NUM="$2"
      if [[ ! "$PR_NUM" =~ ^[0-9]+$ ]]; then
        echo "[warn] detect-review-mode: --pr value must be numeric" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "[error] unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validate ID shape: must be FEAT-<digits>, CHORE-<digits>, or BUG-<digits>.
if [[ -z "$ID" ]]; then
  usage
  exit 2
fi
if [[ ! "$ID" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  echo "[error] detect-review-mode: malformed ID '${ID}' (expected FEAT-N / CHORE-N / BUG-N)" >&2
  exit 2
fi

# --- Helpers ------------------------------------------------------------------

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then HAS_JQ=1; fi

emit_code_review() {
  local n="$1"
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -cn --argjson n "$n" '{mode:"code-review", prNumber:$n}'
  else
    printf '{"mode":"code-review","prNumber":%s}\n' "$n"
  fi
}

emit_test_plan() {
  local p="$1"
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -cn --arg p "$p" '{mode:"test-plan", testPlanPath:$p}'
  else
    printf '{"mode":"test-plan","testPlanPath":"%s"}\n' "$p"
  fi
}

emit_standard() {
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -cn '{mode:"standard"}'
  else
    printf '{"mode":"standard"}\n'
  fi
}

# --- Precedence chain ---------------------------------------------------------

# Step 1: explicit --pr flag.
if [[ -n "$PR_NUM" ]]; then
  emit_code_review "$PR_NUM"
  exit 0
fi

# Step 2: open PR detection via list-pr.sh dispatcher (FEAT-033 FR-4).
# Silent on dispatcher graceful-skip ([warn]/[info]) -> fall through to step 3.
_DRM_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST_PR_DISPATCHER=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh" ]]; then
  LIST_PR_DISPATCHER="${CLAUDE_PLUGIN_ROOT}/skills/managing-source-control/scripts/list-pr.sh"
elif [[ -f "${_DRM_SCRIPT_DIR}/../../managing-source-control/scripts/list-pr.sh" ]]; then
  LIST_PR_DISPATCHER="$(cd "${_DRM_SCRIPT_DIR}/../../managing-source-control/scripts" && pwd)/list-pr.sh"
fi

gh_step_done=0
if [[ -n "$LIST_PR_DISPATCHER" ]]; then
  # Derive branch prefix from ID prefix.
  case "$ID" in
    FEAT-*) branch_prefix="feat" ;;
    CHORE-*) branch_prefix="chore" ;;
    BUG-*) branch_prefix="fix" ;;
    *)     branch_prefix="" ;;
  esac

  if [[ -n "$branch_prefix" ]]; then
    _drm_stderr_tmp="$(mktemp)"
    list_out="$(bash "$LIST_PR_DISPATCHER" --head "${branch_prefix}/${ID}-*" 2>"$_drm_stderr_tmp" || true)"
    list_err="$(cat "$_drm_stderr_tmp" 2>/dev/null || true)"
    rm -f "$_drm_stderr_tmp"

    # Skip if dispatcher emitted [warn]/[info] (graceful-skip path).
    if ! printf '%s' "$list_err" | grep -Eq '^\[(warn|info)\]'; then
      if [[ "$HAS_JQ" -eq 1 ]]; then
        # Filter for OPEN state, take the first element's number.
        first_num=$(printf '%s' "$list_out" | jq -r '[.[] | select(.state=="OPEN")] | .[0].number // empty' 2>/dev/null || true)
        if [[ -n "$first_num" && "$first_num" =~ ^[0-9]+$ ]]; then
          emit_code_review "$first_num"
          exit 0
        fi
        # Non-empty array but no OPEN+number match: warn and fall through.
        len=$(printf '%s' "$list_out" | jq 'length' 2>/dev/null || echo 0)
        if [[ "$len" =~ ^[0-9]+$ ]] && [[ "$len" -gt 0 ]]; then
          # Only warn when there were entries but none satisfied the filter.
          has_open=$(printf '%s' "$list_out" | jq '[.[] | select(.state=="OPEN")] | length' 2>/dev/null || echo 0)
          if [[ "$has_open" =~ ^[0-9]+$ ]] && [[ "$has_open" -gt 0 ]]; then
            echo "[warn] detect-review-mode: gh response missing 'number' field; falling through." >&2
            gh_step_done=1
          fi
        fi
      else
        # Pure-bash: grep numerically for "number":N when an OPEN state is present.
        if [[ "$list_out" != "[]" && -n "$list_out" ]]; then
          # Match the first object whose state is "OPEN" and has a numeric `number`.
          if [[ "$list_out" =~ \{[^}]*\"number\":[[:space:]]*([0-9]+)[^}]*\"state\":[[:space:]]*\"OPEN\" ]]; then
            first_num="${BASH_REMATCH[1]}"
            emit_code_review "$first_num"
            exit 0
          elif [[ "$list_out" =~ \{[^}]*\"state\":[[:space:]]*\"OPEN\"[^}]*\"number\":[[:space:]]*([0-9]+) ]]; then
            first_num="${BASH_REMATCH[1]}"
            emit_code_review "$first_num"
            exit 0
          elif [[ "$list_out" =~ \"state\":[[:space:]]*\"OPEN\" ]]; then
            # An OPEN entry exists but no `number` field — malformed response.
            echo "[warn] detect-review-mode: gh response missing 'number' field; falling through." >&2
            gh_step_done=1
          fi
        fi
      fi
    fi
  fi
fi

# Step 3: test plan at qa/test-plans/QA-plan-<ID>.md.
TEST_PLAN="qa/test-plans/QA-plan-${ID}.md"
if [[ -f "$TEST_PLAN" ]]; then
  emit_test_plan "$TEST_PLAN"
  exit 0
fi

# Step 4: fallback -> standard.
emit_standard
exit 0
