#!/usr/bin/env bats
# Bats fixture for verify-phase-deliverables.sh (FEAT-027 / FR-4).
#
# Uses PATH-shadowing stubs for `npm` to cover:
#   - graceful degradation when `npm` is absent from PATH
#   - successful test/build/coverage runs via a happy-path stub
#   - failing runs (surfacing tail-50 output only on failure)
#
# Follows the stub pattern from
# plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats:
# per-test setup/teardown with fixture-local FIXTURE_DIR via mktemp -d, inline
# PATH="${FIXTURE_DIR}/stubs:${PATH}" on each `run` call, parent-shell PATH
# never mutated.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/verify-phase-deliverables.sh"
  FIXTURE_SRC="${BATS_TEST_DIRNAME}/fixtures/verify-deliverables-plan.md"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  NOGH_DIR="${FIXTURE_DIR}/nonpm"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR" "$NOGH_DIR"
  : > "$TRACER"
  export TRACER

  # Hermetic work dir so file-existence probes resolve against fixture files.
  TEST_CWD="${FIXTURE_DIR}/work"
  mkdir -p "${TEST_CWD}/src"
  cp "$FIXTURE_SRC" "${TEST_CWD}/plan.md"
  cd "$TEST_CWD"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- stub writers ----------

write_npm_stub() {
  # NPM_TEST_RC        — exit for `npm test`        (default 0)
  # NPM_TEST_OUT       — stdout/stderr payload
  # NPM_BUILD_RC       — exit for `npm run build`   (default 0)
  # NPM_BUILD_OUT      — stdout/stderr payload
  # NPM_COVERAGE_RC    — exit for `npm run test:coverage` (default 0)
  # NPM_COVERAGE_OUT   — stdout/stderr payload
  cat > "${STUB_DIR}/npm" <<'EOF'
#!/usr/bin/env bash
printf 'TRACE:npm:%s\n' "$*" >> "${TRACER}"
case "$1" in
  test)
    printf '%s' "${NPM_TEST_OUT:-npm-test-ok}"
    exit "${NPM_TEST_RC:-0}"
    ;;
  run)
    case "$2" in
      build)
        printf '%s' "${NPM_BUILD_OUT:-npm-build-ok}"
        exit "${NPM_BUILD_RC:-0}"
        ;;
      test:coverage)
        printf '%s' "${NPM_COVERAGE_OUT:-npm-cov-ok}"
        exit "${NPM_COVERAGE_RC:-0}"
        ;;
    esac
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/npm"
}

# PATH directory without npm (but with the real POSIX toolchain the script needs).
empty_path_for_no_npm() {
  local dir="${NOGH_DIR}"
  for bin in bash env awk sed grep tr cut wc mktemp head tail cat printf chmod rm mkdir ls test dirname basename sort jq uniq compgen true false; do
    if [ -x "/bin/$bin" ]; then
      ln -sf "/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -sf "/usr/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/opt/homebrew/bin/$bin" ]; then
      ln -sf "/opt/homebrew/bin/$bin" "$dir/$bin" 2>/dev/null || true
    fi
  done
  printf '%s' "$dir"
}

# =====================================================================
# Arg-validation
# =====================================================================

@test "missing args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: verify-phase-deliverables.sh"* ]]
}

@test "only one arg -> exit 2" {
  run bash "$SCRIPT" "plan.md"
  [ "$status" -eq 2 ]
}

@test "non-positive <phase-N> -> exit 2" {
  run bash "$SCRIPT" "plan.md" "0"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "non-integer <phase-N> -> exit 2" {
  run bash "$SCRIPT" "plan.md" "abc"
  [ "$status" -eq 2 ]
}

@test "non-existent plan file -> exit 1" {
  run bash "$SCRIPT" "nowhere.md" "1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found or unreadable"* ]]
}

@test "phase number not in plan -> exit 1" {
  write_npm_stub
  # Place the file for phase 1's first deliverable so no-file doesn't confuse things.
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "99"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase 99 not found"* ]]
}

# =====================================================================
# File-existence
# =====================================================================

@test "all extracted paths exist -> files.ok populated, files.missing empty, exit 0" {
  write_npm_stub
  : > src/alpha.ts
  : > src/beta.ts
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"src/alpha.ts"'* ]]
  [[ "$output" == *'"src/beta.ts"'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "one path missing -> files.missing populated, exit 1" {
  write_npm_stub
  : > src/alpha.ts
  # src/beta.ts deliberately absent.
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"missing":['* ]]
  [[ "$output" == *'"src/beta.ts"'* ]]
  # alpha is still counted as ok.
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"src/alpha.ts"'* ]]
}

@test "non-file deliverable (no leading backtick) is skipped from files checks" {
  write_npm_stub
  : > src/alpha.ts
  : > src/beta.ts
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [ "$status" -eq 0 ]
  # The non-file deliverable starts with `Documentation updated` — it must not
  # appear in files.ok or files.missing.
  [[ "$output" != *"Documentation updated"* ]]
}

# =====================================================================
# npm graceful-degradation
# =====================================================================

@test "npm absent from PATH -> test/build/coverage all skipped, [warn] to stderr, exit 0 when files present" {
  nonpm="$(empty_path_for_no_npm)"
  : > src/alpha.ts
  : > src/beta.ts
  err_file="${FIXTURE_DIR}/err"
  out_file="${FIXTURE_DIR}/out"
  PATH="$nonpm" bash "$SCRIPT" "plan.md" "1" 2>"$err_file" >"$out_file" || rc=$?
  rc=${rc:-0}
  out="$(cat "$out_file")"
  err="$(cat "$err_file")"
  [ "$rc" -eq 0 ]
  [[ "$err" == *"[warn] verify-phase-deliverables: npm not found"* ]]
  [[ "$out" == *'"test":"skipped"'* ]]
  [[ "$out" == *'"build":"skipped"'* ]]
  [[ "$out" == *'"coverage":"skipped"'* ]]
}

@test "npm absent + missing file -> exit 1 (files.missing triggers aggregate failure)" {
  nonpm="$(empty_path_for_no_npm)"
  : > src/alpha.ts
  # beta absent
  err_file="${FIXTURE_DIR}/err"
  out_file="${FIXTURE_DIR}/out"
  PATH="$nonpm" bash "$SCRIPT" "plan.md" "1" 2>"$err_file" >"$out_file" || rc=$?
  rc=${rc:-0}
  out="$(cat "$out_file")"
  [ "$rc" -eq 1 ]
  [[ "$out" == *'"missing":['* ]]
}

# =====================================================================
# Coverage heuristic
# =====================================================================

@test "phase with no coverage token -> coverage skipped" {
  write_npm_stub
  : > src/delta.ts
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "3"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"coverage":"skipped"'* ]]
  # Confirm the coverage command was NOT invoked.
  run cat "${TRACER}"
  [[ "$output" != *"TRACE:npm:run test:coverage"* ]]
}

@test "phase with coverage token (80%) -> test:coverage invoked" {
  write_npm_stub
  : > src/gamma.ts
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"coverage":"pass"'* ]]
  run cat "${TRACER}"
  [[ "$output" == *"TRACE:npm:run test:coverage"* ]]
}

# =====================================================================
# JSON shape
# =====================================================================

@test "output keys present only for failing checks" {
  write_npm_stub
  : > src/alpha.ts
  : > src/beta.ts
  # Happy path: all pass.
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [ "$status" -eq 0 ]
  # output object must be empty {} when everything passes.
  [[ "$output" == *'"output":{}'* ]]
}

@test "failing npm test -> output.test populated, build/coverage not invoked" {
  : > src/alpha.ts
  : > src/beta.ts
  write_npm_stub
  NPM_TEST_RC=1 NPM_TEST_OUT="FAIL: suite crashed" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"test":"fail"'* ]]
  [[ "$output" == *'"build":"skipped"'* ]]
  [[ "$output" == *"FAIL: suite crashed"* ]]
  # Ensure build was not called after test failed.
  run cat "${TRACER}"
  [[ "$output" != *"TRACE:npm:run build"* ]]
}

@test "files.ok and files.missing always present in JSON" {
  write_npm_stub
  : > src/alpha.ts
  : > src/beta.ts
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "plan.md" "1"
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"missing":'* ]]
}
