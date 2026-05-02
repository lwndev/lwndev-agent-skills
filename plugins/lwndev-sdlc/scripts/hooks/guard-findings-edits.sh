#!/usr/bin/env bash
# guard-findings-edits.sh — BUG-015 Hook for findings-decision gate.
#
# Wiring: declared in plugins/lwndev-sdlc/hooks/hooks.json against the
# `PreToolUse` event with matcher `Edit|Write|MultiEdit`. Claude Code invokes
# this hook before every Edit / Write / MultiEdit tool call with a JSON payload
# on stdin containing `tool_input.file_path`.
#
# Behavior (BUG-015 / RC-1, RC-3):
#   * If `.sdlc/workflows/.active` is missing OR no workflow has
#     `gate == findings-decision` set: allow (no gate to guard).
#   * If `tool_input.file_path` does NOT match the regex
#       requirements/(features|chores|bugs)/.+\.md
#     allow (out-of-scope path; no scope creep).
#   * Otherwise require a fresh `.approval-findings-decision-<active-ID>`
#     marker with mtime >= state.gateSetAt. Missing marker, missing
#     `gateSetAt`, or stale marker: deny with the documented systemMessage.
#     Missing `gateSetAt` is treated as "infinitely old" mirroring BUG-014 / AC9
#     (pre-fix workflow state files predating BUG-015 cannot be satisfied by
#     any marker; user must reapprove).
#
# Why this hook exists: BUG-014's Hook B only guards the `Bash` tool, leaving
# `Edit` / `Write` / `MultiEdit` unguarded against direct edits to a
# requirements doc while the orchestrator is paused on findings-decision. The
# orchestrator could "approve" its own findings by editing the requirement
# document inline. This hook closes that bypass.
#
# Output contract (PreToolUse hooks):
#   * On allow: exit 0 with empty stdout (Claude Code defaults to allow).
#   * On deny: exit 0 with stdout containing the documented JSON envelope
#       {"hookSpecificOutput":{"permissionDecision":"deny"}, "systemMessage": "..."}
#     `permissionDecision: "deny"` is the documented denial signal; the
#     systemMessage explains the missing marker and the canonical user input
#     shape required.
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
  deny "Hook (guard-findings-edits): jq not installed. Cannot evaluate Edit/Write/MultiEdit safely. Install jq or disable the hook."
fi

# Read the entire stdin payload.
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  # No payload — let Claude Code allow; the matcher should never have fired.
  allow
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [[ -z "$file_path" ]]; then
  # No file_path — not an Edit/Write/MultiEdit shape we can evaluate. Allow.
  allow
fi

# ---------------------------------------------------------------------------
# Active-workflow lookup. If no active workflow with a findings-decision gate,
# this hook has nothing to do.
# ---------------------------------------------------------------------------

if [[ ! -f "$ACTIVE_FILE" ]]; then
  allow
fi

active_id="$(tr -d '[:space:]' < "$ACTIVE_FILE" 2>/dev/null || true)"
if [[ -z "$active_id" || ! "$active_id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
  # Empty or malformed .active: nothing to guard (no workflow context). Hook B
  # already denies destructive Bash on this path; we don't need to double-deny
  # an Edit that doesn't have a real workflow to associate with.
  allow
fi

state_file=".sdlc/workflows/${active_id}.json"
if [[ ! -f "$state_file" ]]; then
  allow
fi
if ! jq -e . "$state_file" >/dev/null 2>&1; then
  # Corrupt JSON on the active workflow's state file is a fail-secure deny —
  # we cannot tell whether a gate is set, so any Edit on a guarded path is
  # denied until the state file is repaired.
  gate_val=""
  # Drop through to the path-scope check; if path is out of scope we'll allow.
  # If in scope, the gate-presence check below treats empty gate as "no gate"
  # which would allow a guarded Edit. Override that here: corrupt state on a
  # guarded path = deny.
  if [[ "$file_path" =~ requirements/(features|chores|bugs)/.+\.md ]]; then
    deny "Hook (guard-findings-edits): workflow state file ${state_file} is corrupt or unreadable. Denying Edit on guarded path '${file_path}' fail-secure."
  fi
  allow
fi

gate_val="$(jq -r '.gate // empty' "$state_file" 2>/dev/null || true)"
if [[ "$gate_val" != "findings-decision" ]]; then
  # No active findings-decision gate — Edit is unguarded.
  allow
fi

# ---------------------------------------------------------------------------
# Path-scope check. Only Edits to requirements/{features,chores,bugs}/*.md are
# gated. Any other path passes through.
# ---------------------------------------------------------------------------

if ! [[ "$file_path" =~ requirements/(features|chores|bugs)/.+\.md ]]; then
  allow
fi

# ---------------------------------------------------------------------------
# Marker-freshness check. Mirror guard-state-transitions.sh's helpers verbatim
# so BSD/GNU stat ordering matches and ISO-8601 parsing handles both date(1)
# dialects.
# ---------------------------------------------------------------------------

# marker_mtime_epoch <path> -> epoch seconds, or empty if missing.
marker_mtime_epoch() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo ""
    return
  fi
  # GNU stat (`-c %Y`) first; on Linux, BSD-style `-f %m` means
  # `--file-system` mountpoint and silently returns non-numeric garbage,
  # breaking the arithmetic compare and fail-opening the stale-marker check.
  if stat -c %Y "$path" 2>/dev/null; then
    return
  fi
  stat -f %m "$path" 2>/dev/null || echo ""
}

# iso_to_epoch <iso8601> -> epoch seconds (UTC), or empty if unparsable.
# Always interprets the input as UTC (the trailing 'Z' in our ISO format
# indicates UTC, but BSD `date -j -f` ignores that suffix and defaults to
# the local zone — `TZ=UTC` forces correct interpretation).
iso_to_epoch() {
  local iso="$1"
  if [[ -z "$iso" ]]; then
    echo ""
    return
  fi
  # GNU date supports -d and respects the trailing Z natively.
  if date -d "$iso" -u +%s 2>/dev/null; then
    return
  fi
  # BSD/macOS date: force UTC interpretation via env TZ.
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo ""
}

marker_path="${APPROVALS_DIR}/.approval-findings-decision-${active_id}"
marker_epoch="$(marker_mtime_epoch "$marker_path")"

if [[ -z "$marker_epoch" ]]; then
  deny "Hook (guard-findings-edits): missing approval marker for findings-decision gate on workflow ${active_id}. Edit/Write/MultiEdit of '${file_path}' is denied. User must type: approve findings-decision ${active_id}"
fi

gate_set_at="$(jq -r '.gateSetAt // empty' "$state_file" 2>/dev/null || true)"
if [[ -z "$gate_set_at" ]]; then
  # Pre-fix state file (no gateSetAt). Per BUG-014 / AC9 precedent, treat as
  # infinitely old — no marker can satisfy. User must reapprove fresh.
  deny "Hook (guard-findings-edits): workflow ${active_id} state file predates the gateSetAt fix; no marker can satisfy. User must type: approve findings-decision ${active_id}"
fi

gate_epoch="$(iso_to_epoch "$gate_set_at")"
if [[ -z "$gate_epoch" ]]; then
  deny "Hook (guard-findings-edits): cannot parse gateSetAt='${gate_set_at}' on workflow ${active_id}. Denying Edit fail-secure."
fi

if (( marker_epoch < gate_epoch )); then
  deny "Hook (guard-findings-edits): stale approval marker for findings-decision gate on ${active_id} (marker mtime ${marker_epoch} < gateSetAt ${gate_epoch}). User must type: approve findings-decision ${active_id}"
fi

allow
