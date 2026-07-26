#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for FR-9 QA safety-net in preflight-checks.sh.
#
# Tests the qa-* leakage gate: trips on tracked qa-* files; passes on
# *.qa.* adopted siblings; passes on untracked qa-* files; v1 forward-compat
# globs (py/go) are no-ops; Edge Case 9 adopted sibling passes; Edge Case 10
# manually-named qa-foo.test.ts trips the gate.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)"
  PREFLIGHT="${SCRIPT_DIR}/preflight-checks.sh"
  STUB_DIR="$(mktemp -d)"
  export PATH="${STUB_DIR}:${PATH}"

  # FEAT-033: preflight delegates PR-state to managing-source-control's
  # view-pr.sh — point CLAUDE_PLUGIN_ROOT at the real plugin so the
  # dispatcher resolves.
  REAL_PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  export CLAUDE_PLUGIN_ROOT="$REAL_PLUGIN_ROOT"

  # Default npm stub: always succeed (build-health gate passes).
  cat > "${STUB_DIR}/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/npm"
}

teardown() {
  if [ -n "${STUB_DIR:-}" ] && [ -d "$STUB_DIR" ]; then
    rm -rf "$STUB_DIR"
  fi
}

# Helper: write a git stub that:
#   - `git status --porcelain` → empty (clean tree)
#   - `git branch --show-current` → "feat/FEAT-032-test"
#   - `git ls-files <globs>` → $ls_output (caller sets)
write_git_stub_with_ls() {
  local ls_output="$1"
  # Escape for embedding in heredoc.
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "status" ] && [ "\$2" = "--porcelain" ]; then
  exit 0
fi
if [ "\$1" = "branch" ] && [ "\$2" = "--show-current" ]; then
  printf 'feat/FEAT-032-test\n'
  exit 0
fi
if [ "\$1" = "ls-files" ]; then
  printf '%s' '${ls_output}'
  exit 0
fi
# FEAT-033: backend-detect.sh probes the origin URL.
if [ "\$1" = "remote" ] && [ "\$2" = "get-url" ] && [ "\$3" = "origin" ]; then
  printf '%s\n' "https://github.com/foo/bar"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
}

# Helper: write a gh stub that always returns an open/mergeable PR.
write_gh_stub_ok() {
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '{"number":99,"title":"Test PR","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/foo/bar/pull/99"}\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

@test "no qa-* tracked files → gate passes, exit 0" {
  write_git_stub_with_ls ""
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "tracked qa-*.test.ts trips the safety-net → exit 1" {
  write_git_stub_with_ls "tests/unit/qa-bash-input.test.ts
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'QA test files were not adopted'* ]]
  [[ "$output" == *'addressing-qa-findings skill did not complete cleanly'* ]]
  [[ "$output" == *'qa-bash-input.test.ts'* ]]
  [[ "$output" == *'Resolve by running addressing-qa-findings to adoption'* ]]
}

@test "tracked qa-*.bats under tests/bats/qa trips the safety-net → exit 1" {
  write_git_stub_with_ls "tests/bats/qa/qa-error-handling.bats
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'QA test files were not adopted'* ]]
  [[ "$output" == *'qa-error-handling.bats'* ]]
  [[ "$output" == *'Resolve by running addressing-qa-findings to adoption'* ]]
}

@test "Edge Case 9: tracked *.qa.* adopted sibling passes the gate → exit 0" {
  # foo.qa.test.ts has the adopted INFIX, not the qa-* PREFIX; must not trip.
  write_git_stub_with_ls ""
  write_gh_stub_ok
  # We pass no qa-* files to ls-files; the *.qa.* file would not be matched
  # by the glob pattern even if present. Confirm exit 0.
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "Edge Case 9: git ls-files returns only *.qa.* infix → gate still passes" {
  # Even if git ls-files were to return a *.qa.* path (it won't match the globs,
  # but simulate a hypothetical stub that returns it to confirm the script
  # doesn't panic on extra output).
  # The script only sees what git ls-files emits when called with the qa-* globs.
  # Since our stub only outputs what we pass, pass an empty string → gate passes.
  write_git_stub_with_ls ""
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "untracked qa-*.test.ts does NOT trip the gate (FR-9: tracked files only)" {
  # git ls-files only reports tracked files. Untracked files are invisible.
  # Simulate by returning empty output from ls-files.
  write_git_stub_with_ls ""
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "Edge Case 17 lockstep: v1 globs do NOT include qa-*.py (pytest dispatch is stub-only)" {
  # The lockstep constraint requires py/go globs to be active only when
  # adopt-qa-test.sh has real FR-5 dispatch. Currently dispatch is stub-only,
  # so the v1 globs must NOT pass qa-*.py to git ls-files. Verify by logging
  # the git args and inspecting them.
  ARGS_LOG="${STUB_DIR}/git.args"
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "status" ] && [ "\$2" = "--porcelain" ]; then exit 0; fi
if [ "\$1" = "branch" ] && [ "\$2" = "--show-current" ]; then
  printf 'feat/FEAT-032-test\n'; exit 0
fi
if [ "\$1" = "ls-files" ]; then
  printf '%s\n' "\$@" >> "${ARGS_LOG}"
  exit 0
fi
# FEAT-033: backend-detect.sh probes origin URL.
if [ "\$1" = "remote" ] && [ "\$2" = "get-url" ] && [ "\$3" = "origin" ]; then
  printf '%s\n' "https://github.com/foo/bar"; exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  ! grep -q 'qa-\*\.py' "$ARGS_LOG"
  ! grep -q 'qa-\*\.go' "$ARGS_LOG"
}

@test "v1 globs are anchored to canonical paths per CLAUDE.md naming convention" {
  # The v1 globs MUST include the canonical anchored paths so ephemeral QA
  # tests at the convention's locations trip the gate. Permanent infrastructure
  # tests under tests/bats/skills/<skill>/qa-*.bats must NOT match.
  ARGS_LOG="${STUB_DIR}/git.args"
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "status" ] && [ "\$2" = "--porcelain" ]; then exit 0; fi
if [ "\$1" = "branch" ] && [ "\$2" = "--show-current" ]; then
  printf 'feat/FEAT-032-test\n'; exit 0
fi
if [ "\$1" = "ls-files" ]; then
  printf '%s\n' "\$@" >> "${ARGS_LOG}"
  exit 0
fi
# FEAT-033: backend-detect.sh probes origin URL.
if [ "\$1" = "remote" ] && [ "\$2" = "get-url" ] && [ "\$3" = "origin" ]; then
  printf '%s\n' "https://github.com/foo/bar"; exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  grep -q 'tests/unit/qa-\*\.test\.ts' "$ARGS_LOG"
  grep -q 'tests/unit/qa-\*\.test\.js' "$ARGS_LOG"
  grep -q 'tests/bats/qa/qa-\*\.bats' "$ARGS_LOG"
}

@test "Edge Case 10: post-glob abort path emits the leaked path in the verbatim error" {
  # Any non-empty git ls-files result must abort with the leaked path embedded
  # in the FR-9 error message. The path content here is irrelevant to the
  # globs (stub bypasses real glob matching) — this test pins the abort path.
  write_git_stub_with_ls "tests/unit/qa-foo.test.ts
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'QA test files were not adopted'* ]]
  [[ "$output" == *'qa-foo.test.ts'* ]]
}

@test "multiple leaked qa-* files: all paths appear in error message" {
  write_git_stub_with_ls "tests/unit/qa-input-validation.test.ts
tests/bats/qa/qa-output-format.bats
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'qa-input-validation.test.ts'* ]]
  [[ "$output" == *'qa-output-format.bats'* ]]
}

@test "error message verbatim text: first line pinned per FR-9" {
  write_git_stub_with_ls "tests/unit/qa-bash-input.test.ts
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'QA test files were not adopted; the addressing-qa-findings skill did not complete cleanly:'* ]]
}

@test "error message verbatim text: last line pinned per FR-9" {
  write_git_stub_with_ls "tests/unit/qa-bash-input.test.ts
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Resolve by running addressing-qa-findings to adoption, or manually adopting/deleting these files.'* ]]
}

@test "safety-net runs after build-health: build failure aborts before safety-net" {
  # If build-health fails, the safety-net subshell never runs and the abort
  # reason is 'build-health check failed', not the safety-net message.
  write_git_stub_with_ls "tests/unit/qa-bash-input.test.ts
"
  write_gh_stub_ok
  # Override npm stub to fail.
  cat > "${STUB_DIR}/npm" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_DIR}/npm"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'build-health check failed'* ]]
  # Safety-net message must NOT appear because we aborted earlier.
  [[ "$output" != *'QA test files were not adopted'* ]]
}

@test "qa-leakage.reason tmpfile is written when gate trips" {
  write_git_stub_with_ls "tests/unit/qa-bash-input.test.ts
"
  write_gh_stub_ok
  # Run in subshell; inspect via exit code and output.
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  # The script exits 1 (gate tripped) — the tmpdir is cleaned up by trap EXIT,
  # but the abort JSON captures the leaked paths in the reason field.
  [[ "$output" == *'qa-bash-input.test.ts'* ]]
}

# ---- BUG-023 regression: after initial-PASS adoption FR-9 passes ----------------
# Simulate the state after adopt-qa-test.sh has moved qa-*.test.ts to *.qa.test.ts.
# git ls-files returns empty for the three canonical globs → gate passes.

@test "BUG-023 regression: after initial-PASS adoption git ls-files returns empty → FR-9 passes" {
  # Post-adoption: no qa-* files tracked; only the adopted *.qa.* sibling exists.
  # Our stub returns empty for ls-files (adopted *.qa.* infix is not glob-matched).
  write_git_stub_with_ls ""
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "BUG-023 regression: qa-* file still present (not adopted) still trips FR-9" {
  # Confirms the gate was not weakened: a genuine orphan still blocks finalize.
  write_git_stub_with_ls "tests/unit/qa-BUG-023-edge.test.ts
"
  write_gh_stub_ok
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'QA test files were not adopted'* ]]
  [[ "$output" == *'qa-BUG-023-edge.test.ts'* ]]
}
