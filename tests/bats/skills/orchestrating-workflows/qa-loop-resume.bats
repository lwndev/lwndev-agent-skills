#!/usr/bin/env bats
# Bats fixture for QA-loop resume-flag dispatch (FEAT-032 FR-8).
#
# Covers:
#   * --approve-advance: advances with qaFixAttempts preserved (not reset)
#   * --qa-loop-cap <N>: resets qaFixAttempts to 0 AND writes qaLoopCap=N
#   * Neither flag: no state mutation (orchestrator stays paused)
#   * Both flags: parse-model-flags.sh exits 2 with verbatim FR-8 mutual-exclusion message
#   * set-qa-loop-cap subcommand: happy path, missing arg, non-integer cap
#   * reset-qa-fix-attempts: counter is 0 after reset (used by --qa-loop-cap resume path)

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  PMF="${SCRIPT_DIR}/parse-model-flags.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

seed_state_exhausted() {
  local id="${1:-FEAT-032}"
  local qa_fix_attempts="${2:-2}"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "feature",
  "currentStep": 0,
  "status": "paused",
  "pauseReason": "qa-loop-exhausted",
  "gate": null,
  "gateSetAt": null,
  "steps": [
    {"name":"Doc","skill":"documenting-features","context":"main","status":"in-progress","artifact":null,"completedAt":null}
  ],
  "phases": {"total": 0, "completed": 0},
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-04-23T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "medium",
  "complexityStage": "init",
  "modelOverride": null,
  "modelSelections": [],
  "qaFixAttempts": ${qa_fix_attempts},
  "qaLastVerdict": "ISSUES-FOUND",
  "adoptedTests": [],
  "qaLoopCap": 2,
  "stateEvents": []
}
EOF
}

# ---- --approve-advance semantics: counter preserved ---------------------------

@test "--approve-advance: qaFixAttempts preserved after resume" {
  seed_state_exhausted FEAT-032 2
  cd "$TMPDIR_TEST"
  # Simulate --approve-advance: resume (no counter change).
  run --separate-stderr bash "$WS" resume FEAT-032
  [ "$status" -eq 0 ]
  local attempts
  attempts=$(jq -r '.qaFixAttempts' "${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json")
  [ "$attempts" = "2" ]
}

@test "--approve-advance: parse-model-flags emits approveAdvance=true" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$PMF" --approve-advance FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.approveAdvance')" = "true" ]
}

# ---- --qa-loop-cap semantics: counter reset + cap raised ----------------------

@test "--qa-loop-cap: set-qa-loop-cap writes qaLoopCap and reset-qa-fix-attempts resets counter" {
  seed_state_exhausted FEAT-032 2
  cd "$TMPDIR_TEST"
  # set-qa-loop-cap N
  run --separate-stderr bash "$WS" set-qa-loop-cap FEAT-032 4
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLoopCap')" = "4" ]
  # reset-qa-fix-attempts
  run --separate-stderr bash "$WS" reset-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "0" ]
}

@test "--qa-loop-cap: parse-model-flags emits qaLoopCap value" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$PMF" --qa-loop-cap 5 FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLoopCap')" = "5" ]
}

@test "set-qa-loop-cap rejects non-integer cap → exit 1" {
  seed_state_exhausted FEAT-032 2
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-loop-cap FEAT-032 abc
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"positive integer"* ]]
}

@test "set-qa-loop-cap rejects zero cap → exit 1" {
  seed_state_exhausted FEAT-032 2
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-loop-cap FEAT-032 0
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"positive integer"* ]]
}

@test "set-qa-loop-cap missing N → exit 1" {
  seed_state_exhausted FEAT-032 2
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-loop-cap FEAT-032
  [ "$status" -eq 1 ]
}

# ---- neither flag: no state mutation ------------------------------------------

@test "neither flag: parse-model-flags emits approveAdvance=false and qaLoopCap=null" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$PMF" FEAT-032
  [ "$status" -eq 0 ]
  local approve_advance
  approve_advance=$(echo "$output" | jq -r '.approveAdvance // false')
  [ "$approve_advance" = "false" ]
  local cap
  cap=$(echo "$output" | jq -r '.qaLoopCap')
  [ "$cap" = "null" ]
}

# ---- both flags: mutual exclusion guard (FR-8 verbatim) -----------------------

@test "both flags: parse-model-flags exits 2 with FR-8 verbatim message" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$PMF" --approve-advance --qa-loop-cap 3
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--approve-advance and --qa-loop-cap are mutually exclusive"* ]]
}

# ---- reset-qa-fix-attempts edge cases -----------------------------------------

@test "reset-qa-fix-attempts on fresh state → counter stays 0" {
  seed_state_exhausted FEAT-032 0
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" reset-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "0" ]
}
