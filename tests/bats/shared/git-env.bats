#!/usr/bin/env bats
# Bats fixture for tests/bats/helpers/git-env.bash (issue #326).
#
# The helper is the Bats-side half of the git-env isolation fix. Coverage that
# every Bats file actually loads it lives in tests/unit/git-env-isolation.test.ts;
# this file covers the helper's own behaviour.

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

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

@test "sourcing the helper survives an exported readonly GIT_* variable" {
  # Bats sources test files under `set -e` and the helper self-invokes on load,
  # so a non-zero unset aborts every fixture in the repo at gather time. A
  # readonly GIT_* var (a profile pinning GIT_EDITOR, a CI wrapper) is the
  # realistic trigger.
  #
  # Shape matters, and an earlier version of this test had it wrong on both
  # counts: it ran `bash -c` without `-e`, and declared the readonly AFTER the
  # source, so the only invocation that matters — the self-invoking call at
  # file scope — ran against a clean env. It passed against a helper with the
  # `|| true` deleted, i.e. it verified nothing. Mutation-checked: with
  # `sed 's/ || true//'` applied to the helper, this version fails.
  #
  # Exported, not just readonly: the variable must be visible to reach the
  # unset in the first place.
  run bash -e -c "export GIT_RO=1; readonly GIT_RO; source '${HELPER}'; echo survived"
  [ "$status" -eq 0 ]
  [[ "$output" == *"survived"* ]]
}

@test "loading the helper sanitizes with no explicit call" {
  # The keystone property: sourcing IS the sanitization. A fixture that only
  # loads the helper — no `sanitize_git_env` line — must still come up clean.
  probe="${BATS_TEST_TMPDIR}/load-only.bats"
  {
    echo '#!/usr/bin/env bats'
    echo "load '${HELPER%.bash}'"
    echo '@test "poison is gone at file scope" {'
    echo '  [ -z "${GIT_DIR+set}" ]'
    echo '}'
  } >"$probe"

  GIT_DIR=/poison/.git run bats "$probe"
  [ "$status" -eq 0 ]
}

@test "after sanitizing, a poisoned GIT_DIR no longer redirects git" {
  # The bug in one assertion: with GIT_DIR set, `git rev-parse --absolute-git-dir`
  # from a temp repo reports the POISONED repo. After sanitizing it reports the
  # temp repo, so every subsequent write lands in the fixture.
  #
  # Both repos live under BATS_TEST_TMPDIR, which bats removes for us. A bare
  # mktemp -d plus a trailing rm leaks two initialized repos into the system
  # temp dir on any run where an assertion above the cleanup fails.
  poison="${BATS_TEST_TMPDIR}/poison"
  work="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$poison" "$work"
  git -C "$poison" init -q -b main
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
}
