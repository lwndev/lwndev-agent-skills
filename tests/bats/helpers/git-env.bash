#!/usr/bin/env bash
# Shared Bats helper: strip inherited git environment.
#
# An inherited GIT_DIR redirects every child `git` call at the real repository
# regardless of cwd. See the "Tests must never inherit git environment" bullet
# in CLAUDE.md for the full failure mode (issue #326).
#
# EVERY .bats file loads this, whether or not it currently uses git — the rule
# is unconditional so it cannot fail open on an indirect invocation such as
# "$REAL_GIT" init. Enforced by tests/unit/git-env-isolation.test.ts, which
# checks three properties of the load and nothing else: it runs on source (above
# the first setup()/@test block, outside any heredoc), its spec resolves here,
# and the spec is depth-independent. Quoting style is free.
#
# Loading this file IS the sanitization: the call at the bottom runs on source.
# That makes the property fail-closed by construction — there is no second line
# to forget, mis-order, or bury inside a function body where a regex guard
# would still see the token and report green.

# Unset every GIT_* variable in the current shell. Bats sources the test file
# before running its tests, so unsetting at file scope covers setup() and every
# test body. Variables a test exports itself afterwards are unaffected.
#
# `|| true` on the unset, not just `return 0` at the end: Bats sources test
# files under `set -e`, so a readonly GIT_* variable (a developer profile
# pinning GIT_EDITOR, a CI wrapper) would abort the load and take all of the
# file's tests down with an error naming this helper rather than the variable.
sanitize_git_env() {
  local __git_env_name
  for __git_env_name in ${!GIT_*}; do
    unset "$__git_env_name" 2>/dev/null || true
  done
  return 0
}

sanitize_git_env
