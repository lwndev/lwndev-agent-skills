#!/usr/bin/env bats
# Bats fixture for commit-qa-tests.sh (FEAT-030 / FR-8).
#
# Covers:
#   * Happy path — multiple files committed with canonical message.
#   * Single file with spaces in path.
#   * No-files-to-commit (already-staged-and-committed) → exit 1 with [info].
#   * Already-committed file passed again → exit 1.
#   * Missing args → exit 2.
#   * Non-existent path → exit 2.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/commit-qa-tests.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  init_repo
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

init_repo() {
  git init -q
  git checkout -q -b main
  echo a > a.txt
  git add a.txt
  git -c user.email=t@t.test -c user.name=t commit -q -m init
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.test
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.test
}

# --- Arg validation --------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "ID only (no files) → exit 2" {
  run bash "$SCRIPT" FEAT-030
  [ "$status" -eq 2 ]
}

@test "non-existent file path → exit 2" {
  run bash "$SCRIPT" FEAT-030 no-such-file.spec.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]]
}

# --- Happy path -----------------------------------------------------------

@test "multiple files committed with canonical message" {
  mkdir -p __tests__
  echo "// fail test 1" > __tests__/qa-one.spec.ts
  echo "// fail test 2" > __tests__/qa-two.spec.ts
  run bash "$SCRIPT" FEAT-030 __tests__/qa-one.spec.ts __tests__/qa-two.spec.ts
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-030): add executable QA tests from executing-qa run" ]
  # Files actually staged + committed.
  files="$(git show --name-only --pretty='' HEAD | sort)"
  [[ "$files" == *"__tests__/qa-one.spec.ts"* ]]
  [[ "$files" == *"__tests__/qa-two.spec.ts"* ]]
}

# --- Edge: spaces in path -------------------------------------------------

@test "single file with spaces in path is committed" {
  mkdir -p __tests__
  echo "// test" > "__tests__/qa with spaces.spec.ts"
  run bash "$SCRIPT" FEAT-030 "__tests__/qa with spaces.spec.ts"
  [ "$status" -eq 0 ]
  files="$(git show --name-only --pretty='' HEAD)"
  [[ "$files" == *"__tests__/qa with spaces.spec.ts"* ]]
}

# --- Edge: no files to commit --------------------------------------------

@test "passing an already-committed (unchanged) file → exit 1 with [info]" {
  mkdir -p __tests__
  echo "// test" > __tests__/qa-already.spec.ts
  git add __tests__/qa-already.spec.ts
  git -c user.email=t@t.test -c user.name=t commit -q -m "pre-commit test"
  run bash "$SCRIPT" FEAT-030 __tests__/qa-already.spec.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"no files to commit"* ]]
}

# --- Edge: not in a git repo ---------------------------------------------

@test "outside a git repo → exit 1" {
  cd "$TMPDIR_TEST"
  rm -rf .git
  echo "// test" > foo.spec.ts
  run bash "$SCRIPT" FEAT-030 foo.spec.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}
