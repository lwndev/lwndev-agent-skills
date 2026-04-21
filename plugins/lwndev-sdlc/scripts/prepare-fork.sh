#!/usr/bin/env bash
# prepare-fork.sh — Run the FEAT-014 pre-fork ceremony (FEAT-021 / FR-1, FR-2).
#
# Composes the four pre-fork steps currently described as prose in
# orchestrating-workflows/SKILL.md into a single script invocation:
#   1. SKILL.md readability check for the sub-skill.
#   2. Tier resolution via `workflow-state.sh resolve-tier`.
#   3. Audit-trail write via `workflow-state.sh record-model-selection`
#      (NFR-1 ordering invariant: happens BEFORE Step 4 so that a Step 4
#      failure still leaves a visible audit entry).
#   4. FR-14 console echo line emitted to stderr (baseline-locked, non-locked,
#      or Edge Case 11 hard-override-below-baseline variant).
#   5. Print the resolved tier on stdout as the script's only stdout output.
#
# Usage:
#   prepare-fork.sh <ID> <stepIndex> <skill-name> [--mode <mode>] [--phase <phase>]
#                   [--cli-model <tier>] [--cli-complexity <tier>]
#                   [--cli-model-for <step:tier>]...
#
# Exit codes:
#   0  success (tier printed to stdout, echo line to stderr)
#   1+ propagated from a child workflow-state.sh subcommand
#   2  argument-validation failure
#   3  SKILL.md cannot be read at the resolved path
#   4  jq missing or state-file unreadable for complexity-stage read
#
# Bash 3.2 compatible (NFR-4): no associative arrays, no `mapfile`, no `&>>`.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: prepare-fork.sh <ID> <stepIndex> <skill-name> [--mode <mode>] [--phase <phase>]
                       [--cli-model <tier>] [--cli-complexity <tier>]
                       [--cli-model-for <step:tier>]...

Positional arguments (all three required):
  <ID>           Work-item ID (FEAT-NNN, CHORE-NNN, or BUG-NNN). Must correspond
                 to an existing .sdlc/workflows/<ID>.json state file.
  <stepIndex>    Zero-based index of the step in the chain's `steps` array.
                 Must be a non-negative integer.
  <skill-name>   Canonical fork step-name. Must be one of:
                   reviewing-requirements
                   creating-implementation-plans
                   implementing-plan-phases
                   executing-chores
                   executing-bug-fixes
                   finalizing-workflow
                   pr-creation

Optional flags (may appear before or after positional args):
  --mode <mode>             Mode passed to record-model-selection. Only valid
                            when <skill-name> is reviewing-requirements.
  --phase <phase>           Phase passed to record-model-selection. Only valid
                            when <skill-name> is implementing-plan-phases.
  --cli-model <tier>        Forwarded to resolve-tier --cli-model.
  --cli-complexity <tier>   Forwarded to resolve-tier --cli-complexity.
  --cli-model-for <step:tier>
                            Forwarded to resolve-tier --cli-model-for; may be
                            repeated.
  --help, -h                Print this usage message to stdout and exit 0.

Example:
  prepare-fork.sh FEAT-021 2 reviewing-requirements --mode standard

Exit codes:
  0  success
  1+ propagated child exit (resolve-tier / record-model-selection / step-baseline)
  2  argument-validation failure
  3  SKILL.md cannot be read
  4  jq missing or state-file unreadable
USAGE
}

# --- Step 0a: --help / -h pre-scan --------------------------------------------
# Help takes precedence over every other validation — any occurrence of --help
# or -h anywhere in argv wins before positional-arg or flag-value parsing.
for _arg in "$@"; do
  case "$_arg" in
    --help|-h)
      usage
      exit 0
      ;;
  esac
done

# --- Step 0b: jq availability -------------------------------------------------
# jq is required for Steps 3 and 4. Checking up front gives a deterministic
# exit 4 before any side effect is written.
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: cannot read complexityStage from state file — is jq installed?" >&2
  exit 4
fi

# --- Step 1: argument parsing -------------------------------------------------
ID=""
step_index=""
skill=""
mode=""            # empty when --mode absent; "null" string at call time
phase=""           # empty when --phase absent; "null" string at call time
cli_model=""
cli_complexity=""
# Indexed array for repeated --cli-model-for (Bash 3.2 compatible).
cli_model_for_flags=()
positional_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 ]]; then
        echo "Error: --mode requires a value" >&2
        exit 2
      fi
      mode="$2"
      shift 2
      ;;
    --phase)
      if [[ $# -lt 2 ]]; then
        echo "Error: --phase requires a value" >&2
        exit 2
      fi
      phase="$2"
      shift 2
      ;;
    --cli-model)
      if [[ $# -lt 2 ]]; then
        echo "Error: --cli-model requires a value" >&2
        exit 2
      fi
      cli_model="$2"
      shift 2
      ;;
    --cli-complexity)
      if [[ $# -lt 2 ]]; then
        echo "Error: --cli-complexity requires a value" >&2
        exit 2
      fi
      cli_complexity="$2"
      shift 2
      ;;
    --cli-model-for)
      if [[ $# -lt 2 ]]; then
        echo "Error: --cli-model-for requires a value" >&2
        exit 2
      fi
      cli_model_for_flags+=("--cli-model-for")
      cli_model_for_flags+=("$2")
      shift 2
      ;;
    --*)
      echo "Error: unknown flag '$1'. See prepare-fork.sh --help" >&2
      exit 2
      ;;
    *)
      case "$positional_count" in
        0) ID="$1" ;;
        1) step_index="$1" ;;
        2) skill="$1" ;;
        *)
          echo "Error: unexpected positional argument '$1'. See prepare-fork.sh --help" >&2
          exit 2
          ;;
      esac
      positional_count=$((positional_count + 1))
      shift
      ;;
  esac
done

if [[ "$positional_count" -ne 3 ]]; then
  echo "Error: prepare-fork.sh requires three positional arguments: <ID> <stepIndex> <skill-name>. See prepare-fork.sh --help" >&2
  exit 2
fi

# --- Step 1a: positional validation ------------------------------------------
if ! [[ "$step_index" =~ ^[0-9]+$ ]]; then
  echo "Error: <stepIndex> must be a non-negative integer; got '${step_index}'" >&2
  exit 2
fi

VALID_SKILLS="reviewing-requirements creating-implementation-plans implementing-plan-phases executing-chores executing-bug-fixes finalizing-workflow pr-creation"
skill_valid="false"
for _valid in $VALID_SKILLS; do
  if [[ "$skill" == "$_valid" ]]; then
    skill_valid="true"
    break
  fi
done
if [[ "$skill_valid" != "true" ]]; then
  echo "Error: unknown skill-name '${skill}'. Must be one of: reviewing-requirements, creating-implementation-plans, implementing-plan-phases, executing-chores, executing-bug-fixes, finalizing-workflow, pr-creation" >&2
  exit 2
fi

# --- Step 1b: flag cross-validation ------------------------------------------
if [[ -n "$mode" && -n "$phase" ]]; then
  echo "Error: --mode and --phase are mutually exclusive" >&2
  exit 2
fi
if [[ -n "$mode" && "$skill" != "reviewing-requirements" ]]; then
  echo "Error: --mode is only valid for reviewing-requirements; got skill '${skill}'" >&2
  exit 2
fi
if [[ -n "$phase" && "$skill" != "implementing-plan-phases" ]]; then
  echo "Error: --phase is only valid for implementing-plan-phases; got skill '${skill}'" >&2
  exit 2
fi

# --- Step 1c: resolve CLAUDE_PLUGIN_ROOT / CLAUDE_SKILL_DIR ------------------
# Env vars win when set and non-empty; otherwise derive from script location.
# prepare-fork.sh lives at ${CLAUDE_PLUGIN_ROOT}/scripts/prepare-fork.sh.
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [[ -z "${CLAUDE_SKILL_DIR:-}" ]]; then
  CLAUDE_SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/orchestrating-workflows"
fi

# --- Step 1d: state file must exist ------------------------------------------
state_file_path=".sdlc/workflows/${ID}.json"
if [[ ! -f "$state_file_path" ]]; then
  echo "Error: workflow state file ${state_file_path} not found" >&2
  exit 2
fi

# --- Step 1 (FR-2): SKILL.md readability check -------------------------------
# pr-creation is an inline orchestrator operation, not a forked skill — it has
# no skills/ directory. The name is reserved in the Fork Step-Name Map purely
# so baseline resolution (FEAT-014) can lock it to the haiku tier. Skip the
# readability check for this one canonical exception.
if [[ "$skill" != "pr-creation" ]]; then
  skill_md_path="${CLAUDE_PLUGIN_ROOT}/skills/${skill}/SKILL.md"
  if [[ ! -r "$skill_md_path" ]]; then
    echo "Error: SKILL.md for '${skill}' cannot be read at ${skill_md_path}" >&2
    exit 3
  fi
fi

workflow_state_sh="${CLAUDE_SKILL_DIR}/scripts/workflow-state.sh"

# --- Step 2 (FR-2): resolve the tier ------------------------------------------
# Forward optional flags; use the `${var:+--flag "$var"}` pattern for scalars
# and the array expansion guarded against empty with a length check so that
# `set -u` doesn't trip on Bash 3.2. The child's stderr is inherited from this
# process (fd 2 → our stderr), so any error message is propagated verbatim.
tier=""
set +e
if [[ ${#cli_model_for_flags[@]} -eq 0 ]]; then
  tier=$(
    "$workflow_state_sh" resolve-tier "$ID" "$skill" \
      ${cli_model:+--cli-model "$cli_model"} \
      ${cli_complexity:+--cli-complexity "$cli_complexity"}
  )
else
  tier=$(
    "$workflow_state_sh" resolve-tier "$ID" "$skill" \
      ${cli_model:+--cli-model "$cli_model"} \
      ${cli_complexity:+--cli-complexity "$cli_complexity"} \
      "${cli_model_for_flags[@]}"
  )
fi
resolve_rc=$?
set -e
if [[ "$resolve_rc" -ne 0 ]]; then
  exit "$resolve_rc"
fi

# --- Step 3 (FR-2): record the audit-trail entry -----------------------------
# Read complexityStage from the state file. jq failure → exit 4.
stage=$(jq -r '.complexityStage // "init"' "$state_file_path" 2>/dev/null) || {
  echo "Error: cannot read complexityStage from state file — is jq installed?" >&2
  exit 4
}
if [[ -z "$stage" ]]; then
  stage="init"
fi

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# record-model-selection treats the literal "null" string as JSON null for
# mode and phase.
mode_arg="$mode"
phase_arg="$phase"
[[ -z "$mode_arg" ]] && mode_arg="null"
[[ -z "$phase_arg" ]] && phase_arg="null"

# Suppress record-model-selection's jq-dump of the state file on stdout; it
# pollutes our tier-only stdout contract. Its stderr still propagates.
set +e
"$workflow_state_sh" record-model-selection \
  "$ID" "$step_index" "$skill" "$mode_arg" "$phase_arg" "$tier" "$stage" "$started_at" \
  >/dev/null
record_rc=$?
set -e
if [[ "$record_rc" -ne 0 ]]; then
  exit "$record_rc"
fi

# --- Step 4 (FR-2): emit the FR-14 console echo line -------------------------
# Ordering invariant: this step runs AFTER Step 3 so that a Step 4 failure
# still leaves the audit-trail entry in the state file (NFR-1).
set +e
baseline=$("$workflow_state_sh" step-baseline "$skill")
baseline_rc=$?
set -e
if [[ "$baseline_rc" -ne 0 ]]; then
  exit "$baseline_rc"
fi

set +e
locked=$("$workflow_state_sh" step-baseline-locked "$skill")
locked_rc=$?
set -e
if [[ "$locked_rc" -ne 0 ]]; then
  exit "$locked_rc"
fi

wi_complexity=$(jq -r '.complexity // "medium"' "$state_file_path" 2>/dev/null || echo "medium")
[[ -z "$wi_complexity" ]] && wi_complexity="medium"

state_override=$(jq -r '.modelOverride // empty' "$state_file_path" 2>/dev/null || echo "")

# Determine the override token using FR-14 precedence:
#   per-step CLI > blanket CLI > CLI complexity > state override > "none".
override_token="none"
override_flag_name=""     # Used only for the Edge Case 11 warning.
# Per-step: walk cli_model_for_flags pairwise looking for a match on $skill.
per_step_tier=""
_i=0
if [[ ${#cli_model_for_flags[@]} -gt 0 ]]; then
  _total=${#cli_model_for_flags[@]}
  while [[ $_i -lt $_total ]]; do
    # Flag at index $_i (always "--cli-model-for"), value at $_i + 1.
    _val_idx=$((_i + 1))
    if [[ $_val_idx -lt $_total ]]; then
      _val="${cli_model_for_flags[$_val_idx]}"
      _step="${_val%%:*}"
      _tier="${_val##*:}"
      if [[ "$_step" == "$skill" ]]; then
        per_step_tier="$_tier"
      fi
    fi
    _i=$((_i + 2))
  done
fi

if [[ -n "$per_step_tier" ]]; then
  override_token="cli-model-for:${per_step_tier}"
  override_flag_name="--model"
elif [[ -n "$cli_model" ]]; then
  override_token="cli-model:${cli_model}"
  override_flag_name="--model"
elif [[ -n "$cli_complexity" ]]; then
  override_token="cli-complexity:${cli_complexity}"
  # cli-complexity is a soft override — no Edge Case 11 warning path.
  override_flag_name=""
elif [[ -n "$state_override" ]]; then
  override_token="state-override:${state_override}"
  override_flag_name=""
fi

# Mode-or-phase slot (parenthetical): "mode=X", "phase=N", or empty.
slot=""
if [[ -n "$mode" ]]; then
  slot=", mode=${mode}"
elif [[ -n "$phase" ]]; then
  slot=", phase=${phase}"
fi

# Emit the echo line.
if [[ "$locked" == "true" ]]; then
  echo "[model] step ${step_index} (${skill}) → ${tier} (baseline=${baseline}, baseline-locked)" >&2
else
  echo "[model] step ${step_index} (${skill}${slot}) → ${tier} (baseline=${baseline}, wi-complexity=${wi_complexity}, override=${override_token})" >&2
fi

# Edge Case 11: hard-override-below-baseline downgrade warning.
# Ordering: haiku=0 < sonnet=1 < opus=2.
tier_ord() {
  case "$1" in
    haiku) echo 0 ;;
    sonnet) echo 1 ;;
    opus) echo 2 ;;
    *) echo 1 ;;
  esac
}
if [[ -n "$override_flag_name" ]]; then
  tier_ordinal=$(tier_ord "$tier")
  baseline_ordinal=$(tier_ord "$baseline")
  if [[ "$tier_ordinal" -lt "$baseline_ordinal" ]]; then
    echo "[model] Hard override ${override_flag_name} ${tier} bypassed baseline ${baseline} for ${skill}. Proceeding at user request." >&2
  fi
fi

# --- Step 5 (FR-2): print the resolved tier on stdout -------------------------
printf '%s\n' "$tier"
exit 0
