#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# FEAT-032 FR-12 — commit-qa-artifact.sh: stages and commits the QA results
# artifact with verdict-and-mode-aware messages, post-condition: clean tree.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/executing-qa/scripts" && pwd)"
  SCRIPT="${SCRIPT_DIR}/commit-qa-artifact.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"
  mkdir -p qa/test-results
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

write_artifact() {
  printf '%s\n' "## Summary" "test artifact" > "qa/test-results/QA-results-$1.md"
}

# --- arg validation ---------------------------------------------------------

@test "no args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "one arg -> exit 2" {
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 2 ]
}

@test "unknown mode -> exit 2" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 unknown
  [ "$status" -eq 2 ]
}

@test "re-qa mode without attempt -> exit 2" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 re-qa
  [ "$status" -eq 2 ]
}

@test "re-qa mode with non-integer attempt -> exit 2" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 re-qa abc
  [ "$status" -eq 2 ]
}

@test "re-qa mode with zero attempt -> exit 2 (must be positive)" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 re-qa 0
  [ "$status" -eq 2 ]
}

@test "missing artifact -> exit 1" {
  run bash "$SCRIPT" FEAT-100 initial
  [ "$status" -eq 1 ]
  [[ "$output" == *"QA results artifact not found"* ]]
}

# --- happy path -------------------------------------------------------------

@test "FR-12 initial-run: commit message verbatim 'qa(FEAT-100): record QA results'" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 initial
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-100): record QA results" ]
}

@test "FR-12 re-qa attempt 1: commit message verbatim 'qa(FEAT-100): re-record QA results after fix attempt 1'" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 re-qa 1
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-100): re-record QA results after fix attempt 1" ]
}

@test "FR-12 re-qa attempt 2: commit message includes attempt 2" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 re-qa 2
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-100): re-record QA results after fix attempt 2" ]
}

@test "FR-12 post-condition: working tree clean after commit" {
  write_artifact FEAT-100
  run bash "$SCRIPT" FEAT-100 initial
  [ "$status" -eq 0 ]
  porcelain="$(git status --porcelain)"
  [ -z "$porcelain" ]
}

@test "FR-12 idempotent: second invocation with no artifact change -> exit 1 informational" {
  write_artifact FEAT-100
  bash "$SCRIPT" FEAT-100 initial
  run bash "$SCRIPT" FEAT-100 initial
  [ "$status" -eq 1 ]
}

@test "FR-12 re-QA overwrites artifact then commits with new message" {
  write_artifact FEAT-100
  bash "$SCRIPT" FEAT-100 initial
  # simulate re-QA overwriting the artifact in place
  printf '%s\n' "## Summary" "re-QA artifact" > qa/test-results/QA-results-FEAT-100.md
  run bash "$SCRIPT" FEAT-100 re-qa 1
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-100): re-record QA results after fix attempt 1" ]
  porcelain="$(git status --porcelain)"
  [ -z "$porcelain" ]
}
