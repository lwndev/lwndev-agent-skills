#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# QA adversarial fixture for BUG-020 — strengthened [info] auto-paused audit line.
#
# Inputs P0/P1 from qa/test-plans/QA-plan-BUG-020.md:
#   * the audit line emitted by cmd_advance when landing on a pause-context
#     step carries four load-bearing tokens on a single stderr line:
#       [info] auto-paused, pauseReason=<reason>, HALT (case-sensitive),
#       surface (case-sensitive)
#   * the separator between (pauseReason=<reason>) and HALT is a plain
#     ASCII hyphen-space, NOT em-dash or en-dash — protects grep-token
#     stability against future stylistic edits.

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

# Seed a feature workflow at currentStep=2 (step 3, fork, "Create plan").
# Advance once lands on the pause-context step "Plan approval" at index 3.
seed_at_pre_pause() {
  local id="$1"
  ( cd "$TMPDIR_TEST" && bash "$WS" init "$id" feature >/dev/null )
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
  jq '.currentStep = 2
      | .steps |= [range(0; 2) as $i | .[$i] | .status = "complete" | .completedAt = "2026-05-17T00:00:00Z"] + .[2:]' \
    "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

@test "[P0] auto-paused audit line carries [info] auto-paused, pauseReason=, HALT, surface — all on one stderr line" {
  seed_at_pre_pause FEAT-710
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" advance FEAT-710
  [ "$status" -eq 0 ]
  # The audit line must be a single line. Locate it then verify token presence.
  local line
  line=$(printf '%s\n' "$stderr" | grep -F '[info] auto-paused' || true)
  [ -n "$line" ]
  [[ "$line" == *"[info] auto-paused"* ]]
  [[ "$line" == *"pauseReason=plan-approval"* ]]
  [[ "$line" == *"HALT"* ]]
  [[ "$line" == *"surface"* ]]
}

@test "[P1] separator between (pauseReason=<reason>) and HALT is ASCII '- ' hyphen-space, not em-dash or en-dash" {
  seed_at_pre_pause FEAT-711
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" advance FEAT-711
  [ "$status" -eq 0 ]
  local line
  line=$(printf '%s\n' "$stderr" | grep -F '[info] auto-paused' || true)
  [ -n "$line" ]
  # Require the canonical ") - HALT" sequence and forbid em-dash / en-dash.
  [[ "$line" == *") - HALT"* ]]
  [[ "$line" != *"—"* ]]
  [[ "$line" != *"–"* ]]
}

@test "[P2] LANG=C does not change the auto-paused audit line — locale-free assertion stability" {
  seed_at_pre_pause FEAT-712
  cd "$TMPDIR_TEST"
  LC_ALL=C LANG=C run --separate-stderr bash "$WS" advance FEAT-712
  [ "$status" -eq 0 ]
  local line
  line=$(printf '%s\n' "$stderr" | grep -F '[info] auto-paused' || true)
  [ -n "$line" ]
  [[ "$line" == *"pauseReason=plan-approval"* ]]
  [[ "$line" == *") - HALT"* ]]
  [[ "$line" == *"surface"* ]]
}
