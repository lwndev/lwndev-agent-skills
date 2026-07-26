#!/usr/bin/env bats
# Bats fixture for tests/bats/helpers/git-env.bash (issue #326).
#
# The helper is the Bats-side half of the git-env isolation fix. Coverage that
# every Bats file actually loads it lives in tests/unit/git-env-isolation.test.ts;
# this file covers the helper's own behaviour.

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../helpers/git-env'
sanitize_git_env

setup() {
  HELPER="${BATS_TEST_DIRNAME}/../helpers/git-env.bash"
}

@test "helper file exists" {
  [ -f "$HELPER" ]
}

@test "sanitize_git_env unsets GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE" {
  export GIT_DIR=/somewhere/.git
  export GIT_WORK_TREE=/somewhere
  export GIT_INDEX_FILE=/somewhere/.git/index

  sanitize_git_env

  [ -z "${GIT_DIR+set}" ]
  [ -z "${GIT_WORK_TREE+set}" ]
  [ -z "${GIT_INDEX_FILE+set}" ]
}

@test "sanitize_git_env unsets arbitrary GIT_* names, not just a fixed list" {
  export GIT_SOME_FUTURE_VAR=x
  sanitize_git_env
  [ -z "${GIT_SOME_FUTURE_VAR+set}" ]
}

@test "sanitize_git_env leaves non-GIT_ variables alone" {
  export GITHUB_TOKEN=keepme
  export DIGIT_COUNT=3
  sanitize_git_env
  [ "$GITHUB_TOKEN" = "keepme" ]
  [ "$DIGIT_COUNT" = "3" ]
}

@test "sanitize_git_env is a no-op when no GIT_* vars are set" {
  sanitize_git_env
  run sanitize_git_env
  [ "$status" -eq 0 ]
}

@test "after sanitizing, a poisoned GIT_DIR no longer redirects git" {
  # The bug in one assertion: with GIT_DIR set, `git rev-parse --absolute-git-dir`
  # from a temp repo reports the POISONED repo. After sanitizing it reports the
  # temp repo, so every subsequent write lands in the fixture.
  poison="$(mktemp -d)"
  git -C "$poison" init -q -b main
  work="$(mktemp -d)"
  git -C "$work" init -q -b main

  export GIT_DIR="${poison}/.git"
  cd "$work"
  run git rev-parse --absolute-git-dir
  [ "$status" -eq 0 ]
  [[ "$output" == "$(cd "$poison" && pwd -P)"* ]]

  sanitize_git_env
  run git rev-parse --absolute-git-dir
  [ "$status" -eq 0 ]
  [[ "$output" == "$(cd "$work" && pwd -P)"* ]]

  rm -rf "$poison" "$work"
}
