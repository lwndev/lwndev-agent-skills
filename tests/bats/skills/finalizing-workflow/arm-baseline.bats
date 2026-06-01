#!/usr/bin/env bats
# arm-baseline.bats — Regression tests for
# finalizing-workflow/scripts/arm-baseline.sh (BUG-024 capture-if-absent).
#
# The capture-if-absent invariant is load-bearing: a finalize re-run after a
# pre-flight block MUST reuse the original baseline, never recapture, so an
# out-of-surface commit made between runs is still measured against the clean
# pre-finalize tip.

ARM="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)/arm-baseline.sh"

setup() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "source" > src.ts
  git add .
  git commit -q -m "initial"
  FIRST_SHA="$(git rev-parse HEAD)"
}

teardown() {
  if [ -n "${REPO:-}" ] && [ -d "$REPO" ]; then
    rm -rf "$REPO"
  fi
}

@test "1. absent baseline → captures current HEAD and prints it" {
  cd "$REPO"
  run bash "$ARM" "BUG-024"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIRST_SHA" ]
  [ -f ".git/sdlc-finalize-baseline-BUG-024" ]
  [ "$(cat .git/sdlc-finalize-baseline-BUG-024)" = "$FIRST_SHA" ]
  # Marker is invisible to git status (lives in the git dir, not the work tree).
  [ -z "$(git status --porcelain)" ]
}

@test "2. present baseline is REUSED, never recaptured after HEAD advances" {
  cd "$REPO"
  bash "$ARM" "BUG-024" >/dev/null

  # Advance HEAD (simulating the model's out-of-surface commit between runs).
  echo "mutation" > qa-evil.test.ts
  git add .
  git commit -q -m "chore: overreach"
  SECOND_SHA="$(git rev-parse HEAD)"
  [ "$SECOND_SHA" != "$FIRST_SHA" ]

  # Re-run: must reuse the ORIGINAL baseline, not the post-mutation tip.
  run bash "$ARM" "BUG-024"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIRST_SHA" ]
  [ "$(cat .git/sdlc-finalize-baseline-BUG-024)" = "$FIRST_SHA" ]
}

@test "3. keyed by ID — distinct IDs get distinct baseline files" {
  cd "$REPO"
  bash "$ARM" "BUG-024" >/dev/null
  bash "$ARM" "FEAT-099" >/dev/null
  [ -f ".git/sdlc-finalize-baseline-BUG-024" ]
  [ -f ".git/sdlc-finalize-baseline-FEAT-099" ]
}

@test "4. non-git tree → prints empty, writes no baseline file" {
  NONGIT="$(mktemp -d)"
  cd "$NONGIT"
  run bash "$ARM" "BUG-024"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$NONGIT"
}
