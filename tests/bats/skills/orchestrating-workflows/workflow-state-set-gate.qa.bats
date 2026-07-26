#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# QA adversarial fixture for BUG-020 — cmd_set_gate whitelist extension.
#
# Independent re-verification of the Inputs dimension P0/P1 scenarios from
# qa/test-plans/QA-plan-BUG-020.md. Probes the cmd_set_gate enum guard and
# state-file mutation side-effects against several adversarial inputs.

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

@test "[P0] set-gate merge-approval succeeds; .gate and .gateSetAt are written with ISO-8601-Z stamp" {
  init_feature FEAT-700
  cd "$TMPDIR_TEST"
  run bash "$WS" set-gate FEAT-700 merge-approval
  [ "$status" -eq 0 ]
  local state_file=".sdlc/workflows/FEAT-700.json"
  [ "$(jq -r '.gate' "$state_file")" = "merge-approval" ]
  local gate_set_at
  gate_set_at=$(jq -r '.gateSetAt' "$state_file")
  [[ "$gate_set_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "[P0] set-gate findings-decision still succeeds (regression)" {
  init_feature FEAT-701
  cd "$TMPDIR_TEST"
  run bash "$WS" set-gate FEAT-701 findings-decision
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gate' ".sdlc/workflows/FEAT-701.json")" = "findings-decision" ]
}

@test "[P0] set-gate <bogus> rejects with exit 1 and the multi-value enum error" {
  init_feature FEAT-702
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-702 bogus
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Expected one of: findings-decision, merge-approval"* ]]
}

@test "[P0] set-gate MERGE-APPROVAL (wrong case) rejects on enum check" {
  init_feature FEAT-703
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-703 MERGE-APPROVAL
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Expected one of: findings-decision, merge-approval"* ]]
}

@test "[P0] set-gate with empty string rejects on enum check" {
  init_feature FEAT-704
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-704 ""
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Expected one of: findings-decision, merge-approval"* ]]
}

@test "[P1] set-gate merge-approval is idempotent: second call refreshes gateSetAt and leaves gate set" {
  init_feature FEAT-705
  cd "$TMPDIR_TEST"
  run bash "$WS" set-gate FEAT-705 merge-approval
  [ "$status" -eq 0 ]
  local first_set_at
  first_set_at=$(jq -r '.gateSetAt' ".sdlc/workflows/FEAT-705.json")
  sleep 1
  run bash "$WS" set-gate FEAT-705 merge-approval
  [ "$status" -eq 0 ]
  local state_file=".sdlc/workflows/FEAT-705.json"
  [ "$(jq -r '.gate' "$state_file")" = "merge-approval" ]
  local second_set_at
  second_set_at=$(jq -r '.gateSetAt' "$state_file")
  [[ "$second_set_at" > "$first_set_at" ]]
}

@test "[P1] set-gate merge-approval on a paused workflow rejects with the no-regression error" {
  init_feature FEAT-706
  cd "$TMPDIR_TEST"
  bash "$WS" pause FEAT-706 pr-review >/dev/null
  run --separate-stderr bash "$WS" set-gate FEAT-706 merge-approval
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Cannot set gate on a paused workflow"* ]]
}

@test "[P2] shell-injection arg in gate-type is rejected by the enum check before any expansion" {
  init_feature FEAT-707
  cd "$TMPDIR_TEST"
  rm -f /tmp/qa-bug-020-injection-marker
  run --separate-stderr bash "$WS" set-gate FEAT-707 'merge-approval; touch /tmp/qa-bug-020-injection-marker'
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Expected one of: findings-decision, merge-approval"* ]]
  [ ! -e /tmp/qa-bug-020-injection-marker ]
}
