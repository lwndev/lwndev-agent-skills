#!/usr/bin/env bash
# Shared Bats helper: strip inherited git environment.
#
# An inherited GIT_DIR redirects every child `git` call at the real repository
# regardless of cwd. See the "Tests must never inherit git environment" bullet
# in CLAUDE.md for the full failure mode (issue #326).
#
# EVERY .bats file loads this and calls sanitize_git_env at file scope, whether
# or not it currently uses git — the rule is unconditional so it cannot fail
# open on an indirect invocation such as "$REAL_GIT" init. Enforced by
# tests/unit/git-env-isolation.test.ts.

# Unset every GIT_* variable in the current shell. Bats sources the test file
# before running its tests, so unsetting at file scope covers setup() and every
# test body. Variables a test exports itself afterwards are unaffected.
sanitize_git_env() {
  local __git_env_name
  for __git_env_name in ${!GIT_*}; do
    unset "$__git_env_name"
  done
}
