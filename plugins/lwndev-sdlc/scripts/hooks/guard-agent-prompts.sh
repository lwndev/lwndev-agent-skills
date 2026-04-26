#!/usr/bin/env bash
# guard-agent-prompts.sh — BUG-014 Hook C.
#
# Wiring: declared in plugins/lwndev-sdlc/hooks/hooks.json against the
# `PreToolUse` event with matchers `Task` and `Agent`. (Claude Code's
# subagent-spawning tool is `Task`; the bug spec uses `Agent` as the conceptual
# name. Both matchers are wired so either future name works.) The hook
# inspects `tool_input.prompt` and the target skill name (extracted from the
# prompt's "fork-target" line per the orchestrator's contract).
#
# Behavior (BUG-014 / AC7, AC8):
#   * AC7 — Deny prompts containing carve-out regex set:
#       skip the SKILL\.md.*prompt
#       orchestrator.*has (already )?obtained.*authorization
#       proceed directly to finalize\.sh
#       Skip Step \d+   (whitelist exception: target skill is implementing-plan-phases)
#   * AC8 — Deny forks of confirmation-owning skills (initial set:
#     finalizing-workflow) without `.approval-merge-approval-<active-ID>`.
#   * Prompts not containing carve-outs and not targeting confirmation-owning
#     skills pass through.
#
# Output contract (PreToolUse hooks):
#   * On allow: exit 0 with empty stdout.
#   * On deny: exit 0 with stdout containing
#       {"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage": "..."}
#
# Dependencies: jq (required; missing -> deny).

set -uo pipefail

APPROVALS_DIR=".sdlc/approvals"
ACTIVE_FILE=".sdlc/workflows/.active"

# Helper: emit deny envelope and exit 0.
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
  deny "Hook C (guard-agent-prompts): jq not installed. Cannot evaluate Agent prompt safely. Install jq or disable the hook."
fi

# Read the entire stdin payload.
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  allow
fi

# Extract the prompt text from tool_input.prompt. Subagent spawns route
# through different shapes depending on tool naming:
#   * Task tool: tool_input.prompt is the user-supplied prompt.
#   * Agent tool (legacy): tool_input.prompt or tool_input.input.
prompt_text="$(printf '%s' "$payload" | jq -r '.tool_input.prompt // .tool_input.input // empty' 2>/dev/null || true)"
if [[ -z "$prompt_text" ]]; then
  # No prompt text — not a subagent spawn we can evaluate. Allow.
  allow
fi

# Resolve the target skill once, before either AC7 or AC8 consults it. Real
# orchestrator forks pass the SKILL.md verbatim (per orchestrating-workflows
# references/forked-steps.md) and do NOT set subagent_type on every fork —
# the model decides whether to populate it. The fallback regex therefore has
# to recognize the YAML frontmatter `name:` key in addition to prose-style
# `Skill:` / `fork:` / `target:` references kept for defense in depth.
subagent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"

target_skill="$subagent_type"
if [[ -z "$target_skill" ]]; then
  if [[ "$prompt_text" =~ (^|[[:space:]])name[[:space:]]*:[[:space:]]*([A-Za-z0-9:_/-]+) ]]; then
    target_skill="${BASH_REMATCH[2]}"
  elif [[ "$prompt_text" =~ (^|[[:space:]])(Skill|skill|fork|target)[[:space:]]*[:=][[:space:]]*([A-Za-z0-9:_/-]+) ]]; then
    target_skill="${BASH_REMATCH[3]}"
  fi
fi

# Strip plugin prefix and lowercase explicitly. Lowercasing here decouples
# the case statement below from `nocasematch` shell state — uppercase /
# mixed-case skill names fold to canonical lowercase before matching.
target_skill_norm="$(printf '%s' "${target_skill##*:}" | tr '[:upper:]' '[:lower:]')"

# Confirmation-owning skill set — forks to these skills require a fresh
# `.approval-merge-approval-<active-ID>` marker (AC8). The same set scopes
# AC7's `Skip Step <N>` deny: the carve-out is only dangerous when it
# suppresses a confirmation prompt, and the phrase appears legitimately in
# embedded SKILL.md content for non-gating skills (e.g.
# reviewing-requirements/SKILL.md:261 "Skip Step 4 unless APIs referenced").
case "$target_skill_norm" in
  finalizing-workflow) is_confirmation_owning=1 ;;
  *) is_confirmation_owning=0 ;;
esac

# ---------------------------------------------------------------------------
# AC7: carve-out regex scan.
# ---------------------------------------------------------------------------

shopt -s nocasematch || true

# 1. "skip the SKILL.md ... prompt" — the FEAT-030 reproduction phrase.
if [[ "$prompt_text" =~ skip[[:space:]]+the[[:space:]]+SKILL\.md.*prompt ]]; then
  deny "Hook C: Agent prompt contains the carve-out phrase 'skip the SKILL.md ... prompt' (matches BUG-014 AC7 regex). This phrase was the FEAT-030 reproduction. The orchestrator MUST NOT bypass a sub-skill's confirmation prompt via prompt injection. Remove the carve-out and let the user approve at the prompt."
fi

# 2. "orchestrator ... has [already] obtained ... authorization".
if [[ "$prompt_text" =~ orchestrator.*has[[:space:]]+(already[[:space:]]+)?obtained.*authorization ]]; then
  deny "Hook C: Agent prompt claims the orchestrator 'has obtained authorization' (matches BUG-014 AC7 regex). The orchestrator does not own user authorization; only Hook A markers from real UserPromptSubmit events do. Remove the carve-out."
fi

# 3. "proceed directly to finalize.sh".
if [[ "$prompt_text" =~ proceed[[:space:]]+directly[[:space:]]+to[[:space:]]+finalize\.sh ]]; then
  deny "Hook C: Agent prompt instructs the subagent to 'proceed directly to finalize.sh' (matches BUG-014 AC7 regex). finalize.sh is a destructive call site. Remove the carve-out and require user approval."
fi

# 4. "Skip Step \d+" — scoped deny. implementing-plan-phases is the documented
#    legitimate carve-out (Step 10/12 PR-creation variance). Empty target
#    fails secure. Confirmation-owning targets (the only place the carve-out
#    can suppress a real gate) deny. Other non-gating targets allow — the
#    phrase appears in embedded SKILL.md content where it cannot bypass a
#    confirmation that doesn't exist.
if [[ "$prompt_text" =~ Skip[[:space:]]+Step[[:space:]]+[0-9]+ ]]; then
  case "$target_skill_norm" in
    implementing-plan-phases)
      : # legitimate carve-out — allow.
      ;;
    "")
      deny "Hook C: Agent prompt contains 'Skip Step <N>' carve-out with no resolvable target skill. Denying fail-secure."
      ;;
    *)
      if (( is_confirmation_owning == 1 )); then
        deny "Hook C: Agent prompt contains 'Skip Step <N>' carve-out for confirmation-owning skill '${target_skill_norm}'. The carve-out cannot bypass a confirmation gate. Remove it or fork implementing-plan-phases instead."
      fi
      ;;
  esac
fi

shopt -u nocasematch || true

# ---------------------------------------------------------------------------
# AC8: confirmation-owning-skill scan.
# Initial set: finalizing-workflow (forks to finalize.sh:438 `gh pr merge`).
# ---------------------------------------------------------------------------

if (( is_confirmation_owning == 1 )); then
  if [[ ! -f "$ACTIVE_FILE" ]]; then
    deny "Hook C: spawning '${target_skill_norm}' but no active workflow (.sdlc/workflows/.active missing). User must type: merge <ID>"
  fi
  active_id="$(tr -d '[:space:]' < "$ACTIVE_FILE" 2>/dev/null || true)"
  if [[ -z "$active_id" || ! "$active_id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
    deny "Hook C: spawning '${target_skill_norm}' but .active is empty or malformed. Denying fail-secure."
  fi
  marker_path="${APPROVALS_DIR}/.approval-merge-approval-${active_id}"
  if [[ ! -f "$marker_path" ]]; then
    deny "Hook C: missing merge-approval marker for spawn of '${target_skill_norm}' on workflow ${active_id}. User must type: merge ${active_id}"
  fi
fi

# Default: allow.
allow
