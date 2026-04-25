#!/usr/bin/env bats
# Bats fixture for resolve-pr-number.sh (FEAT-028 / FR-4).
#
# Covers:
#   * gh pr list primary: length==1 wins; length 0 or 2+ falls through.
#   * Subagent-output fallback: `#N` token, pull URL, multi-match line-order
#     last-wins, fenced-code-block filter (P0 — issue from PR #233 review).
#   * `gh` or `jq` unavailable → skip primary, parse, warn on exit-1.
#   * Non-existent subagent file → skip to fallback.
#   * Missing <branch> arg → exit 2.
#
# Fixture strategy: each test builds a per-test mktemp dir, copies a stub-`gh`
# script into it, and prepends the stub dir to PATH. The stub emits a JSON
# array shape (matching `gh pr list --json number --limit 2`). Tests that
# need `gh` unavailable set PATH to a dir without `gh`.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  RPR="${SCRIPT_DIR}/resolve-pr-number.sh"
  TMPDIR_TEST="$(mktemp -d)"
  STUB_DIR="${TMPDIR_TEST}/bin"
  mkdir -p "$STUB_DIR"
  ORIGINAL_PATH="$PATH"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Install a `gh` stub that echoes $STDOUT_FIXTURE (a JSON array) and exits
# $EXIT_CODE. The script calls `gh pr list ... --json number --limit 2` so
# the expected shape is `[{"number":232}]` (length 1) or `[]` (length 0) or
# `[{"number":1},{"number":2}]` (length 2+).
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

# Build a filtered PATH excluding any directory that contains `gh`.
hide_gh() {
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

# ---- gh primary (happy path) ------------------------------------------------

@test "gh pr list returns 1 PR → use that number (skip parsing)" {
  # Subagent output has a misleading #999; gh authoritative must win.
  install_gh_stub '[{"number":232}]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "gh pr list returns 1 PR with no subagent file → use gh number" {
  install_gh_stub '[{"number":232}]'
  run bash "$RPR" chore/CHORE-001-foo
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- gh primary: 0 or 2+ results fall through to parsing --------------------

@test "gh pr list returns 0 results → fall through to subagent parsing" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "gh pr list returns 2+ results → fall through to subagent parsing" {
  install_gh_stub '[{"number":100},{"number":200}]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "gh pr list nonzero exit → fall through to subagent parsing" {
  install_gh_stub '' 1
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-url.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- subagent-output scanning (fallback) ------------------------------------

@test "fallback: file with #232 token → stdout 232, exit 0" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "fallback: file with full GitHub PR URL → stdout 232, exit 0" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-url.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "fallback: file with multiple #N tokens → last match in line-order wins" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-multi-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- fenced-code-block filter (P0 from PR #233 review) ----------------------

@test "fallback: #N inside fenced code block ignored; real #N outside wins" {
  install_gh_stub '[]'
  cat > "${TMPDIR_TEST}/exec-output-fenced.txt" <<'EOF'
Starting executing-chores.

Example from the docs:
```
Pull request created: #999
```

Pull request created: #232
EOF
  run bash "$RPR" chore/CHORE-001-foo "${TMPDIR_TEST}/exec-output-fenced.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

@test "fallback: #N only inside fenced block → no match, exit 1" {
  install_gh_stub '[]'
  cat > "${TMPDIR_TEST}/exec-output-fenced-only.txt" <<'EOF'
Docs example:
```
gh pr create ... → #999
```

(no real PR yet)
EOF
  run bash "$RPR" chore/CHORE-001-foo "${TMPDIR_TEST}/exec-output-fenced-only.txt"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "fallback: URL in line wins over later #N on later line" {
  install_gh_stub '[]'
  cat > "${TMPDIR_TEST}/exec-output-url-then-hash.txt" <<'EOF'
Creating PR
See issue #50 for context
Pull request created: https://github.com/lwndev/lwndev-marketplace/pull/232
EOF
  run bash "$RPR" chore/CHORE-001-foo "${TMPDIR_TEST}/exec-output-url-then-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- no-match paths ---------------------------------------------------------

@test "empty subagent file + gh returns empty array → exit 1, empty stdout" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-empty.txt"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "no subagent file + gh returns empty array → exit 1" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo
  [ "$status" -eq 1 ]
}

@test "non-existent subagent file + gh returns empty → exit 1" {
  install_gh_stub '[]'
  run bash "$RPR" chore/CHORE-001-foo "${TMPDIR_TEST}/does-not-exist.txt"
  [ "$status" -eq 1 ]
}

# ---- gh unavailable ---------------------------------------------------------

@test "gh missing on PATH + no subagent match → [warn] stderr, exit 1" {
  hide_gh
  local err_file="${TMPDIR_TEST}/err.log"
  run bash -c "bash '$RPR' chore/CHORE-001-foo 2>'$err_file'"
  [ "$status" -eq 1 ]
  grep -q '\[warn\] resolve-pr-number: gh unavailable' "$err_file"
}

@test "gh missing on PATH + subagent parse succeeds → use parsed number" {
  hide_gh
  run bash "$RPR" chore/CHORE-001-foo "${FIXTURES_DIR}/exec-output-with-hash.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "232" ]
}

# ---- error cases ------------------------------------------------------------

@test "missing <branch> arg → exit 2" {
  run bash "$RPR"
  [ "$status" -eq 2 ]
}
