#!/usr/bin/env bash
# record-approval.sh — BUG-014 Hook A.
#
# Wiring: declared in plugins/lwndev-sdlc/hooks/hooks.json against the
# `UserPromptSubmit` event. Claude Code invokes this script with the
# UserPromptSubmit JSON payload on stdin every time the user submits a real
# prompt. Auto-mode self-prompts produced by the agent are NOT
# UserPromptSubmit events, so this hook never fires for them — the absence of
# a marker is exactly what Hook B (`guard-state-transitions.sh`) and Hook C
# (`guard-agent-prompts.sh`) read as "no user authorization given".
#
# Behavior (BUG-014 / AC2, AC3):
#   * Parse the user prompt for canonical approval shapes:
#       approve <gate-type> <ID>
#       proceed <ID>
#       yes <ID>
#       merge <ID>
#       pause <ID>
#   * For each match, write an approval marker file:
#       .sdlc/approvals/.approval-<marker-name>-<ID>
#     containing: ISO-8601 timestamp, workflow ID, verbatim user message.
#   * Unknown shapes are silently ignored (no marker, no error, exit 0).
#
# Marker-name resolution:
#   * `approve <gate-type> <ID>`  -> .approval-<gate-type>-<ID>     (e.g. plan-approval, pr-review, findings-decision, review-findings)
#   * `proceed <ID>` / `yes <ID>` -> resolved against active gate state for the
#                                   workflow if a state file exists; otherwise
#                                   written as `.approval-proceed-<ID>` so the
#                                   user can approve out of band.
#   * `merge <ID>`                -> .approval-merge-approval-<ID>  (Hook B's
#                                   destructive-Bash gate name).
#   * `pause <ID>`                -> .approval-pause-<ID>            (explicit
#                                   decline marker; future use).
#
# Output contract (UserPromptSubmit hooks):
#   * stdout: empty (this hook is purely a side effect; the prompt continues
#     to Claude unchanged).
#   * exit 0 always — a hook failure must not block the user from typing.
#
# Dependencies: jq (required), bash 3.2+. No `mapfile`, no associative arrays.
#
# Exit codes:
#   0  always (silent skip on jq missing, malformed payload, write failure —
#      Hook B is the fail-secure guard, Hook A is best-effort marker writing).

set -uo pipefail

# Resolve repo root (cwd at hook fire time is the user's project root per
# Claude Code hook semantics — the payload also carries `cwd`, but we use
# the runtime cwd to keep the implementation straightforward).
APPROVALS_DIR=".sdlc/approvals"

# jq missing -> exit 0 silently. Hook B will deny anyway.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Read the entire stdin payload (UserPromptSubmit JSON).
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

# Extract the prompt text. UserPromptSubmit payloads carry the user message
# under `prompt` per the Claude Code hooks schema; older revisions sometimes
# used `user_prompt`. Fall through gracefully.
prompt_text="$(printf '%s' "$payload" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || true)"
if [[ -z "$prompt_text" ]]; then
  exit 0
fi

# Helper: ISO-8601 UTC timestamp matching workflow-state.sh `now_iso`.
now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Helper: write a marker file. Atomic via mktemp+mv. Silent on failure.
write_marker() {
  local marker_name="$1"
  local id="$2"
  mkdir -p "$APPROVALS_DIR" 2>/dev/null || return 0
  local marker_path="${APPROVALS_DIR}/.approval-${marker_name}-${id}"
  local tmp
  tmp="$(mktemp "${APPROVALS_DIR}/.approval.XXXXXX" 2>/dev/null)" || return 0
  {
    printf 'timestamp: %s\n' "$(now_iso)"
    printf 'workflow_id: %s\n' "$id"
    printf 'message: %s\n' "$prompt_text"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  mv -f "$tmp" "$marker_path" 2>/dev/null || rm -f "$tmp"
}

# Canonical workflow ID shape: FEAT-N, CHORE-N, BUG-N (uppercase, no leading
# zeros enforced — workflow-state.sh's regex accepts any digit string).
ID_RE='(FEAT|CHORE|BUG)-[0-9]+'

# Iterate the prompt line-by-line so multi-line prompts can carry multiple
# approvals (e.g. "approve plan-approval BUG-014\napprove pr-review BUG-014").
# Use a per-line regex match; ignore everything else.
#
# Matching is case-insensitive on the keyword (per QA P1 input scenario:
# "APPROVE PLAN-APPROVAL BUG-014" must match), case-preserving on the ID
# (uppercase by convention; the regex enforces uppercase).
shopt -s nocasematch || true

while IFS= read -r line; do
  # 1. approve <gate-type> <ID>
  if [[ "$line" =~ (^|[[:space:]])approve[[:space:]]+([A-Za-z][A-Za-z0-9-]*)[[:space:]]+(${ID_RE})([[:space:]]|$) ]]; then
    gate="${BASH_REMATCH[2]}"
    id="${BASH_REMATCH[3]}"
    # Lowercase the gate name (gate names are lowercase by convention).
    gate_lc="$(printf '%s' "$gate" | tr '[:upper:]' '[:lower:]')"
    write_marker "$gate_lc" "$id"
    continue
  fi

  # 2. merge <ID>  -> .approval-merge-approval-<ID>
  if [[ "$line" =~ (^|[[:space:]])merge[[:space:]]+(${ID_RE})([[:space:]]|$) ]]; then
    id="${BASH_REMATCH[2]}"
    write_marker "merge-approval" "$id"
    continue
  fi

  # 3. pause <ID>  -> .approval-pause-<ID> (explicit decline)
  if [[ "$line" =~ (^|[[:space:]])pause[[:space:]]+(${ID_RE})([[:space:]]|$) ]]; then
    id="${BASH_REMATCH[2]}"
    write_marker "pause" "$id"
    continue
  fi

  # 4. proceed <ID> / yes <ID>  -> resolve against active gate/pauseReason
  #    Falls back to a generic `.approval-proceed-<ID>` marker when the state
  #    file is missing so out-of-band approvals still produce evidence.
  if [[ "$line" =~ (^|[[:space:]])(proceed|yes)[[:space:]]+(${ID_RE})([[:space:]]|$) ]]; then
    id="${BASH_REMATCH[3]}"
    state_file=".sdlc/workflows/${id}.json"
    marker_resolved=""
    if [[ -f "$state_file" ]]; then
      # Precedence: active `gate` field beats `pauseReason` (per QA P0
      # state-transitions scenario: gate set during a re-fork attempt wins).
      gate_val="$(jq -r '.gate // empty' "$state_file" 2>/dev/null || true)"
      pause_reason="$(jq -r '.pauseReason // empty' "$state_file" 2>/dev/null || true)"
      if [[ -n "$gate_val" ]]; then
        marker_resolved="$gate_val"
      elif [[ -n "$pause_reason" ]]; then
        marker_resolved="$pause_reason"
      fi
    fi
    if [[ -n "$marker_resolved" ]]; then
      write_marker "$marker_resolved" "$id"
    else
      write_marker "proceed" "$id"
    fi
    continue
  fi
done <<< "$prompt_text"

shopt -u nocasematch || true

exit 0
