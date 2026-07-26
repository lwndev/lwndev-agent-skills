#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats coverage for FEAT-032 / Phase 2 / FR-13 deletion-ownership invariant.
#
# `addressing-qa-findings/scripts/adopt-qa-test.sh` is the SOLE owner of
# QA-test deletion across the entire plugin. The move via `git mv` IS the
# deletion. No other surface under `plugins/lwndev-sdlc/` may delete any
# `qa-*` file via `rm`, `git rm`, or `git mv`.
#
# This test greps the plugin tree for any deletion-shaped reference to
# `qa-*` outside the addressing-qa-findings directory. Any hit fails the
# test.
#
# Negative-control: a deliberately-introduced violation under a temp fixture
# inside the plugin tree triggers the assertion failure as expected.

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
}

# --- happy path -------------------------------------------------------------

@test "FR-13: no script outside addressing-qa-findings deletes qa-* test files" {
  cd "$PLUGIN_DIR"
  # Search for shapes that delete or move a QA TEST file (qa-*.test.* or
  # qa-*.bats). The marker file `.executing-qa-baseline-{ID}` is NOT a QA
  # test file and is correctly cleaned by executing-qa/scripts/stop-hook.sh
  # — the regex below excludes it by requiring the qa- token to be followed
  # by something that resolves to a test file (`*.test.*` or `*.bats`).
  set +e
  hits="$(grep -rEn 'rm[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)|git[[:space:]]+rm[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)|git[[:space:]]+mv[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)' \
    --include='*.sh' --include='*.ts' --include='*.md' \
    . 2>/dev/null \
    | grep -v 'skills/addressing-qa-findings/' \
    || true)"
  set -e
  if [[ -n "$hits" ]]; then
    echo "FR-13 violation: deletion-shaped references to qa-* test files outside addressing-qa-findings:" >&2
    echo "$hits" >&2
    return 1
  fi
}

# --- negative control -------------------------------------------------------

@test "FR-13 negative-control: a planted violation under a temp fixture is detected" {
  # Create an isolated copy of the plugin tree minus addressing-qa-findings
  # under a tmpdir and plant a violation; assert grep finds it. This mirrors
  # the behavior of the happy-path grep against a real violation.
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/skills/some-skill/scripts"
  cat > "${TMPDIR_TEST}/skills/some-skill/scripts/violator.sh" <<'EOF'
#!/usr/bin/env bash
# Deliberately violates FR-13 for negative-control purposes.
git rm tests/unit/qa-input-validation.test.ts
EOF

  set +e
  hits="$(grep -rEn 'rm[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)|git[[:space:]]+rm[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)|git[[:space:]]+mv[[:space:]]+[^|;]*qa-[a-zA-Z][^[:space:]]*(\.test\.|\.bats)' \
    --include='*.sh' \
    "$TMPDIR_TEST" 2>/dev/null \
    | grep -v 'skills/addressing-qa-findings/' \
    || true)"
  set -e

  rm -rf "$TMPDIR_TEST"
  [ -n "$hits" ]
  [[ "$hits" == *"violator.sh"* ]]
  [[ "$hits" == *"qa-input-validation.test.ts"* ]]
}
