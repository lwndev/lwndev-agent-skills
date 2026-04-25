#!/usr/bin/env bats
# Bats fixture for check-branch-diff.sh (FEAT-030 / FR-4).
#
# Covers:
#   * Non-empty diff vs. main → exit 0.
#   * Empty diff vs. main (branched off main with no edits) → exit 1.
#   * Detached HEAD with edits → exit code reflects diff result.
#   * Not in a git repo → exit 1.
#   * Extra args → exit 1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/check-branch-diff.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: init a repo with an initial commit on `main`.
init_repo() {
  git init -q
  git checkout -q -b main
  echo a > a.txt
  git add a.txt
  git -c user.email=t@t.test -c user.name=t commit -q -m init
}

@test "happy path — non-empty diff vs. main → exit 0" {
  init_repo
  git checkout -q -b feature
  echo b > b.txt
  git add b.txt
  git -c user.email=t@t.test -c user.name=t commit -q -m feat
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "empty diff — branch matches main → exit 1" {
  init_repo
  git checkout -q -b feature
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "empty diff while still on main → exit 1" {
  init_repo
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "detached HEAD with edits — propagates exit 0 when diff is non-empty" {
  init_repo
  git checkout -q -b feature
  echo b > b.txt
  git add b.txt
  git -c user.email=t@t.test -c user.name=t commit -q -m feat
  HEAD_SHA="$(git rev-parse HEAD)"
  git checkout -q --detach "$HEAD_SHA"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "no git repo → exit 1 with explicit error" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "no main branch and no origin/main → exit 1 with explicit error" {
  git init -q
  git checkout -q -b dev
  echo a > a.txt
  git add a.txt
  git -c user.email=t@t.test -c user.name=t commit -q -m init
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve 'main' or 'origin/main'"* ]]
}

@test "extra positional arg → exit 1" {
  init_repo
  run bash "$SCRIPT" extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"takes no arguments"* ]]
}
