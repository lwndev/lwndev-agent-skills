#!/usr/bin/env bats
# Bats fixture for ensure-branch.sh (FR-5).
#
# All tests run inside a synthetic throw-away git repo created in setup()
# so no branch operations touch the marketplace repo itself.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  ENSURE="${SCRIPT_DIR}/ensure-branch.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "initial" > README.md
  git add README.md
  git -c commit.gpgsign=false commit -q -m "initial"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: already on target branch → 'on <branch>'" {
  run bash "$ENSURE" main
  [ "$status" -eq 0 ]
  [ "$output" = "on main" ]
}

@test "branch does not exist: creates it → 'created <branch>'" {
  run bash "$ENSURE" feat/FEAT-001-demo
  [ "$status" -eq 0 ]
  [ "$output" = "created feat/FEAT-001-demo" ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feat/FEAT-001-demo" ]
}

@test "branch exists and is not current: switches → 'switched to <branch>'" {
  git -c commit.gpgsign=false checkout -q -b feat/FEAT-002-other
  git checkout -q main
  run bash "$ENSURE" feat/FEAT-002-other
  [ "$status" -eq 0 ]
  [ "$output" = "switched to feat/FEAT-002-other" ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feat/FEAT-002-other" ]
}

@test "idempotency: calling twice with the same branch is safe" {
  run bash "$ENSURE" feat/FEAT-003-twice
  [ "$status" -eq 0 ]
  [ "$output" = "created feat/FEAT-003-twice" ]
  run bash "$ENSURE" feat/FEAT-003-twice
  [ "$status" -eq 0 ]
  [ "$output" = "on feat/FEAT-003-twice" ]
}

@test "dirty working tree blocks switch: exit 3 with 'error: uncommitted changes'" {
  # Create a target branch whose checkout would overwrite local edits.
  git -c commit.gpgsign=false checkout -q -b feat/FEAT-004-dirty
  echo "changed on branch" > README.md
  git add README.md
  git -c commit.gpgsign=false commit -q -m "branch change"
  git checkout -q main
  # Now modify README on main so switching to feat/FEAT-004-dirty would overwrite it.
  echo "local edit" > README.md
  run bash "$ENSURE" feat/FEAT-004-dirty
  [ "$status" -eq 3 ]
  [[ "$output" == *"error: uncommitted changes"* ]]
  # Verify we did NOT switch — still on main, and local edit preserved.
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
  [ "$(cat README.md)" = "local edit" ]
}

@test "missing arg: exit 2" {
  run bash "$ENSURE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
}
