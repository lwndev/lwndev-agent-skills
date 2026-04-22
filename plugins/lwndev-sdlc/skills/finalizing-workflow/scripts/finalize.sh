#!/usr/bin/env bash
# finalize.sh — Top-level orchestrator for the finalizing-workflow skill (FR-1).
#
# Usage: finalize.sh <branch-name>
#
# Composes Phase 1–3 subscripts into the finalize sequence:
#   1. Pre-flight (preflight-checks.sh)
#   2. Branch classification (branch-id-parse.sh)
#   3. Bookkeeping (feature/chore/bug only): resolve doc → idempotency check →
#      (if not idempotent) checkbox flip + completion upsert + affected-files
#      reconcile → commit + push.
#   4. Execution: gh pr merge → git checkout main → git fetch → git pull.
#
# Invariant (NO-ROLLBACK): on any failure after BK-5 commit/push, the script
# MUST NOT revert or reset the bookkeeping commit. Re-invocation relies on
# check-idempotent.sh to skip already-finalized docs.
#
# Exit codes:
#   0  finalize completed (merge succeeded; fetch/pull failures are warnings)
#   1  any fatal failure (subscript abort, merge failure, checkout failure,
#      BK-5 commit/push failure, unexpected subscript exit code)
#   2  missing arg

set -euo pipefail

# Resolve SKILL_DIR = directory containing this script.
# Prefer an explicit SKILL_DIR env override so bats harnesses can shadow
# subscripts without relying on BASH_SOURCE resolution order.
if [ -n "${SKILL_DIR:-}" ]; then
  : # use caller override verbatim
else
  SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# PLUGIN_ROOT = SKILL_DIR/../../.. (skills/<name>/scripts/ → plugin root)
if [ -n "${PLUGIN_ROOT:-}" ]; then
  : # use caller override
else
  PLUGIN_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd)"
fi

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "[error] usage: finalize.sh <branch-name>" >&2
  exit 2
fi

branch="$1"

# -----------------------------------------------------------------------------
# Helpers.
# -----------------------------------------------------------------------------

# extract_json_scalar <json> <key> → stdout value (string, unquoted).
# Prefers jq when available; hand-assembled fallback otherwise.
extract_json_scalar() {
  local json="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // empty'
    return 0
  fi
  # Hand-assembled fallback: key is a scalar (string or number or null).
  # Handle string: "key":"value"  (value may contain escaped quotes — best-effort)
  local s
  s="$(printf '%s' "$json" | sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p")"
  if [ -n "$s" ]; then
    printf '%s' "$s"
    return 0
  fi
  # Handle number: "key":NNN
  s="$(printf '%s' "$json" | sed -n "s/.*\"${key}\":\\([0-9][0-9]*\\).*/\\1/p")"
  if [ -n "$s" ]; then
    printf '%s' "$s"
    return 0
  fi
  # Handle null: "key":null
  if printf '%s' "$json" | grep -q "\"${key}\":null"; then
    printf ''
    return 0
  fi
}

# fatal_unexpected <rc> <subscript> <stderr-file>
fatal_unexpected() {
  local rc="$1" name="$2" stderr_file="$3"
  echo "[error] unexpected exit ${rc} from ${name}" >&2
  if [ -n "${stderr_file:-}" ] && [ -f "$stderr_file" ]; then
    cat "$stderr_file" >&2
  fi
  exit 1
}

# -----------------------------------------------------------------------------
# Step 1: Pre-flight checks.
# -----------------------------------------------------------------------------

run_preflight() {
  local preflight_stdout preflight_stderr preflight_rc
  preflight_stdout="$(mktemp)"
  preflight_stderr="$(mktemp)"

  set +e
  bash "${SKILL_DIR}/preflight-checks.sh" >"$preflight_stdout" 2>"$preflight_stderr"
  preflight_rc=$?
  set -e

  case "$preflight_rc" in
    0)
      # Surface any info notes (e.g. UNKNOWN retry) from stderr verbatim.
      if [ -s "$preflight_stderr" ]; then
        cat "$preflight_stderr" >&2
      fi
      local json
      json="$(cat "$preflight_stdout")"
      rm -f "$preflight_stdout" "$preflight_stderr"
      PR_NUMBER="$(extract_json_scalar "$json" "prNumber")"
      PR_TITLE="$(extract_json_scalar "$json" "prTitle")"
      PR_URL="$(extract_json_scalar "$json" "prUrl")"
      ;;
    1)
      cat "$preflight_stderr" >&2
      rm -f "$preflight_stdout" "$preflight_stderr"
      exit 1
      ;;
    *)
      local saved_stderr="$preflight_stderr"
      rm -f "$preflight_stdout"
      fatal_unexpected "$preflight_rc" "preflight-checks.sh" "$saved_stderr"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Step 2: Branch classification.
# -----------------------------------------------------------------------------

run_branch_parse() {
  local parse_stdout parse_stderr parse_rc
  parse_stdout="$(mktemp)"
  parse_stderr="$(mktemp)"

  set +e
  bash "${PLUGIN_ROOT}/scripts/branch-id-parse.sh" "$branch" >"$parse_stdout" 2>"$parse_stderr"
  parse_rc=$?
  set -e

  case "$parse_rc" in
    0)
      local json
      json="$(cat "$parse_stdout")"
      rm -f "$parse_stdout" "$parse_stderr"
      BRANCH_TYPE="$(extract_json_scalar "$json" "type")"
      BRANCH_ID="$(extract_json_scalar "$json" "id")"
      BRANCH_DIR="$(extract_json_scalar "$json" "dir")"
      ;;
    1)
      # Unrecognized branch: emit canonical info, skip bookkeeping.
      rm -f "$parse_stdout" "$parse_stderr"
      echo "[info] Branch ${branch} does not match workflow ID pattern; skipping bookkeeping." >&2
      BRANCH_TYPE=""
      BRANCH_ID=""
      BRANCH_DIR=""
      BOOKKEEPING_SUMMARY="Bookkeeping: skipped (not a workflow branch)"
      ;;
    *)
      local saved_stderr="$parse_stderr"
      rm -f "$parse_stdout"
      fatal_unexpected "$parse_rc" "branch-id-parse.sh" "$saved_stderr"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Step 3: Bookkeeping.
# -----------------------------------------------------------------------------

# Returns via globals: BOOKKEEPING_SUMMARY, BK_COMMIT_SHA (optional).
run_bookkeeping() {
  # Release branch: silently skip bookkeeping.
  if [ "$BRANCH_TYPE" = "release" ]; then
    BOOKKEEPING_SUMMARY="Bookkeeping: skipped (release branch)"
    return 0
  fi

  # Non-workflow branch: BRANCH_TYPE unset (BOOKKEEPING_SUMMARY already set in
  # run_branch_parse). Nothing to do.
  if [ -z "$BRANCH_TYPE" ]; then
    return 0
  fi

  # feature/chore/bug only from here.
  local resolve_stdout resolve_stderr resolve_rc
  resolve_stdout="$(mktemp)"
  resolve_stderr="$(mktemp)"

  set +e
  bash "${PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" "$BRANCH_ID" >"$resolve_stdout" 2>"$resolve_stderr"
  resolve_rc=$?
  set -e

  local doc=""
  case "$resolve_rc" in
    0)
      doc="$(cat "$resolve_stdout" | head -n 1)"
      rm -f "$resolve_stdout" "$resolve_stderr"
      ;;
    1)
      rm -f "$resolve_stdout" "$resolve_stderr"
      echo "[warn] No requirement doc found for ${BRANCH_ID} under ${BRANCH_DIR}; skipping bookkeeping." >&2
      BOOKKEEPING_SUMMARY="Bookkeeping: skipped (no requirement doc)"
      return 0
      ;;
    2)
      rm -f "$resolve_stdout" "$resolve_stderr"
      echo "[warn] Multiple requirement docs for ${BRANCH_ID} — workspace inconsistency; investigate." >&2
      BOOKKEEPING_SUMMARY="Bookkeeping: skipped (workspace inconsistency)"
      return 0
      ;;
    3)
      rm -f "$resolve_stdout" "$resolve_stderr"
      echo "[warn] Malformed ID ${BRANCH_ID}; skipping bookkeeping." >&2
      BOOKKEEPING_SUMMARY="Bookkeeping: skipped (malformed id)"
      return 0
      ;;
    *)
      local saved_stderr="$resolve_stderr"
      rm -f "$resolve_stdout"
      fatal_unexpected "$resolve_rc" "resolve-requirement-doc.sh" "$saved_stderr"
      ;;
  esac

  # Idempotency check.
  local idem_stdout idem_stderr idem_rc
  idem_stdout="$(mktemp)"
  idem_stderr="$(mktemp)"

  set +e
  bash "${SKILL_DIR}/check-idempotent.sh" "$doc" "$PR_NUMBER" >"$idem_stdout" 2>"$idem_stderr"
  idem_rc=$?
  set -e

  case "$idem_rc" in
    0)
      # Silent-pass: bookkeeping already applied.
      rm -f "$idem_stdout" "$idem_stderr"
      BOOKKEEPING_SUMMARY="Bookkeeping: skipped (requirement doc already finalized)"
      return 0
      ;;
    1)
      # Proceed to BK-4. Do NOT surface the [info] label to the user —
      # it's an internal diagnostic per spec.
      rm -f "$idem_stdout" "$idem_stderr"
      ;;
    *)
      local saved_stderr="$idem_stderr"
      rm -f "$idem_stdout"
      fatal_unexpected "$idem_rc" "check-idempotent.sh" "$saved_stderr"
      ;;
  esac

  # --- BK-4.1: checkbox flip on Acceptance Criteria.
  local flip_stdout flip_stderr flip_rc
  flip_stdout="$(mktemp)"
  flip_stderr="$(mktemp)"

  set +e
  bash "${PLUGIN_ROOT}/scripts/checkbox-flip-all.sh" "$doc" "Acceptance Criteria" >"$flip_stdout" 2>"$flip_stderr"
  flip_rc=$?
  set -e

  if [ "$flip_rc" -ne 0 ]; then
    local saved_stderr="$flip_stderr"
    rm -f "$flip_stdout"
    fatal_unexpected "$flip_rc" "checkbox-flip-all.sh" "$saved_stderr"
  fi

  local flip_out
  flip_out="$(cat "$flip_stdout")"
  rm -f "$flip_stdout" "$flip_stderr"
  # `checked N lines` → extract N.
  local checked_count
  checked_count="$(printf '%s' "$flip_out" | sed -n 's/^checked \([0-9][0-9]*\) lines.*/\1/p')"
  checked_count="${checked_count:-0}"

  # --- BK-4.2: completion upsert.
  local up_stdout up_stderr up_rc
  up_stdout="$(mktemp)"
  up_stderr="$(mktemp)"

  set +e
  bash "${SKILL_DIR}/completion-upsert.sh" "$doc" "$PR_NUMBER" "$PR_URL" >"$up_stdout" 2>"$up_stderr"
  up_rc=$?
  set -e

  if [ "$up_rc" -ne 0 ]; then
    local saved_stderr="$up_stderr"
    rm -f "$up_stdout"
    fatal_unexpected "$up_rc" "completion-upsert.sh" "$saved_stderr"
  fi

  local upsert_mode
  upsert_mode="$(cat "$up_stdout" | head -n 1)"
  rm -f "$up_stdout" "$up_stderr"
  # Sanity: normalize to either "upserted" or "appended".
  case "$upsert_mode" in
    upserted|appended) ;;
    *) upsert_mode="appended" ;;
  esac

  # --- BK-4.3: reconcile affected files.
  local rec_stdout rec_stderr rec_rc
  rec_stdout="$(mktemp)"
  rec_stderr="$(mktemp)"

  set +e
  bash "${SKILL_DIR}/reconcile-affected-files.sh" "$doc" "$PR_NUMBER" >"$rec_stdout" 2>"$rec_stderr"
  rec_rc=$?
  set -e

  local appended_count=0 annotated_count=0
  case "$rec_rc" in
    0)
      local rec_line
      rec_line="$(cat "$rec_stdout" | head -n 1)"
      appended_count="$(printf '%s' "$rec_line" | awk '{print $1}')"
      annotated_count="$(printf '%s' "$rec_line" | awk '{print $2}')"
      appended_count="${appended_count:-0}"
      annotated_count="${annotated_count:-0}"
      rm -f "$rec_stdout" "$rec_stderr"
      ;;
    1)
      # Non-fatal warning. Script already emitted its [warn] on stderr.
      if [ -s "$rec_stderr" ]; then
        cat "$rec_stderr" >&2
      fi
      rm -f "$rec_stdout" "$rec_stderr"
      appended_count=0
      annotated_count=0
      ;;
    *)
      local saved_stderr="$rec_stderr"
      rm -f "$rec_stdout"
      fatal_unexpected "$rec_rc" "reconcile-affected-files.sh" "$saved_stderr"
      ;;
  esac

  BOOKKEEPING_SUMMARY="Bookkeeping: ticked ${checked_count} acceptance criteria, wrote Completion section (${upsert_mode}), reconciled ${appended_count} new + ${annotated_count} annotated affected files"

  # --- BK-5: commit + push if dirty.
  run_bk5 "$doc"
}

# Commit and push the bookkeeping changes if the doc has any diff.
# Sets BK_COMMIT_SHA when a commit was made.
run_bk5() {
  local doc="$1"

  local porcelain
  set +e
  porcelain="$(git status --porcelain -- "$doc" 2>/dev/null)"
  set -e

  if [ -z "$porcelain" ]; then
    # No diff → skip commit and push.
    BK_COMMIT_SHA=""
    return 0
  fi

  # Stage.
  if ! git add "$doc" >/dev/null 2>&1; then
    echo "[error] git add failed for ${doc}" >&2
    exit 1
  fi

  # Check git identity.
  local gname gemail
  set +e
  gname="$(git config user.name 2>/dev/null || true)"
  gemail="$(git config user.email 2>/dev/null || true)"
  set -e
  if [ -z "${gname:-}" ] || [ -z "${gemail:-}" ]; then
    echo "[error] git identity not configured (run 'git config user.name/.email')" >&2
    exit 1
  fi

  # Commit with canonical message. Use a tempfile-backed commit message for
  # multi-line safety.
  local msg_file
  msg_file="$(mktemp)"
  {
    printf 'chore(%s): finalize requirement document\n\n' "$BRANCH_ID"
    printf -- '- Tick completed acceptance criteria\n'
    printf -- '- Set completion status with PR link\n'
    printf -- '- Reconcile affected files against PR diff\n'
  } > "$msg_file"

  set +e
  git commit -F "$msg_file" >/dev/null 2>&1
  local commit_rc=$?
  set -e
  rm -f "$msg_file"

  if [ "$commit_rc" -ne 0 ]; then
    echo "[error] git commit failed" >&2
    exit 1
  fi

  # Capture short SHA for summary.
  local sha
  sha="$(git rev-parse --short HEAD 2>/dev/null || echo '')"

  # Push.
  set +e
  local push_err
  push_err="$(git push 2>&1 >/dev/null)"
  local push_rc=$?
  set -e
  if [ "$push_rc" -ne 0 ]; then
    if [ -n "$push_err" ]; then
      printf '%s\n' "$push_err" >&2
    fi
    echo "[error] git push failed" >&2
    exit 1
  fi

  BK_COMMIT_SHA="$sha"
}

# -----------------------------------------------------------------------------
# Step 4: Execution (merge + checkout + fetch + pull).
# NO-ROLLBACK: do NOT call `git revert` or `git reset --hard` under any
# circumstance in this script.
# -----------------------------------------------------------------------------

run_execution() {
  # Merge.
  set +e
  local merge_err
  merge_err="$(gh pr merge --merge --delete-branch 2>&1 >/dev/null)"
  local merge_rc=$?
  set -e
  if [ "$merge_rc" -ne 0 ]; then
    if [ -n "$merge_err" ]; then
      printf '%s\n' "$merge_err" >&2
    fi
    echo "[error] gh pr merge failed" >&2
    exit 1
  fi

  # Checkout main.
  set +e
  local co_err
  co_err="$(git checkout main 2>&1 >/dev/null)"
  local co_rc=$?
  set -e
  if [ "$co_rc" -ne 0 ]; then
    if [ -n "$co_err" ]; then
      printf '%s\n' "$co_err" >&2
    fi
    echo "[error] git checkout failed; note that merge already succeeded" >&2
    exit 1
  fi

  # Fetch (non-fatal).
  set +e
  local fetch_err
  fetch_err="$(git fetch origin 2>&1 >/dev/null)"
  local fetch_rc=$?
  set -e
  if [ "$fetch_rc" -ne 0 ]; then
    echo "[warn] git fetch failed: ${fetch_err}" >&2
    FINAL_STATE_LINE="On main, fetch/pull skipped"
    return 0
  fi

  # Pull (non-fatal).
  set +e
  local pull_err
  pull_err="$(git pull 2>&1 >/dev/null)"
  local pull_rc=$?
  set -e
  if [ "$pull_rc" -ne 0 ]; then
    echo "[warn] git pull failed: ${pull_err}" >&2
    FINAL_STATE_LINE="On main, fetch/pull skipped"
    return 0
  fi

  FINAL_STATE_LINE="On main, up to date"
}

# -----------------------------------------------------------------------------
# Main.
# -----------------------------------------------------------------------------

PR_NUMBER=""
PR_TITLE=""
PR_URL=""
BRANCH_TYPE=""
BRANCH_ID=""
BRANCH_DIR=""
BOOKKEEPING_SUMMARY=""
BK_COMMIT_SHA=""
FINAL_STATE_LINE=""

run_preflight
run_branch_parse
run_bookkeeping
run_execution

# Final stdout report.
printf 'Merged PR #%s — %s\n' "$PR_NUMBER" "$PR_TITLE"
printf '%s\n' "$BOOKKEEPING_SUMMARY"
if [ -n "$BK_COMMIT_SHA" ]; then
  printf 'Pushed bookkeeping commit as %s\n' "$BK_COMMIT_SHA"
fi
printf '%s\n' "$FINAL_STATE_LINE"

exit 0
