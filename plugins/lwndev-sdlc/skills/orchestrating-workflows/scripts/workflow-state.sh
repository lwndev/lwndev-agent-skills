#!/usr/bin/env bash
set -euo pipefail

# workflow-state.sh — State management for orchestrating-workflows skill
# Manages .sdlc/workflows/{ID}.json state files for SDLC workflow chains.
# Requires: jq, bash-compatible shell

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install via: brew install jq (macOS), apt-get install jq (Debian/Ubuntu), or see https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

WORKFLOWS_DIR=".sdlc/workflows"

usage() {
  echo "Usage: workflow-state.sh <command> <args...>" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  init <ID> <type>              Create state file for a new workflow" >&2
  echo "  status <ID>                   Return current state as JSON" >&2
  echo "  advance <ID> [artifact-path]  Mark current step complete, advance to next" >&2
  echo "  pause <ID> <reason>           Set status to paused" >&2
  echo "  resume <ID>                   Set status to in-progress" >&2
  echo "  fail <ID> <message>           Set status to failed with error" >&2
  echo "  complete <ID>                 Mark workflow as complete" >&2
  echo "  set-pr <ID> <pr-num> <branch> Record PR metadata" >&2
  echo "  populate-phases <ID> <count>  Insert phase steps and post-phase steps" >&2
  echo "  phase-count <ID>              Return number of implementation phases" >&2
  echo "  phase-status <ID>             Return per-phase completion status" >&2
  echo "  set-complexity <ID> <tier>    Set work-item complexity tier (low|medium|high)" >&2
  echo "  get-model <ID> <step-name>    Resolve model tier for a step (baseline + complexity + modelOverride)" >&2
  echo "  record-model-selection <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>" >&2
  echo "                                Append an entry to the modelSelections audit trail" >&2
  exit 1
}

state_file() {
  echo "${WORKFLOWS_DIR}/${1}.json"
}

ensure_dir() {
  mkdir -p "$WORKFLOWS_DIR"
}

validate_id() {
  local id="$1"
  if [[ ! "$id" =~ ^(FEAT|CHORE|BUG)-[0-9]+$ ]]; then
    echo "Error: Invalid ID format '${id}'. Expected FEAT-NNN, CHORE-NNN, or BUG-NNN." >&2
    exit 1
  fi
}

validate_state_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Error: State file not found: ${file}" >&2
    exit 1
  fi
  if ! jq -e '.id and .type and .status and .steps and (.currentStep != null)' "$file" &>/dev/null; then
    echo "Error: State file is malformed or missing required fields (id, type, status, steps, currentStep)." >&2
    echo "Consider deleting ${file} and restarting the workflow." >&2
    exit 1
  fi
  # Defensive migration (FR-13): silently add FEAT-014 fields if missing.
  _migrate_state_file "$file"
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# --- Model selection helpers (FEAT-014) ---

# Map a tier name to a numeric rank for comparison: haiku=1 < sonnet=2 < opus=3.
# Emits empty string for unknown tiers.
_tier_rank() {
  case "$1" in
    haiku) echo 1 ;;
    sonnet) echo 2 ;;
    opus) echo 3 ;;
    *) echo "" ;;
  esac
}

# Compare two tier strings and echo the higher one. If either side is unknown,
# the other is returned. If both are unknown, echoes the first argument.
_max_tier() {
  local a="$1"
  local b="$2"
  local ra rb
  ra=$(_tier_rank "$a")
  rb=$(_tier_rank "$b")
  if [[ -z "$ra" && -z "$rb" ]]; then
    echo "$a"
    return
  fi
  if [[ -z "$ra" ]]; then
    echo "$b"
    return
  fi
  if [[ -z "$rb" ]]; then
    echo "$a"
    return
  fi
  if (( ra >= rb )); then
    echo "$a"
  else
    echo "$b"
  fi
}

# Map a work-item complexity label (low|medium|high) to its associated model tier.
# low → haiku, medium → sonnet, high → opus. Returns empty string for unknown / null.
_complexity_to_tier() {
  case "$1" in
    low) echo "haiku" ;;
    medium) echo "sonnet" ;;
    high) echo "opus" ;;
    *) echo "" ;;
  esac
}

# Step baseline lookup (FEAT-014 Axis 1). Echoes baseline tier for a given step name.
# Unknown step names default to "sonnet" (safe floor).
_step_baseline() {
  case "$1" in
    reviewing-requirements|creating-implementation-plans|implementing-plan-phases|executing-chores|executing-bug-fixes)
      echo "sonnet"
      ;;
    finalizing-workflow|pr-creation)
      echo "haiku"
      ;;
    *)
      echo "sonnet"
      ;;
  esac
}

# Step baseline-lock lookup. Baseline-locked steps ignore work-item complexity upgrades
# and soft overrides. Echoes "true" if locked, "false" otherwise.
_step_baseline_locked() {
  case "$1" in
    finalizing-workflow|pr-creation) echo "true" ;;
    *) echo "false" ;;
  esac
}

# Defensive migration for pre-existing state files missing FEAT-014 fields (FR-13).
# Adds complexity, complexityStage, modelOverride, and modelSelections with their init
# defaults when any of them are missing. Silent except for a single stderr debug line
# the first time a file is actually rewritten.
_migrate_state_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  # Quick check: does the file need migration at all?
  local needs_migration
  needs_migration=$(jq '
    (has("complexity") | not) or
    (has("complexityStage") | not) or
    (has("modelOverride") | not) or
    (has("modelSelections") | not)
  ' "$file" 2>/dev/null || echo "false")

  if [[ "$needs_migration" != "true" ]]; then
    return 0
  fi

  echo "[workflow-state] debug: migrating ${file} to add FEAT-014 model-selection fields" >&2

  jq '
    (if has("complexity") | not then .complexity = null else . end)
    | (if has("complexityStage") | not then .complexityStage = "init" else . end)
    | (if has("modelOverride") | not then .modelOverride = null else . end)
    | (if has("modelSelections") | not then .modelSelections = [] else . end)
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Generate the feature chain step sequence (FR-1)
# Steps 1-6 are fixed, then phase steps are added dynamically later
generate_feature_steps() {
  cat <<'STEPS'
[
  {"name":"Document feature requirements","skill":"documenting-features","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Create implementation plan","skill":"creating-implementation-plans","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Plan approval","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile test plan","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Generate the chore chain step sequence (FR-1)
# Fixed 9-step sequence with a single PR-review pause point, no phase loop
generate_chore_steps() {
  cat <<'STEPS'
[
  {"name":"Document chore","skill":"documenting-chores","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile test plan","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute chore","skill":"executing-chores","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile post-review","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Generate the bug chain step sequence (FR-1)
# Fixed 9-step sequence mirroring the chore chain but with bug-specific skills, no phase loop
generate_bug_steps() {
  cat <<'STEPS'
[
  {"name":"Document bug","skill":"documenting-bugs","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Review requirements (standard)","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Document QA test plan","skill":"documenting-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile test plan","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute bug fix","skill":"executing-bug-fixes","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile post-review","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# Post-phase steps appended after phase steps are populated
generate_post_phase_steps() {
  cat <<'STEPS'
[
  {"name":"Create PR","skill":"orchestrator","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"PR review","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null},
  {"name":"Reconcile post-review","skill":"reviewing-requirements","context":"fork","status":"pending","artifact":null,"completedAt":null},
  {"name":"Execute QA","skill":"executing-qa","context":"main","status":"pending","artifact":null,"completedAt":null},
  {"name":"Finalize","skill":"finalizing-workflow","context":"fork","status":"pending","artifact":null,"completedAt":null}
]
STEPS
}

# --- Commands ---

cmd_init() {
  local id="$1"
  local type="$2"
  validate_id "$id"

  ensure_dir
  local file
  file=$(state_file "$id")

  # Idempotency: if state file exists, return current state
  if [[ -f "$file" ]]; then
    cat "$file"
    return 0
  fi

  local steps
  case "$type" in
    feature)
      steps=$(generate_feature_steps)
      ;;
    chore)
      steps=$(generate_chore_steps)
      ;;
    bug)
      steps=$(generate_bug_steps)
      ;;
    *)
      echo "Error: Unknown chain type '${type}'. Supported: feature, chore, bug." >&2
      exit 1
      ;;
  esac

  local now
  now=$(now_iso)

  jq -n \
    --arg id "$id" \
    --arg type "$type" \
    --arg now "$now" \
    --argjson steps "$steps" \
    '{
      id: $id,
      type: $type,
      currentStep: 0,
      status: "in-progress",
      pauseReason: null,
      steps: $steps,
      phases: { total: 0, completed: 0 },
      prNumber: null,
      branch: null,
      startedAt: $now,
      lastResumedAt: null,
      complexity: null,
      complexityStage: "init",
      modelOverride: null,
      modelSelections: []
    }' > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_status() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"
  cat "$file"
}

cmd_advance() {
  local id="$1"
  local artifact="${2:-}"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local current_step total_steps current_status
  current_step=$(jq -r '.currentStep' "$file")
  total_steps=$(jq -r '.steps | length' "$file")
  current_status=$(jq -r ".steps[${current_step}].status" "$file")

  # Idempotency: no-op if step already complete
  if [[ "$current_status" == "complete" ]]; then
    cat "$file"
    return 0
  fi

  local now
  now=$(now_iso)
  local next_step=$((current_step + 1))

  # Update current step to complete, advance currentStep
  local artifact_arg="null"
  if [[ -n "$artifact" ]]; then
    artifact_arg=$(jq -n --arg a "$artifact" '$a')
  fi

  jq \
    --argjson step "$current_step" \
    --argjson next "$next_step" \
    --arg now "$now" \
    --argjson artifact "$artifact_arg" \
    '.steps[$step].status = "complete"
     | .steps[$step].completedAt = $now
     | (if $artifact != null then .steps[$step].artifact = $artifact else . end)
     | .currentStep = $next' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  # Update phase completion count if the completed step had a phaseNumber
  local has_phase
  has_phase=$(jq --argjson step "$current_step" '.steps[$step] | has("phaseNumber")' "$file")
  if [[ "$has_phase" == "true" ]]; then
    jq '.phases.completed = ([.steps[] | select(has("phaseNumber") and .status == "complete")] | length)' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi

  cat "$file"
}

cmd_pause() {
  local id="$1"
  local reason="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  if [[ "$reason" != "plan-approval" && "$reason" != "pr-review" && "$reason" != "review-findings" ]]; then
    echo "Error: Invalid pause reason '${reason}'. Expected 'plan-approval', 'pr-review', or 'review-findings'." >&2
    exit 1
  fi

  jq --arg reason "$reason" \
    '.status = "paused" | .pauseReason = $reason' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_resume() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local now
  now=$(now_iso)

  local current_step
  current_step=$(jq -r '.currentStep' "$file")

  jq --arg now "$now" --argjson step "$current_step" \
    '.status = "in-progress" | .pauseReason = null | .error = null | .lastResumedAt = $now
     | if .steps[$step].status == "failed" then .steps[$step].status = "pending" else . end' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_fail() {
  local id="$1"
  local message="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local current_step
  current_step=$(jq -r '.currentStep' "$file")

  jq --arg msg "$message" --argjson step "$current_step" \
    '.status = "failed" | .error = $msg | .steps[$step].status = "failed"' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_complete() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local now
  now=$(now_iso)

  jq --arg now "$now" \
    '.status = "complete" | .completedAt = $now' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_set_pr() {
  local id="$1"
  local pr_number="$2"
  local branch="$3"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  jq --argjson pr "$pr_number" --arg branch "$branch" \
    '.prNumber = $pr | .branch = $branch' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_populate_phases() {
  local id="$1"
  local count="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  # Idempotency: if phase steps already exist, return current state
  local existing_phases
  existing_phases=$(jq '[.steps[] | select(has("phaseNumber"))] | length' "$file")
  if [[ "$existing_phases" -gt 0 ]]; then
    cat "$file"
    return 0
  fi

  # Generate phase steps
  local phase_steps="[]"
  for ((i = 1; i <= count; i++)); do
    phase_steps=$(echo "$phase_steps" | jq --argjson n "$i" --argjson total "$count" \
      '. + [{"name":"Implement phase \($n) of \($total)","skill":"implementing-plan-phases","context":"fork","status":"pending","artifact":null,"completedAt":null,"phaseNumber":$n}]')
  done

  local post_steps
  post_steps=$(generate_post_phase_steps)

  # Append phase steps + post-phase steps after the initial 6 steps, update phases.total
  jq --argjson phase_steps "$phase_steps" \
     --argjson post_steps "$post_steps" \
     --argjson total "$count" \
    '.steps = .steps[:6] + $phase_steps + $post_steps | .phases.total = $total' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

cmd_phase_count() {
  local id="$1"

  # Find the implementation plan using sorted glob for deterministic results
  local plan_file=""
  if [[ -d "requirements/implementation" ]]; then
    plan_file=$(ls requirements/implementation/${id}-*.md 2>/dev/null | sort | head -1 || true)
  fi

  if [[ -z "$plan_file" ]]; then
    echo "Error: No implementation plan found for ${id} in requirements/implementation/" >&2
    exit 1
  fi

  local count
  count=$(grep -cE '^### Phase [0-9]+' "$plan_file" || true)

  if [[ "$count" -eq 0 ]]; then
    echo "Error: Implementation plan has 0 phases — plan may be malformed: ${plan_file}" >&2
    exit 1
  fi

  echo "$count"
}

cmd_phase_status() {
  local id="$1"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  jq '[.steps[] | select(has("phaseNumber")) | {phaseNumber, status, completedAt}]' "$file"
}

# Set work-item complexity tier (FEAT-014 FR-15). Writes .complexity only.
# complexityStage is untouched — manual override is considered a user edit, not a
# stage transition. Tier must be one of low|medium|high.
cmd_set_complexity() {
  local id="$1"
  local tier="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  if [[ "$tier" != "low" && "$tier" != "medium" && "$tier" != "high" ]]; then
    echo "Error: Invalid complexity tier '${tier}'. Expected 'low', 'medium', or 'high'." >&2
    exit 1
  fi

  jq --arg tier "$tier" '.complexity = $tier' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

# Resolve model tier for a named step (FEAT-014 FR-15).
#
# Pure-bash lookup using the hardcoded step baselines table plus the persisted
# .complexity and .modelOverride fields. Intentionally does NOT implement the
# full FR-3 precedence chain — CLI flags (--model, --complexity, --model-for)
# live in the orchestrator, not here. Use this subcommand only for the
# baseline + work-item complexity + modelOverride subset of the chain.
#
# Resolution order:
#   1. If the step is baseline-locked (finalizing-workflow, pr-creation),
#      return its baseline regardless of complexity. modelOverride (soft)
#      respects the lock; hard overrides live in the orchestrator.
#   2. Otherwise start from baseline, then max(baseline, complexity_tier).
#   3. If .modelOverride is non-null, that replaces the computed tier
#      (soft-override semantics — orchestrator handles hard overrides).
cmd_get_model() {
  local id="$1"
  local step_name="$2"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  local baseline locked complexity override complexity_tier resolved
  baseline=$(_step_baseline "$step_name")
  locked=$(_step_baseline_locked "$step_name")
  complexity=$(jq -r '.complexity // ""' "$file")
  override=$(jq -r '.modelOverride // ""' "$file")

  if [[ "$locked" == "true" ]]; then
    # Baseline-locked: ignore work-item complexity. Soft override (modelOverride)
    # is only applied for non-locked steps; hard override is orchestrator-scope.
    resolved="$baseline"
  else
    complexity_tier=$(_complexity_to_tier "$complexity")
    if [[ -n "$complexity_tier" ]]; then
      resolved=$(_max_tier "$baseline" "$complexity_tier")
    else
      resolved="$baseline"
    fi
    if [[ -n "$override" ]]; then
      resolved="$override"
    fi
  fi

  echo "$resolved"
}

# Append an entry to the modelSelections audit trail (FEAT-014 FR-7, NFR-3).
# Called by the orchestrator immediately before each fork so that a mid-fork
# crash still leaves a record of which model was chosen.
cmd_record_model_selection() {
  local id="$1"
  local step_index="$2"
  local skill="$3"
  local mode="$4"
  local phase="$5"
  local tier="$6"
  local complexity_stage="$7"
  local started_at="$8"
  local file
  file=$(state_file "$id")
  validate_state_file "$file"

  # Normalize "null" literal into JSON null for the optional fields.
  # Phase is numeric when provided (integer phase number); mode is a string.
  local phase_arg="null"
  if [[ -n "$phase" && "$phase" != "null" ]]; then
    if [[ "$phase" =~ ^[0-9]+$ ]]; then
      phase_arg="$phase"
    else
      phase_arg=$(jq -n --arg v "$phase" '$v')
    fi
  fi
  local mode_arg="null"
  if [[ -n "$mode" && "$mode" != "null" ]]; then
    mode_arg=$(jq -n --arg v "$mode" '$v')
  fi

  jq \
    --argjson stepIndex "$step_index" \
    --arg skill "$skill" \
    --argjson mode "$mode_arg" \
    --argjson phase "$phase_arg" \
    --arg tier "$tier" \
    --arg complexityStage "$complexity_stage" \
    --arg startedAt "$started_at" \
    '.modelSelections += [{
       stepIndex: $stepIndex,
       skill: $skill,
       mode: $mode,
       phase: $phase,
       tier: $tier,
       complexityStage: $complexityStage,
       startedAt: $startedAt
     }]' \
    "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  cat "$file"
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  usage
fi

command="$1"
shift

case "$command" in
  init)
    [[ $# -ge 2 ]] || { echo "Error: init requires <ID> <type>" >&2; exit 1; }
    cmd_init "$1" "$2"
    ;;
  status)
    [[ $# -ge 1 ]] || { echo "Error: status requires <ID>" >&2; exit 1; }
    cmd_status "$1"
    ;;
  advance)
    [[ $# -ge 1 ]] || { echo "Error: advance requires <ID> [artifact-path]" >&2; exit 1; }
    cmd_advance "$1" "${2:-}"
    ;;
  pause)
    [[ $# -ge 2 ]] || { echo "Error: pause requires <ID> <reason>" >&2; exit 1; }
    cmd_pause "$1" "$2"
    ;;
  resume)
    [[ $# -ge 1 ]] || { echo "Error: resume requires <ID>" >&2; exit 1; }
    cmd_resume "$1"
    ;;
  fail)
    [[ $# -ge 2 ]] || { echo "Error: fail requires <ID> <message>" >&2; exit 1; }
    cmd_fail "$1" "$2"
    ;;
  complete)
    [[ $# -ge 1 ]] || { echo "Error: complete requires <ID>" >&2; exit 1; }
    cmd_complete "$1"
    ;;
  set-pr)
    [[ $# -ge 3 ]] || { echo "Error: set-pr requires <ID> <pr-number> <branch>" >&2; exit 1; }
    cmd_set_pr "$1" "$2" "$3"
    ;;
  populate-phases)
    [[ $# -ge 2 ]] || { echo "Error: populate-phases requires <ID> <count>" >&2; exit 1; }
    cmd_populate_phases "$1" "$2"
    ;;
  phase-count)
    [[ $# -ge 1 ]] || { echo "Error: phase-count requires <ID>" >&2; exit 1; }
    cmd_phase_count "$1"
    ;;
  phase-status)
    [[ $# -ge 1 ]] || { echo "Error: phase-status requires <ID>" >&2; exit 1; }
    cmd_phase_status "$1"
    ;;
  set-complexity)
    [[ $# -ge 2 ]] || { echo "Error: set-complexity requires <ID> <tier>" >&2; exit 1; }
    cmd_set_complexity "$1" "$2"
    ;;
  get-model)
    [[ $# -ge 2 ]] || { echo "Error: get-model requires <ID> <step-name>" >&2; exit 1; }
    cmd_get_model "$1" "$2"
    ;;
  record-model-selection)
    [[ $# -ge 8 ]] || { echo "Error: record-model-selection requires <ID> <stepIndex> <skill> <mode> <phase> <tier> <complexityStage> <startedAt>" >&2; exit 1; }
    cmd_record_model_selection "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
    ;;
  *)
    echo "Error: Unknown command '${command}'" >&2
    usage
    ;;
esac
