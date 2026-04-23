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
#   2. Open PR via `gh pr list --head <prefix>/<ID>-* --json number,state`
#      where prefix is feat|chore|fix by ID prefix (FEAT-|CHORE-|BUG-).
#   3. Test plan at qa/test-plans/QA-plan-<ID>.md exists.
#   4. Fallback: standard.
#
# When `gh` is missing or unauthenticated, step 2 is silently skipped. When
# `gh pr list` returns a non-empty array whose first element has no `number`
# field, a [warn] line is emitted and detection falls through to step 3.
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

# Step 2: open PR detection via gh.
# Silent on gh-missing / unauthenticated -> fall through to step 3.
gh_step_done=0
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    # Derive branch prefix from ID prefix.
    case "$ID" in
      FEAT-*) branch_prefix="feat" ;;
      CHORE-*) branch_prefix="chore" ;;
      BUG-*) branch_prefix="fix" ;;
      *)     branch_prefix="" ;;
    esac

    if [[ -n "$branch_prefix" ]]; then
      # gh pr list filters by --head pattern; use the --jq extractor documented
      # in FR-1 to pick the first OPEN PR's number.
      gh_out=""
      if gh_out=$(gh pr list --head "${branch_prefix}/${ID}-*" --json number,state --jq '[.[] | select(.state=="OPEN")]' 2>/dev/null); then
        # Expect a JSON array. If non-empty, check for `number` on first element.
        if [[ "$HAS_JQ" -eq 1 ]]; then
          len=$(printf '%s' "$gh_out" | jq 'length' 2>/dev/null || echo 0)
          if [[ "$len" =~ ^[0-9]+$ ]] && [[ "$len" -gt 0 ]]; then
            first_num=$(printf '%s' "$gh_out" | jq -r '.[0].number // empty' 2>/dev/null || true)
            if [[ -n "$first_num" && "$first_num" =~ ^[0-9]+$ ]]; then
              emit_code_review "$first_num"
              exit 0
            else
              echo "[warn] detect-review-mode: gh response missing 'number' field; falling through." >&2
              gh_step_done=1
            fi
          fi
        else
          # Pure-bash: grep numerically for "number":N; bail on malformed shape.
          if [[ "$gh_out" != "[]" && -n "$gh_out" ]]; then
            if [[ "$gh_out" =~ \"number\":[[:space:]]*([0-9]+) ]]; then
              first_num="${BASH_REMATCH[1]}"
              emit_code_review "$first_num"
              exit 0
            else
              # Non-empty but no number field -> warn and fall through.
              # (`[]` or empty responses fall to step 3 silently.)
              if [[ "$gh_out" != "[]" && "$gh_out" != "" ]]; then
                echo "[warn] detect-review-mode: gh response missing 'number' field; falling through." >&2
              fi
              gh_step_done=1
            fi
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
