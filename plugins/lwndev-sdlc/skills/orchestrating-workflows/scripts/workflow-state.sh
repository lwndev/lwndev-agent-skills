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
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
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
      echo "Error: Chain type 'bug' is not yet implemented." >&2
      exit 1
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
      lastResumedAt: null
    }' > "$file"

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

  if [[ "$reason" != "plan-approval" && "$reason" != "pr-review" ]]; then
    echo "Error: Invalid pause reason '${reason}'. Expected 'plan-approval' or 'pr-review'." >&2
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
  *)
    echo "Error: Unknown command '${command}'" >&2
    usage
    ;;
esac
