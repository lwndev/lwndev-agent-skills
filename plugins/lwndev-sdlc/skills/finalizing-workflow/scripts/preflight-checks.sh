#!/usr/bin/env bash
# preflight-checks.sh — Pre-flight inspection for finalize.sh (FR-2).
#
# Usage: preflight-checks.sh
#
# Runs three read-only checks in parallel, then a sequential build-health
# gate (BUG-013) once the parallel checks pass:
#   1. `git status --porcelain` must be empty (clean working directory).
#   2. `git branch --show-current` must NOT be `main` or `master`.
#   3. `gh pr view --json number,title,state,mergeable,url` must return an
#      OPEN PR with `mergeable` in {MERGEABLE, UNKNOWN}. On UNKNOWN, sleep 2
#      and retry once. If still UNKNOWN, accept and emit a stderr info note.
#   4. Shared `verify-build-health.sh --no-interactive` must exit 0 (lint /
#      format:check / test / build all pass, or graceful skip when no
#      package.json / npm absent).
#
# Output:
#   On success: single-line JSON on stdout
#     {"status":"ok","prNumber":N,"prTitle":"...","prUrl":"..."}
#     Exit 0.
#   On abort: single-line JSON on stdout
#     {"status":"abort","reason":"<verbatim reason>"}
#     Reason on stderr prefixed `[error] preflight: `.
#     Exit 1.
#
# Verbatim abort reasons (matching the pre-refactor SKILL.md Error Handling):
#   - working directory has uncommitted changes
#   - already on main/master; nothing to finalize
#   - no PR found for current branch
#   - PR is not open (state: <STATE>)
#   - PR is not mergeable (<reason>)
#   - build-health check failed (lint / format:check / test / build)
#   - build-health gate unavailable: verify-build-health.sh not found at <paths>
#
# Missing `gh` on PATH:        [error] preflight: gh CLI not found on PATH
# `gh auth status` failure:    [error] preflight: gh CLI not authenticated (run 'gh auth login')
#
# Exit codes:
#   0  all checks passed (prints ok JSON)
#   1  any check aborted (prints abort JSON + [error] stderr)

set -euo pipefail

# Emit JSON using jq when available, hand-assembled fallback otherwise.
emit_ok_json() {
  local prNumber="$1" prTitle="$2" prUrl="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --argjson prNumber "$prNumber" \
      --arg prTitle "$prTitle" \
      --arg prUrl "$prUrl" \
      '{status: "ok", prNumber: $prNumber, prTitle: $prTitle, prUrl: $prUrl}'
  else
    local esc_title esc_url
    esc_title="${prTitle//\\/\\\\}"
    esc_title="${esc_title//\"/\\\"}"
    esc_url="${prUrl//\\/\\\\}"
    esc_url="${esc_url//\"/\\\"}"
    printf '{"status":"ok","prNumber":%s,"prTitle":"%s","prUrl":"%s"}\n' \
      "$prNumber" "$esc_title" "$esc_url"
  fi
}

emit_abort_json() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg reason "$reason" '{status: "abort", reason: $reason}'
  else
    local esc="${reason//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    printf '{"status":"abort","reason":"%s"}\n' "$esc"
  fi
}

abort() {
  local reason="$1"
  emit_abort_json "$reason"
  echo "[error] preflight: ${reason}" >&2
  exit 1
}

# Fatal: gh missing/unauthenticated — no JSON shape required beyond stderr
# per NFR-2 convention; still emit an abort JSON for finalize.sh consumers.
fatal_gh() {
  local reason="$1"
  emit_abort_json "$reason"
  echo "[error] preflight: ${reason}" >&2
  exit 1
}

# Check gh presence and authentication UP FRONT so we can distinguish
# "gh missing" from "PR not found" later.
if ! command -v gh >/dev/null 2>&1; then
  fatal_gh "gh CLI not found on PATH"
fi
if ! gh auth status >/dev/null 2>&1; then
  fatal_gh "gh CLI not authenticated (run 'gh auth login')"
fi

# Parallel check scaffolding: tempfile per child for stdout/stderr/exit.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Check 1: git status --porcelain must be empty.
(
  set +e
  out="$(git status --porcelain 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'git-error\n' > "$tmpdir/status.reason"
    echo "git status failed: ${out}" > "$tmpdir/status.err"
    exit 1
  fi
  if [ -n "$out" ]; then
    printf 'dirty\n' > "$tmpdir/status.reason"
    exit 1
  fi
  printf 'clean\n' > "$tmpdir/status.reason"
  exit 0
) &
pid_status=$!

# Check 2: branch must not be main/master.
(
  set +e
  branch="$(git branch --show-current 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'git-error\n' > "$tmpdir/branch.reason"
    echo "git branch --show-current failed: ${branch}" > "$tmpdir/branch.err"
    exit 1
  fi
  printf '%s\n' "$branch" > "$tmpdir/branch.name"
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    printf 'on-main\n' > "$tmpdir/branch.reason"
    exit 1
  fi
  printf 'feature\n' > "$tmpdir/branch.reason"
  exit 0
) &
pid_branch=$!

# Check 3: gh pr view — OPEN + (MERGEABLE | UNKNOWN w/ retry).
(
  set +e
  pr_json="$(gh pr view --json number,title,state,mergeable,url 2>"$tmpdir/pr.stderr")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # Treat any gh-view failure as "no PR for current branch" per the
    # Error Handling table row.
    printf 'no-pr\n' > "$tmpdir/pr.reason"
    exit 1
  fi

  # Parse with jq when available, fall back to grep-based extraction.
  if command -v jq >/dev/null 2>&1; then
    pr_number="$(printf '%s' "$pr_json" | jq -r '.number')"
    pr_title="$(printf '%s' "$pr_json" | jq -r '.title')"
    pr_state="$(printf '%s' "$pr_json" | jq -r '.state')"
    pr_mergeable="$(printf '%s' "$pr_json" | jq -r '.mergeable')"
    pr_url="$(printf '%s' "$pr_json" | jq -r '.url')"
  else
    # Simple extractor: strip leading/trailing braces and split on ','
    # Only used in the no-jq fallback; values are expected to be scalars.
    pr_number="$(printf '%s' "$pr_json" | sed -n 's/.*"number":\s*\([0-9]\+\).*/\1/p')"
    pr_title="$(printf '%s' "$pr_json" | sed -n 's/.*"title":\s*"\([^"]*\)".*/\1/p')"
    pr_state="$(printf '%s' "$pr_json" | sed -n 's/.*"state":\s*"\([^"]*\)".*/\1/p')"
    pr_mergeable="$(printf '%s' "$pr_json" | sed -n 's/.*"mergeable":\s*"\([^"]*\)".*/\1/p')"
    pr_url="$(printf '%s' "$pr_json" | sed -n 's/.*"url":\s*"\([^"]*\)".*/\1/p')"
  fi

  if [ -z "${pr_number:-}" ] || [ "$pr_number" = "null" ]; then
    printf 'no-pr\n' > "$tmpdir/pr.reason"
    exit 1
  fi

  printf '%s\n' "$pr_number" > "$tmpdir/pr.number"
  printf '%s\n' "$pr_title"  > "$tmpdir/pr.title"
  printf '%s\n' "$pr_url"    > "$tmpdir/pr.url"

  if [ "$pr_state" != "OPEN" ]; then
    printf 'not-open:%s\n' "$pr_state" > "$tmpdir/pr.reason"
    exit 1
  fi

  case "$pr_mergeable" in
    MERGEABLE)
      printf 'mergeable\n' > "$tmpdir/pr.reason"
      exit 0
      ;;
    UNKNOWN)
      sleep 2
      # Retry once.
      pr_json2="$(gh pr view --json number,title,state,mergeable,url 2>"$tmpdir/pr.stderr2" || true)"
      if command -v jq >/dev/null 2>&1; then
        pr_mergeable2="$(printf '%s' "$pr_json2" | jq -r '.mergeable' 2>/dev/null || printf 'UNKNOWN')"
        pr_state2="$(printf '%s' "$pr_json2" | jq -r '.state' 2>/dev/null || printf 'UNKNOWN')"
      else
        pr_mergeable2="$(printf '%s' "$pr_json2" | sed -n 's/.*"mergeable":\s*"\([^"]*\)".*/\1/p')"
        pr_state2="$(printf '%s' "$pr_json2" | sed -n 's/.*"state":\s*"\([^"]*\)".*/\1/p')"
      fi
      if [ "$pr_state2" != "OPEN" ] && [ -n "$pr_state2" ]; then
        printf 'not-open:%s\n' "$pr_state2" > "$tmpdir/pr.reason"
        exit 1
      fi
      case "$pr_mergeable2" in
        MERGEABLE)
          printf 'mergeable\n' > "$tmpdir/pr.reason"
          exit 0
          ;;
        UNKNOWN|"")
          printf 'unknown-retry\n' > "$tmpdir/pr.reason"
          exit 0
          ;;
        *)
          printf 'not-mergeable:%s\n' "$pr_mergeable2" > "$tmpdir/pr.reason"
          exit 1
          ;;
      esac
      ;;
    *)
      printf 'not-mergeable:%s\n' "$pr_mergeable" > "$tmpdir/pr.reason"
      exit 1
      ;;
  esac
) &
pid_pr=$!

# Wait on each child individually so we can capture per-child exit codes.
set +e
wait "$pid_status"; rc_status=$?
wait "$pid_branch"; rc_branch=$?
wait "$pid_pr";     rc_pr=$?
set -e

# Evaluate in order. First failure wins, matching the pre-refactor SKILL.md
# error-handling precedence.
status_reason=""
[ -f "$tmpdir/status.reason" ] && status_reason="$(cat "$tmpdir/status.reason")"
branch_reason=""
[ -f "$tmpdir/branch.reason" ] && branch_reason="$(cat "$tmpdir/branch.reason")"
pr_reason=""
[ -f "$tmpdir/pr.reason" ] && pr_reason="$(cat "$tmpdir/pr.reason")"

if [ "$rc_status" -ne 0 ]; then
  case "$status_reason" in
    dirty)
      abort "working directory has uncommitted changes"
      ;;
    *)
      reason="$(cat "$tmpdir/status.err" 2>/dev/null || echo "git status failed")"
      abort "$reason"
      ;;
  esac
fi

if [ "$rc_branch" -ne 0 ]; then
  case "$branch_reason" in
    on-main)
      abort "already on main/master; nothing to finalize"
      ;;
    *)
      reason="$(cat "$tmpdir/branch.err" 2>/dev/null || echo "git branch --show-current failed")"
      abort "$reason"
      ;;
  esac
fi

if [ "$rc_pr" -ne 0 ]; then
  case "$pr_reason" in
    no-pr)
      abort "no PR found for current branch"
      ;;
    not-open:*)
      state="${pr_reason#not-open:}"
      abort "PR is not open (state: ${state})"
      ;;
    not-mergeable:*)
      m="${pr_reason#not-mergeable:}"
      abort "PR is not mergeable (${m})"
      ;;
    *)
      abort "preflight: PR check failed"
      ;;
  esac
fi

# All three checks passed. Run the shared build-health gate before
# composing the success JSON. The shared script lives at
# plugins/lwndev-sdlc/scripts/verify-build-health.sh and may be invoked
# from either the cached plugin location (CLAUDE_PLUGIN_ROOT) or the
# in-repo location when this script runs from the marketplace checkout.
PREFLIGHT_DIR="$(cd "$(dirname "$0")" && pwd)"
verify_health=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh" ]; then
  verify_health="${CLAUDE_PLUGIN_ROOT}/scripts/verify-build-health.sh"
elif [ -f "${PREFLIGHT_DIR}/../../../scripts/verify-build-health.sh" ]; then
  verify_health="$(cd "${PREFLIGHT_DIR}/../../../scripts" && pwd)/verify-build-health.sh"
fi

if [ -n "$verify_health" ]; then
  echo "[info] preflight: running verify-build-health.sh --no-interactive ..." >&2
  if ! bash "$verify_health" --no-interactive; then
    abort "build-health check failed (lint / format:check / test / build)"
  fi
else
  abort "build-health gate unavailable: verify-build-health.sh not found at \${CLAUDE_PLUGIN_ROOT:-(unset)}/scripts/ or relative fallback ${PREFLIGHT_DIR}/../../../scripts/"
fi

pr_number="$(cat "$tmpdir/pr.number")"
pr_title="$(cat "$tmpdir/pr.title")"
pr_url="$(cat "$tmpdir/pr.url")"

if [ "$pr_reason" = "unknown-retry" ]; then
  echo "[info] PR mergeable state UNKNOWN after retry — proceeding." >&2
fi

emit_ok_json "$pr_number" "$pr_title" "$pr_url"
exit 0
