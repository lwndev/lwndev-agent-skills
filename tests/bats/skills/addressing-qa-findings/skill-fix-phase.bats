#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Bats coverage for the addressing-qa-findings fix-phase precheck helpers
# (FEAT-032 / Phase 2 / FR-4).
#
# Covers the deterministic surfaces of the fix phase:
#   * detect-phase.sh: returns phase=fix on (ISSUES-FOUND, attempts=0, no adopts).
#   * detect-phase.sh: returns phase=fix on (ISSUES-FOUND, attempts>0, no adopts)
#     — re-fix after a partial loop is still the fix phase per FR-4.
#   * detect-phase.sh: returns phase=adopt on (PASS, attempts>0, no adopts).
#   * detect-phase.sh: returns phase=unknown on (PASS, attempts=0, no adopts)
#     — initial-run PASS does not need addressing-qa-findings; orchestrator
#     advances directly per FR-7.
#   * detect-phase.sh: returns phase=unknown on adopt-already-done state.
#   * check-fix-prechecks.sh: rejects dirty working tree with verbatim message.
#   * check-fix-prechecks.sh: rejects missing QA artifact with verbatim message.
#   * check-fix-prechecks.sh: passes on clean tree + present artifact.

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  ADDR_SCRIPTS="${PLUGIN_DIR}/skills/addressing-qa-findings/scripts"
  WF_STATE="${PLUGIN_DIR}/skills/orchestrating-workflows/scripts/workflow-state.sh"
  DETECT="${ADDR_SCRIPTS}/detect-phase.sh"
  PRECHECK="${ADDR_SCRIPTS}/check-fix-prechecks.sh"

  TMPDIR_TEST="$(mktemp -d)"
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"
  printf 'placeholder\n' > "$TMPDIR_TEST/README"
  git -C "$TMPDIR_TEST" add README
  git -C "$TMPDIR_TEST" commit -q -m "init"

  cd "$TMPDIR_TEST"

  # Initialize a workflow state file. workflow-state.sh init expects type to
  # be one of feature|chore|bug; we use feature for the fixture.
  bash "$WF_STATE" init "FEAT-032" feature >/dev/null
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- detect-phase.sh -------------------------------------------------------

@test "detect-phase: ISSUES-FOUND with no adopts → phase=fix" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "ISSUES-FOUND" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=fix" ]
}

@test "detect-phase: ISSUES-FOUND with attempts>0 and no adopts → phase=fix" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "ISSUES-FOUND" >/dev/null
  bash "$WF_STATE" inc-qa-fix-attempts "FEAT-032" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=fix" ]
}

@test "detect-phase: PASS with attempts>0 and no adopts → phase=adopt" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" inc-qa-fix-attempts "FEAT-032" >/dev/null
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "PASS" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=adopt" ]
}

@test "detect-phase: PASS with attempts=0 → phase=unknown (initial-run PASS)" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "PASS" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=unknown" ]
}

@test "detect-phase: PASS with adopts already recorded → phase=unknown" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" inc-qa-fix-attempts "FEAT-032" >/dev/null
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "PASS" >/dev/null
  bash "$WF_STATE" record-adopted-test "FEAT-032" "tests/unit/foo.qa.test.ts" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=unknown" ]
}

@test "detect-phase: ERROR verdict → phase=unknown" {
  cd "$TMPDIR_TEST"
  bash "$WF_STATE" set-qa-verdict "FEAT-032" "ERROR" >/dev/null
  run bash "$DETECT" "FEAT-032"
  [ "$status" -eq 0 ]
  [ "$output" = "phase=unknown" ]
}

@test "detect-phase: missing arg → exit 2" {
  run bash "$DETECT"
  [ "$status" -eq 2 ]
}

# --- check-fix-prechecks.sh -------------------------------------------------

@test "check-fix-prechecks: clean tree + artifact present → exit 0 silent" {
  mkdir -p qa/test-results
  printf '# QA-results\n' > qa/test-results/QA-results-FEAT-032.md
  git add . && git commit -q -m "qa-fixture"

  run bash "$PRECHECK" "FEAT-032"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check-fix-prechecks: dirty unstaged change → exit 1 with verbatim message" {
  mkdir -p qa/test-results
  printf '# QA-results\n' > qa/test-results/QA-results-FEAT-032.md
  git add . && git commit -q -m "qa-fixture"

  printf 'dirty\n' >> README

  run bash "$PRECHECK" "FEAT-032"
  [ "$status" -eq 1 ]
  [ "$output" = "failed | working tree dirty; commit or stash before re-running" ]
}

@test "check-fix-prechecks: dirty staged change → exit 1 with verbatim message" {
  mkdir -p qa/test-results
  printf '# QA-results\n' > qa/test-results/QA-results-FEAT-032.md
  git add . && git commit -q -m "qa-fixture"

  printf 'staged\n' >> README
  git add README

  run bash "$PRECHECK" "FEAT-032"
  [ "$status" -eq 1 ]
  [ "$output" = "failed | working tree dirty; commit or stash before re-running" ]
}

@test "check-fix-prechecks: missing QA artifact → exit 1 with verbatim placeholder message" {
  run bash "$PRECHECK" "FEAT-032"
  [ "$status" -eq 1 ]
  [ "$output" = "failed | no QA artifact at qa/test-results/QA-results-{ID}.md" ]
}

@test "check-fix-prechecks: missing arg → exit 2" {
  run bash "$PRECHECK"
  [ "$status" -eq 2 ]
}

