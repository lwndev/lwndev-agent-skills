#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# QA adversarial fixture for BUG-020 — gate / gateSetAt clearing on state transitions.
#
# State-transitions P0/P1 from qa/test-plans/QA-plan-BUG-020.md:
#   * After set-gate <ID> merge-approval, calling advance <ID> clears .gate
#     and .gateSetAt (inline mutation at cmd_advance).
#   * After set-gate <ID> merge-approval, calling pause <ID> <reason> clears
#     .gate and .gateSetAt (cmd_pause auto-clear).
#   * cmd_advance landing on a pause-context step auto-pauses but does not
#     set .gate — confirms BUG-018 atomic auto-pause and BUG-020 gate
#     semantics do not collide.

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

init_feature() {
  local id="$1"
  ( cd "$TMPDIR_TEST" && bash "$WS" init "$id" feature >/dev/null )
}

@test "[P0] advance after set-gate merge-approval clears .gate and .gateSetAt to null" {
  init_feature FEAT-720
  cd "$TMPDIR_TEST"
  bash "$WS" set-gate FEAT-720 merge-approval >/dev/null
  [ "$(jq -r '.gate' ".sdlc/workflows/FEAT-720.json")" = "merge-approval" ]
  run bash "$WS" advance FEAT-720
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gate' ".sdlc/workflows/FEAT-720.json")" = "null" ]
  [ "$(jq -r '.gateSetAt' ".sdlc/workflows/FEAT-720.json")" = "null" ]
}

@test "[P1] pause after set-gate merge-approval clears .gate and .gateSetAt to null" {
  init_feature FEAT-721
  cd "$TMPDIR_TEST"
  bash "$WS" set-gate FEAT-721 merge-approval >/dev/null
  run bash "$WS" pause FEAT-721 pr-review
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gate' ".sdlc/workflows/FEAT-721.json")" = "null" ]
  [ "$(jq -r '.gateSetAt' ".sdlc/workflows/FEAT-721.json")" = "null" ]
}

@test "[P1] auto-pause on a pause-context advance leaves .gate == null (no collision with BUG-020 gate semantic)" {
  init_feature FEAT-722
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-722.json"
  jq '.currentStep = 2
      | .steps |= [range(0; 2) as $i | .[$i] | .status = "complete" | .completedAt = "2026-05-17T00:00:00Z"] + .[2:]' \
    "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  run --separate-stderr bash "$WS" advance FEAT-722
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gate' "$state_file")" = "null" ]
  [ "$(jq -r '.status' "$state_file")" = "paused" ]
  [ "$(jq -r '.pauseReason' "$state_file")" = "plan-approval" ]
}

@test "[P2] rapid set-gate / clear-gate cycles leave the state file parseable" {
  init_feature FEAT-723
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-723.json"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    bash "$WS" set-gate FEAT-723 merge-approval >/dev/null
    bash "$WS" clear-gate FEAT-723 >/dev/null
  done
  jq -e . "$state_file" >/dev/null
  [ "$(jq -r '.id' "$state_file")" = "FEAT-723" ]
  [ "$(jq -r '.gate' "$state_file")" = "null" ]
  [ "$(jq -r '.status' "$state_file")" = "in-progress" ]
}
