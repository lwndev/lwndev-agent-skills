#!/usr/bin/env bash
# guard-state-transitions.sh — BUG-014 Hook B.
#
# Wiring: declared in plugins/lwndev-sdlc/hooks/hooks.json against the
# `PreToolUse` event with matcher `Bash`. Claude Code invokes this hook
# before every Bash tool call with a JSON payload on stdin containing
# `tool_input.command`.
#
# Behavior (BUG-014 / AC4, AC5, AC6):
#   * If command matches `workflow-state.sh resume <ID>`, require a fresh
#     `.approval-<pauseReason>-<ID>` marker (mtime >= state.pausedAt). Missing
#     `pausedAt` -> infinitely old, no marker can satisfy.
#   * If command matches `workflow-state.sh clear-gate <ID>`, require an
#     `.approval-<gate>-<ID>` marker (any mtime — the gate has no equivalent
#     of `pausedAt`).
#   * If command matches one of the destructive prefix-globs:
#       gh pr merge*
#       git push --force*
#       git push -f*
#       git reset --hard*
#       gh release create*
#       npm publish*
#       git tag -d*
#       git push origin :refs/tags/*
#     require a `.approval-merge-approval-<active-ID>` marker. The active
#     workflow ID is read from `.sdlc/workflows/.active`.
#   * Fail-secure: missing jq, missing workflow JSON, corrupt JSON, missing
#     `.active` (when destructive Bash without prior merge approval) all
#     DENY with a clear systemMessage.
#
# Output contract (PreToolUse hooks):
#   * On allow: exit 0 with empty stdout (Claude Code defaults to allow).
#   * On deny: exit 0 with stdout containing the documented JSON envelope
#       {"hookSpecificOutput":{"permissionDecision":"deny"}, "systemMessage": "..."}
#     `permissionDecision: "deny"` is the documented denial signal; the
#     systemMessage explains the missing marker and the canonical user input
#     shape required.
#
# Out-of-scope destructive patterns (deliberately not blocked here; defense
# is provided by Hook D managed-settings or by being a non-destructive
# operation on a feature branch):
#   - rm -rf  (general filesystem; too broad to gate at this layer)
#   - dropdb, mongo --eval, etc. (project-specific; not in initial set)
#   - git push (without --force / -f); regular pushes are part of normal
#     workflow and are not gated.
#
# Dependencies: jq (required for payload parse and state read; missing -> deny).
#
# Exit codes:
#   0  always (denial signaled via JSON output, not exit code).

set -uo pipefail

APPROVALS_DIR=".sdlc/approvals"
ACTIVE_FILE=".sdlc/workflows/.active"

# Helper: emit a deny envelope and exit 0.
deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      permissionDecision: "deny"
    },
    systemMessage: $reason
  }' 2>/dev/null || printf '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"%s"}\n' "$reason"
  exit 0
}

# Helper: emit allow (default) and exit 0.
allow() {
  exit 0
}

# jq missing -> deny (fail-secure).
if ! command -v jq >/dev/null 2>&1; then
  deny "Hook B (guard-state-transitions): jq not installed. Cannot evaluate command safely. Install jq or disable the hook."
fi

# Read the entire stdin payload.
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  # No payload — let Claude Code allow; the matcher should never have fired.
  allow
fi

command_text="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [[ -z "$command_text" ]]; then
  # Not a Bash tool call (or no command) — allow.
  allow
fi

# ---------------------------------------------------------------------------
# Helpers for marker lookup.
# ---------------------------------------------------------------------------

# marker_mtime_epoch <path> -> epoch seconds, or empty if missing.
marker_mtime_epoch() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo ""
    return
  fi
  # macOS uses `stat -f %m`; GNU uses `stat -c %Y`.
  if stat -f %m "$path" 2>/dev/null; then
    return
  fi
  stat -c %Y "$path" 2>/dev/null || echo ""
}

# iso_to_epoch <iso8601> -> epoch seconds, or empty if unparsable.
iso_to_epoch() {
  local iso="$1"
  if [[ -z "$iso" ]]; then
    echo ""
    return
  fi
  # GNU date supports -d; macOS BSD date needs -j -f.
  if date -d "$iso" +%s 2>/dev/null; then
    return
  fi
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo ""
}

# state_field <id> <jq-expr> -> value or empty
state_field() {
  local id="$1"
  local expr="$2"
  local file=".sdlc/workflows/${id}.json"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  jq -r "${expr} // empty" "$file" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Pattern: workflow-state.sh resume <ID>
# Requires a `.approval-<pauseReason>-<ID>` marker with mtime >= pausedAt.
# ---------------------------------------------------------------------------
if [[ "$command_text" =~ workflow-state\.sh[[:space:]]+resume[[:space:]]+((FEAT|CHORE|BUG)-[0-9]+) ]]; then
  id="${BASH_REMATCH[1]}"
  state_file=".sdlc/workflows/${id}.json"
  if [[ ! -f "$state_file" ]]; then
    deny "Hook B: workflow state file ${state_file} not found. Cannot verify resume authorization."
  fi
  if ! jq -e . "$state_file" >/dev/null 2>&1; then
    deny "Hook B: workflow state file ${state_file} is corrupt or unreadable. Denying resume fail-secure."
  fi

  pause_reason="$(state_field "$id" '.pauseReason')"
  if [[ -z "$pause_reason" ]]; then
    # No active pauseReason: defensive deny — resume should only happen after a
    # pause. (If this proves over-restrictive in practice it can be relaxed,
    # but per AC4 the safer default is deny.)
    deny "Hook B: workflow ${id} has no active pauseReason. Cannot resume — there is nothing to resume from."
  fi

  paused_at="$(state_field "$id" '.pausedAt')"
  marker_path="${APPROVALS_DIR}/.approval-${pause_reason}-${id}"
  marker_epoch="$(marker_mtime_epoch "$marker_path")"

  if [[ -z "$marker_epoch" ]]; then
    deny "Hook B: missing approval marker for resume of ${id} (pauseReason=${pause_reason}). User must type: approve ${pause_reason} ${id}"
  fi

  if [[ -z "$paused_at" ]]; then
    # Pre-fix workflow state file (no pausedAt). Per AC9, treat as infinitely
    # old — no marker can satisfy. User must approve fresh.
    deny "Hook B: workflow ${id} state file predates the pausedAt fix; no marker can satisfy. User must type: approve ${pause_reason} ${id}"
  fi

  paused_epoch="$(iso_to_epoch "$paused_at")"
  if [[ -z "$paused_epoch" ]]; then
    deny "Hook B: cannot parse pausedAt='${paused_at}' on workflow ${id}. Denying resume fail-secure."
  fi

  if (( marker_epoch < paused_epoch )); then
    deny "Hook B: stale approval marker for resume of ${id} (marker mtime ${marker_epoch} < pausedAt ${paused_epoch}). User must type: approve ${pause_reason} ${id}"
  fi

  allow
fi

# ---------------------------------------------------------------------------
# Pattern: workflow-state.sh clear-gate <ID>
# Requires `.approval-<gate>-<ID>` marker (no timestamp comparison — gates
# don't expose pausedAt-equivalent; the marker presence alone is the gate).
# ---------------------------------------------------------------------------
if [[ "$command_text" =~ workflow-state\.sh[[:space:]]+clear-gate[[:space:]]+((FEAT|CHORE|BUG)-[0-9]+) ]]; then
  id="${BASH_REMATCH[1]}"
  state_file=".sdlc/workflows/${id}.json"
  if [[ ! -f "$state_file" ]]; then
    deny "Hook B: workflow state file ${state_file} not found. Cannot verify clear-gate authorization."
  fi
  if ! jq -e . "$state_file" >/dev/null 2>&1; then
    deny "Hook B: workflow state file ${state_file} is corrupt or unreadable. Denying clear-gate fail-secure."
  fi

  gate_val="$(state_field "$id" '.gate')"
  if [[ -z "$gate_val" ]]; then
    # No active gate — clear-gate is a no-op anyway, but per fail-secure deny
    # rather than allow a probe that would clear nothing.
    deny "Hook B: workflow ${id} has no active gate. Nothing to clear."
  fi

  marker_path="${APPROVALS_DIR}/.approval-${gate_val}-${id}"
  if [[ ! -f "$marker_path" ]]; then
    deny "Hook B: missing approval marker for clear-gate on ${id} (gate=${gate_val}). User must type: approve ${gate_val} ${id}"
  fi

  allow
fi

# ---------------------------------------------------------------------------
# Pattern: destructive Bash (prefix-glob set per AC6).
# Requires `.approval-merge-approval-<active-ID>` marker. Active workflow ID
# is read from .sdlc/workflows/.active.
# ---------------------------------------------------------------------------

# Strip leading whitespace for prefix matching.
trimmed_command="${command_text#"${command_text%%[![:space:]]*}"}"

is_destructive=""
case "$trimmed_command" in
  "gh pr merge "*|"gh pr merge")              is_destructive="gh pr merge" ;;
  "git push --force "*|"git push --force")    is_destructive="git push --force" ;;
  "git push -f "*|"git push -f")              is_destructive="git push -f" ;;
  "git reset --hard "*|"git reset --hard")    is_destructive="git reset --hard" ;;
  "gh release create "*|"gh release create")  is_destructive="gh release create" ;;
  "npm publish "*|"npm publish")              is_destructive="npm publish" ;;
  "git tag -d "*|"git tag -d")                is_destructive="git tag -d" ;;
  "git push origin :refs/tags/"*)             is_destructive="git push origin :refs/tags/" ;;
esac

if [[ -n "$is_destructive" ]]; then
  if [[ ! -f "$ACTIVE_FILE" ]]; then
    deny "Hook B: destructive command '${is_destructive}...' attempted with no active workflow (.sdlc/workflows/.active missing). User must type: merge <ID>"
  fi
  active_id="$(tr -d '[:space:]' < "$ACTIVE_FILE" 2>/dev/null || true)"
  if [[ -z "$active_id" ]]; then
    deny "Hook B: destructive command '${is_destructive}...' attempted but .active is empty. User must type: merge <ID>"
  fi
  if [[ ! "$active_id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
    deny "Hook B: destructive command '${is_destructive}...' but .active contains malformed ID '${active_id}'. Denying fail-secure."
  fi
  marker_path="${APPROVALS_DIR}/.approval-merge-approval-${active_id}"
  if [[ ! -f "$marker_path" ]]; then
    deny "Hook B: missing merge-approval marker for destructive command '${is_destructive}...' on workflow ${active_id}. User must type: merge ${active_id}"
  fi
  allow
fi

# Default: command does not match any guarded pattern -> allow.
allow
