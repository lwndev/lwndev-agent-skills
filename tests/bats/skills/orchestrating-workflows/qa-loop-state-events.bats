#!/usr/bin/env bats
# Bats fixture for QA-loop state events (FEAT-032 Edge Case 15).
#
# Covers:
#   * inc-qa-fix-attempts records a {type:"qa-fix-attempt", attempt:<N>, at:<ISO>} entry
#     in stateEvents on each call
#   * Multiple increments produce multiple ordered stateEvents entries
#   * reset-qa-fix-attempts does NOT clear stateEvents (history preserved)
#   * stateEvents is initialised as [] on workflow init
#   * stateEvents is migrated to [] on pre-FEAT-032 state files (NFR-3)
#   * stateEvents entries contain the correct attempt number

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

seed_fresh_state() {
  local id="${1:-FEAT-032}"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "feature",
  "currentStep": 0,
  "status": "in-progress",
  "pauseReason": null,
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
  "qaFixAttempts": 0,
  "qaLastVerdict": null,
  "adoptedTests": [],
  "qaLoopCap": 2,
  "stateEvents": []
}
EOF
}

seed_pre_feat032_state() {
  local id="${1:-FEAT-032}"
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

# ---- inc-qa-fix-attempts records a state event --------------------------------

@test "inc-qa-fix-attempts: first call records stateEvents[0] with type=qa-fix-attempt attempt=1" {
  seed_fresh_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  local events_len
  events_len=$(jq '.stateEvents | length' "$state_file")
  [ "$events_len" = "1" ]
  [ "$(jq -r '.stateEvents[0].type' "$state_file")" = "qa-fix-attempt" ]
  [ "$(jq -r '.stateEvents[0].attempt' "$state_file")" = "1" ]
}

@test "inc-qa-fix-attempts: each call adds one entry with increasing attempt number" {
  seed_fresh_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  local events_len
  events_len=$(jq '.stateEvents | length' "$state_file")
  [ "$events_len" = "3" ]
  [ "$(jq -r '.stateEvents[0].attempt' "$state_file")" = "1" ]
  [ "$(jq -r '.stateEvents[1].attempt' "$state_file")" = "2" ]
  [ "$(jq -r '.stateEvents[2].attempt' "$state_file")" = "3" ]
}

@test "inc-qa-fix-attempts: each stateEvent has an 'at' timestamp" {
  seed_fresh_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  local at
  at=$(jq -r '.stateEvents[0].at' "$state_file")
  # ISO-8601 format: starts with a digit year
  [[ "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# ---- reset-qa-fix-attempts preserves stateEvents (history not cleared) --------

@test "reset-qa-fix-attempts preserves stateEvents (history remains traceable)" {
  seed_fresh_state FEAT-032
  cd "$TMPDIR_TEST"
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  bash "$WS" reset-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  # qaFixAttempts reset to 0
  [ "$(jq -r '.qaFixAttempts' "$state_file")" = "0" ]
  # stateEvents still has 2 entries
  local events_len
  events_len=$(jq '.stateEvents | length' "$state_file")
  [ "$events_len" = "2" ]
}

# ---- stateEvents initialised on workflow init ---------------------------------

@test "workflow init creates stateEvents as empty array" {
  seed_fresh_state FEAT-032
  cd "$TMPDIR_TEST"
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  local events_len
  events_len=$(jq '.stateEvents | length' "$state_file")
  [ "$events_len" = "0" ]
}

# ---- NFR-3 migration: pre-FEAT-032 state gets stateEvents = [] ---------------

@test "NFR-3: pre-FEAT-032 fixture gets stateEvents migrated to [] on first mutation" {
  seed_pre_feat032_state FEAT-032
  cd "$TMPDIR_TEST"
  # First call triggers migration then writes event.
  bash "$WS" inc-qa-fix-attempts FEAT-032 >/dev/null
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json"
  # The file should now have stateEvents array.
  local events_raw
  events_raw=$(jq -c '.stateEvents' "$state_file")
  [[ "$events_raw" != "null" ]]
  # Should have the one event from inc-qa-fix-attempts.
  local events_len
  events_len=$(jq '.stateEvents | length' "$state_file")
  [ "$events_len" = "1" ]
}
