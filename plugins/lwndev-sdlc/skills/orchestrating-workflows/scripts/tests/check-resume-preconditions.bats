#!/usr/bin/env bats
# Bats fixture for check-resume-preconditions.sh (FEAT-028 / FR-6).
#
# Covers:
#   * Status matrix: in-progress | paused (×3 pauseReasons) | failed | complete.
#   * chainTable == type invariant across feature | chore | bug.
#   * resume-recompute stderr relay: `[model] ...` line emitted by the stub
#     must surface on the script's stderr verbatim.
#   * Error paths: missing state file (1), missing arg (2), malformed ID (2).
#
# Fixture strategy: each test chdirs into a per-test mktemp dir and seeds a
# controlled `.sdlc/workflows/<ID>.json` state file. A `workflow-state.sh`
# stub is installed on PATH ahead of the real script so the tests do not
# depend on any real classifier behavior.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  CHECK="${SCRIPT_DIR}/check-resume-preconditions.sh"
  TMPDIR_TEST="$(mktemp -d)"
  STUB_DIR="${TMPDIR_TEST}/stubs"
  mkdir -p "$STUB_DIR" "${TMPDIR_TEST}/.sdlc/workflows"
  install_workflow_state_stub
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Default workflow-state.sh stub:
#   * status <ID>            → cat the state file (so test-seeded fields flow
#                              directly into the `status` projection)
#   * resume-recompute <ID>  → exit 0 silently (no upgrade by default)
install_workflow_state_stub() {
  cat > "${STUB_DIR}/workflow-state.sh" <<'STUB'
#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  status)
    id="${1:-}"
    cat ".sdlc/workflows/${id}.json"
    ;;
  resume-recompute)
    : # default no-op; tests override to emit [model] stderr.
    ;;
  *)
    echo "stub: unknown command $cmd" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/workflow-state.sh"
}

# Seed a state file with controllable status/pauseReason/type/complexity.
write_state() {
  local id="$1"
  local type="$2"
  local status="$3"
  local pause_reason="$4"  # empty string for JSON null
  local complexity="$5"
  local complexity_stage="${6:-init}"

  local pause_field
  if [ -z "$pause_reason" ]; then
    pause_field="null"
  else
    pause_field="\"$pause_reason\""
  fi

  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "${type}",
  "currentStep": 3,
  "status": "${status}",
  "pauseReason": ${pause_field},
  "gate": null,
  "steps": [],
  "phases": {"total": 0, "completed": 0},
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-04-23T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "${complexity}",
  "complexityStage": "${complexity_stage}",
  "modelOverride": null,
  "modelSelections": []
}
EOF
}

run_with_stubs() {
  PATH="${STUB_DIR}:${PATH}" run "$@"
}

get_field() {
  local json="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${key}"
  else
    printf '%s' "$json" | sed -E "s/.*\"${key}\":\"?([^\",}]*)\"?.*/\1/"
  fi
}

# ---- status matrix ----------------------------------------------------------

@test "status=in-progress → status=in-progress, pauseReason=null, exit 0" {
  write_state FEAT-028 feature in-progress "" medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" status)" = "in-progress" ]
  # pauseReason is JSON null → get_field returns "null" via jq.
  if command -v jq >/dev/null 2>&1; then
    [ "$(printf '%s' "$output" | jq -r '.pauseReason')" = "null" ]
  fi
}

@test "status=paused + plan-approval → pauseReason=plan-approval, exit 0" {
  write_state FEAT-028 feature paused plan-approval medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" status)" = "paused" ]
  [ "$(get_field "$output" pauseReason)" = "plan-approval" ]
}

@test "status=paused + pr-review → pauseReason=pr-review, exit 0" {
  write_state FEAT-028 feature paused pr-review medium post-plan
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" pauseReason)" = "pr-review" ]
}

@test "status=paused + review-findings → pauseReason=review-findings, exit 0" {
  write_state FEAT-028 feature paused review-findings high init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" pauseReason)" = "review-findings" ]
}

@test "status=failed → status=failed, pauseReason=null, exit 0" {
  write_state FEAT-028 feature failed "" medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" status)" = "failed" ]
  if command -v jq >/dev/null 2>&1; then
    [ "$(printf '%s' "$output" | jq -r '.pauseReason')" = "null" ]
  fi
}

@test "status=complete → status=complete, pauseReason=null, exit 0" {
  write_state FEAT-028 feature complete "" high post-plan
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" status)" = "complete" ]
  if command -v jq >/dev/null 2>&1; then
    [ "$(printf '%s' "$output" | jq -r '.pauseReason')" = "null" ]
  fi
}

# ---- chainTable == type invariant -------------------------------------------

@test "chainTable == type for feature chain" {
  write_state FEAT-028 feature in-progress "" medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "feature" ]
  [ "$(get_field "$output" chainTable)" = "feature" ]
}

@test "chainTable == type for chore chain" {
  write_state CHORE-001 chore in-progress "" low init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" CHORE-001
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "chore" ]
  [ "$(get_field "$output" chainTable)" = "chore" ]
}

@test "chainTable == type for bug chain" {
  write_state BUG-001 bug in-progress "" medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" BUG-001
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "bug" ]
  [ "$(get_field "$output" chainTable)" = "bug" ]
}

# ---- resume-recompute stderr relay ------------------------------------------

@test "resume-recompute [model] upgrade line surfaces on stderr verbatim" {
  write_state FEAT-028 feature in-progress "" medium init
  # Override the stub to emit the [model] line on stderr.
  cat > "${STUB_DIR}/workflow-state.sh" <<'STUB'
#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  status)
    id="${1:-}"
    cat ".sdlc/workflows/${id}.json"
    ;;
  resume-recompute)
    echo "[model] Work-item complexity upgraded from low to medium for FEAT-028" >&2
    ;;
  *)
    echo "stub: unknown command $cmd" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/workflow-state.sh"

  cd "$TMPDIR_TEST"
  # Use run with combined stderr+stdout capture; bats 1.5+ supports
  # --separate-stderr via BATS_OUT split. Older: stderr merges into $output
  # when run uses `2>&1`. Use explicit file capture for portability.
  stderr_file="${TMPDIR_TEST}/check.err"
  PATH="${STUB_DIR}:${PATH}" bash "$CHECK" FEAT-028 >/dev/null 2>"$stderr_file"
  exit_code=$?
  [ "$exit_code" -eq 0 ]
  grep -q '\[model\] Work-item complexity upgraded from low to medium for FEAT-028' "$stderr_file"
}

@test "status stderr relayed verbatim without contaminating JSON (FR-13 migration debug)" {
  # Override the stub so `status` emits the workflow-state.sh FR-13 migration
  # debug line to stderr AND valid JSON to stdout. Previously the script's
  # 2>&1 capture merged the debug line into status_json, breaking jq parsing.
  write_state FEAT-028 feature in-progress "" medium init
  cat > "${STUB_DIR}/workflow-state.sh" <<'STUB'
#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  status)
    id="${1:-}"
    echo "[workflow-state] debug: migrating .sdlc/workflows/${id}.json to add missing state fields (model-selection and gate)" >&2
    cat ".sdlc/workflows/${id}.json"
    ;;
  resume-recompute)
    : ;;
  *)
    echo "stub: unknown command $cmd" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/workflow-state.sh"

  cd "$TMPDIR_TEST"
  stderr_file="${TMPDIR_TEST}/check.err"
  stdout_file="${TMPDIR_TEST}/check.out"
  PATH="${STUB_DIR}:${PATH}" bash "$CHECK" FEAT-028 >"$stdout_file" 2>"$stderr_file"
  exit_code=$?
  [ "$exit_code" -eq 0 ]
  # Debug line must surface on stderr verbatim.
  grep -q '\[workflow-state\] debug: migrating' "$stderr_file"
  # Stdout must be clean JSON (no debug prefix contaminating the projection).
  output=$(cat "$stdout_file")
  [ "$(get_field "$output" type)" = "feature" ]
  [ "$(get_field "$output" status)" = "in-progress" ]
  [ "$(get_field "$output" complexity)" = "medium" ]
}

# ---- pass-through invariant: complexity is NOT downgraded ------------------

@test "check-resume-preconditions does not downgrade complexity" {
  # State file says medium. Stub resume-recompute returns 0 without modifying
  # the file. Output must still say medium.
  write_state FEAT-028 feature in-progress "" medium init
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-028
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" complexity)" = "medium" ]
  [ "$(get_field "$output" complexityStage)" = "init" ]
}

# ---- error paths ------------------------------------------------------------

@test "missing state file → exit 1" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" FEAT-999
  [ "$status" -eq 1 ]
}

@test "missing <ID> arg → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK"
  [ "$status" -eq 2 ]
}

@test "malformed ID (lowercase feat-028) → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" feat-028
  [ "$status" -eq 2 ]
}

@test "malformed ID (unknown prefix) → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$CHECK" TASK-001
  [ "$status" -eq 2 ]
}
