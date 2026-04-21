#!/usr/bin/env bats
# Bats fixture for commit-work.sh (FR-8).
#
# Covers: happy path (staged file → commit → short SHA printed),
# nothing-staged (git failure → exit 1), invalid type (exit 2),
# missing args (exit 2), commit-message format verified via git log.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  COMMIT="${SCRIPT_DIR}/commit-work.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: stages via caller, commits, prints short SHA" {
  echo "hello" > a.txt
  git add a.txt
  run bash "$COMMIT" feat FEAT-020 "hello world"
  [ "$status" -eq 0 ]
  # Short SHA is the last line of output (7 hex chars typical).
  sha="$(printf '%s\n' "$output" | tail -n 1)"
  [[ "$sha" =~ ^[0-9a-f]{7,}$ ]]
  # Commit message matches expected format.
  msg="$(git log -1 --format=%s)"
  [ "$msg" = "feat(FEAT-020): hello world" ]
}

@test "nothing staged: git commit fails → exit 1" {
  # Must seed with an initial commit so `git commit` fails on "nothing to commit"
  # rather than "no branch" errors.
  echo "seed" > seed.txt
  git add seed.txt
  git commit -q -m "seed"
  run bash "$COMMIT" feat FEAT-020 "nothing staged"
  [ "$status" -eq 1 ]
}

@test "invalid type: exit 2 with error" {
  run bash "$COMMIT" badtype FEAT-020 "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"invalid type"* ]]
}

@test "missing args: exit 2" {
  run bash "$COMMIT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
  run bash "$COMMIT" feat
  [ "$status" -eq 2 ]
  run bash "$COMMIT" feat FEAT-020
  [ "$status" -eq 2 ]
}

@test "commit message format verified via git log -1 --format=%s" {
  echo "x" > x.txt
  git add x.txt
  run bash "$COMMIT" chore deps "bump lodash to 4.17.21"
  [ "$status" -eq 0 ]
  msg="$(git log -1 --format=%s)"
  [ "$msg" = "chore(deps): bump lodash to 4.17.21" ]
}

@test "all twelve type-tokens accepted" {
  # Smoke-check each allowed type on a fresh commit.
  for t in chore fix feat qa docs test refactor perf style build ci revert; do
    f="file_${t}.txt"
    echo "$t" > "$f"
    git add "$f"
    run bash "$COMMIT" "$t" scope "desc for ${t}"
    [ "$status" -eq 0 ]
    msg="$(git log -1 --format=%s)"
    [ "$msg" = "${t}(scope): desc for ${t}" ]
  done
}
