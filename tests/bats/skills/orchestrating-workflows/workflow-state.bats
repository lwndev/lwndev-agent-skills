#!/usr/bin/env bats
# Bats fixture for workflow-state.sh FEAT-032 QA-loop subcommands.
#
# Covers:
#   * set-qa-verdict happy path (each verdict) + invalid verdict rejection
#   * inc-qa-fix-attempts increments and emits the new count on stdout
#   * reset-qa-fix-attempts returns counter to 0
#   * record-adopted-test appends to the adoptedTests array
#   * get-qa-state emits {qaFixAttempts, qaLastVerdict, adoptedTests} JSON
#   * NFR-3 in-place migration: read a pre-FEAT-032 fixture lacking the three
#     new fields; subsequent mutation persists defaults
#   * Missing-arg paths exit 1 with the documented message

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/../../../fixtures/orchestrating-workflows"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Seed a state file with the FEAT-032-aware shape. Defaults to a fresh
# pre-FEAT-032 fixture (no qaFixAttempts / qaLastVerdict / adoptedTests fields)
# so the migration path is exercised on first read.
seed_pre_feat032_state() {
  local id="$1"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "feature",
  "currentStep": 0,
  "status": "in-progress",
  "pauseReason": null,
  "gate": null,
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
  "modelSelections": []
}
EOF
}

# ---- NFR-3 in-place migration -----------------------------------------------

@test "NFR-3: pre-FEAT-032 fixture lacks fields; first get-qa-state emits defaults" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" get-qa-state FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "0" ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "null" ]
  [ "$(echo "$output" | jq -c '.adoptedTests')" = "[]" ]
}

@test "NFR-3: migration persists defaults to disk on first mutation" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  # First read triggers in-place migration; the file is rewritten with defaults.
  bash "$WS" get-qa-state FEAT-032 >/dev/null 2>&1
  # Confirm the file now has all three new fields.
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  [ "$(jq -r '.qaFixAttempts' "$state_file")" = "0" ]
  [ "$(jq -r '.qaLastVerdict' "$state_file")" = "null" ]
  [ "$(jq -c '.adoptedTests' "$state_file")" = "[]" ]
  [ "$(jq -r '.qaLoopCap' "$state_file")" = "2" ]
}

# ---- set-qa-verdict ---------------------------------------------------------

@test "set-qa-verdict PASS persists qaLastVerdict" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-032 PASS
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "PASS" ]
}

@test "set-qa-verdict ISSUES-FOUND persists qaLastVerdict" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-032 ISSUES-FOUND
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "ISSUES-FOUND" ]
}

@test "set-qa-verdict ERROR persists qaLastVerdict" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-032 ERROR
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "ERROR" ]
}

@test "set-qa-verdict EXPLORATORY-ONLY persists qaLastVerdict" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-032 EXPLORATORY-ONLY
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "EXPLORATORY-ONLY" ]
}

@test "set-qa-verdict invalid → exit 1" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-032 BROKEN
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"verdict must be one of"* ]]
}

@test "set-qa-verdict missing arg → exit 1" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-qa-verdict
  [ "$status" -eq 1 ]
}

# ---- inc-qa-fix-attempts ----------------------------------------------------

@test "inc-qa-fix-attempts increments and emits new count on stdout" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" inc-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run --separate-stderr bash "$WS" inc-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  run --separate-stderr bash "$WS" inc-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "inc-qa-fix-attempts persists to disk" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  [ "$(jq -r '.qaFixAttempts' "$state_file")" = "2" ]
}

@test "inc-qa-fix-attempts missing arg → exit 1" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" inc-qa-fix-attempts
  [ "$status" -eq 1 ]
}

# ---- reset-qa-fix-attempts --------------------------------------------------

@test "reset-qa-fix-attempts returns counter to 0" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  run --separate-stderr bash "$WS" reset-qa-fix-attempts FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "0" ]
}

@test "reset-qa-fix-attempts missing arg → exit 1" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" reset-qa-fix-attempts
  [ "$status" -eq 1 ]
}

# ---- record-adopted-test ----------------------------------------------------

@test "record-adopted-test appends to adoptedTests" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-adopted-test FEAT-032 tests/unit/foo.qa.test.ts
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.adoptedTests')" = '["tests/unit/foo.qa.test.ts"]' ]
  run --separate-stderr bash "$WS" record-adopted-test FEAT-032 tests/unit/bar.qa.test.ts
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.adoptedTests')" = '["tests/unit/foo.qa.test.ts","tests/unit/bar.qa.test.ts"]' ]
}

@test "record-adopted-test missing path → exit 1" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-adopted-test FEAT-032
  [ "$status" -eq 1 ]
}

# ---- get-qa-state -----------------------------------------------------------

@test "get-qa-state emits the FR-4 triple JSON" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" set-qa-verdict FEAT-032 ISSUES-FOUND >/dev/null
  bash "$WS" record-adopted-test FEAT-032 tests/unit/foo.qa.test.ts >/dev/null
  run --separate-stderr bash "$WS" get-qa-state FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "1" ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "ISSUES-FOUND" ]
  [ "$(echo "$output" | jq -c '.adoptedTests')" = '["tests/unit/foo.qa.test.ts"]' ]
}

@test "get-qa-state on fresh fixture emits defaults" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" get-qa-state FEAT-032
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.qaFixAttempts')" = "0" ]
  [ "$(echo "$output" | jq -r '.qaLastVerdict')" = "null" ]
  [ "$(echo "$output" | jq -c '.adoptedTests')" = "[]" ]
}

@test "get-qa-state missing arg → exit 1" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" get-qa-state
  [ "$status" -eq 1 ]
}
