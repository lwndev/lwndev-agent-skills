#!/usr/bin/env bats
# Bats fixture for resolve-pr-number.sh (FEAT-028 / FR-4).
#
# Covers:
#   * Subagent-output-file scanning: `#N` token, pull URL, multi-match
#     last-wins.
#   * `gh pr list` fallback: returns number, returns null/empty, returns
#     non-integer.
#   * `gh` unavailable (PATH shadowed with no binary) → [warn] + exit 1.
#   * Non-existent subagent file → skip to fallback.
#   * Missing <branch> arg → exit 2.
#
# Fixture strategy: each test builds a per-test mktemp dir, copies a
# stub-`gh` script into it, and prepends the stub dir to PATH. Tests that
# need `gh` unavailable set PATH to ONLY the stub dir (with no `gh`).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  RPR="${SCRIPT_DIR}/resolve-pr-number.sh"
  TMPDIR_TEST="$(mktemp -d)"
  STUB_DIR="${TMPDIR_TEST}/bin"
  mkdir -p "$STUB_DIR"
  # Preserve original PATH so we can restore per-test after manipulating it.
  ORIGINAL_PATH="$PATH"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Install a `gh` stub that echoes $STDOUT_FIXTURE and exits $EXIT_CODE.
# Both env vars are read at stub invocation time.
install_gh_stub() {
  local stdout_value="$1"
  local exit_code="${2:-0}"
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '${stdout_value}'
exit ${exit_code}
EOF
  chmod +x "${STUB_DIR}/gh"
  export PATH="${STUB_DIR}:${ORIGINAL_PATH}"
}

# Install an empty bin dir and set PATH to *only* it plus system essentials
# required for the script to run (bash, coreutils). The goal is `gh` not
# found. We include a minimal PATH subset that still resolves bash / grep /
# command builtins.
hide_gh() {
  # Build a filtered PATH excluding any directory that contains `gh`.
  local new_path=""
  local IFS=:
  for dir in $ORIGINAL_PATH; do
    if [ -n "$dir" ] && [ ! -x "${dir}/gh" ]; then
      if [ -z "$new_path" ]; then
        new_path="$dir"
      else
        new_path="${new_path}:${dir}"
      fi
    fi
  done
  export PATH="$new_path"
}

# ---- subagent-output scanning (happy path) ----------------------------------

@test "file with #232 token → stdout 232, exit 0" {
  # gh stub present but should not be called (step 1 wins).
  install_gh_stub "999"
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "file with full GitHub PR URL → stdout 232, exit 0" {
  install_gh_stub "999"
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-url.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "file with multiple #N tokens → last match wins" {
  install_gh_stub "999"
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-multi-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- fallback: gh pr list succeeds ------------------------------------------

@test "empty subagent file (no PR tokens) → gh pr list fallback returns 232" {
  install_gh_stub "232"
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-empty.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "no subagent file arg → gh pr list fallback returns 232" {
  install_gh_stub "232"
  run bash "$RPR" chore/CHORE-001-foo
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "non-existent subagent file → gh pr list fallback returns 232" {
  install_gh_stub "232"
  run bash "$RPR" chore/CHORE-001-foo "${TMPDIR_TEST}/does-not-exist.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- fallback: gh pr list returns nothing -----------------------------------

@test "no subagent file + gh pr list returns empty → exit 1, empty stdout" {
  install_gh_stub ""
  run bash "$RPR" chore/CHORE-001-foo
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "no subagent file + gh pr list returns literal 'null' → exit 1" {
  install_gh_stub "null"
  run bash "$RPR" chore/CHORE-001-foo
  [ "$status" -eq 1 ]
}

# ---- gh unavailable ---------------------------------------------------------

@test "gh missing on PATH → [warn] stderr, exit 1" {
  hide_gh
  local err_file="${TMPDIR_TEST}/err.log"
  run bash -c "bash '$RPR' chore/CHORE-001-foo 2>'$err_file'"
  [ "$status" -eq 1 ]
  grep -q '\[warn\] resolve-pr-number: gh unavailable' "$err_file"
}

@test "gh present but errors (nonzero exit) → [warn] stderr, exit 1" {
  # Simulate an unauthenticated gh that exits 1 and prints nothing useful.
  install_gh_stub "" 1
  local err_file="${TMPDIR_TEST}/err.log"
  run bash -c "bash '$RPR' chore/CHORE-001-foo 2>'$err_file'"
  [ "$status" -eq 1 ]
  grep -q '\[warn\] resolve-pr-number: gh unavailable' "$err_file"
}

# ---- error cases ------------------------------------------------------------

@test "missing <branch> arg → exit 2" {
  run bash "$RPR"
  [ "$status" -eq 2 ]
}
