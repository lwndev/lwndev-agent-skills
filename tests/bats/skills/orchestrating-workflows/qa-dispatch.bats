#!/usr/bin/env bats
# Bats fixture for qa-dispatch.sh (FEAT-032 FR-7, BUG-023).
#
# Covers:
#   * FR-7 row 1a: initial-run PASS with un-adopted qa-* files → dispatch=adopt-phase (BUG-023)
#   * FR-7 row 1b: initial-run PASS with no qa-* files → dispatch=advance
#   * FR-7 row 2: EXPLORATORY-ONLY → dispatch=advance
#   * FR-7 row 3: ISSUES-FOUND + qaFixAttempts < qaLoopCap → dispatch=fix-phase
#   * FR-7 row 4: ISSUES-FOUND + qaFixAttempts >= qaLoopCap → dispatch=pause:qa-loop-exhausted
#   * FR-7 row 5: post-fix PASS + adoptedTests empty → dispatch=adopt-phase
#   * FR-7 row 6: post-adopt PASS (adoptedTests non-empty) → dispatch=advance
#   * FR-7 row 7: ERROR → dispatch=pause:qa-error
#   * No infinite loop after initial-PASS adoption (adoptedTests>0) → advance even with stray qa-* file
#   * --explain flag emits to stderr
#   * Missing args → exit 2

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  QD="${SCRIPT_DIR}/qa-dispatch.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
  # Initialize a real git repo so the git ls-files presence-check works.
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"
  # Commit a placeholder so HEAD exists.
  printf 'placeholder\n' > "${TMPDIR_TEST}/README"
  git -C "$TMPDIR_TEST" add README
  git -C "$TMPDIR_TEST" commit -q -m "init"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Seed a fully-migrated state file with explicit QA fields.
seed_qa_state() {
  local id="$1"
  local qa_fix_attempts="${2:-0}"
  local qa_last_verdict="${3:-null}"
  local adopted_tests="${4:-[]}"
  local qa_loop_cap="${5:-2}"

  if [ "$qa_last_verdict" = "null" ]; then
    verdict_json="null"
  else
    verdict_json="\"${qa_last_verdict}\""
  fi

  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "feature",
  "currentStep": 0,
  "status": "in-progress",
  "pauseReason": null,
  "gate": null,
  "gateSetAt": null,
  "steps": [
    {"name":"Doc","skill":"documenting-features","context":"main","status":"in-progress","artifact":null,"completedAt":null}
  ],
  "phases": {"total": 0, "completed": 0},
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-04-23T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "medium",
  "complexityStage": "init",
  "modelOverride": null,
  "modelSelections": [],
  "qaFixAttempts": ${qa_fix_attempts},
  "qaLastVerdict": ${verdict_json},
  "adoptedTests": ${adopted_tests},
  "qaLoopCap": ${qa_loop_cap},
  "stateEvents": []
}
EOF
}

# ---- FR-7 row 1a: initial-run PASS WITH un-adopted qa-* files (BUG-023) ---------

@test "BUG-023 FR-7 row 1a: initial-run PASS + un-adopted qa-*.test.ts → dispatch=adopt-phase" {
  seed_qa_state FEAT-032 0 PASS
  # Commit a qa-* file so git ls-files sees it.
  mkdir -p "${TMPDIR_TEST}/tests/unit"
  printf 'test("edge", () => {});\n' > "${TMPDIR_TEST}/tests/unit/qa-BUG-023-edge.test.ts"
  git -C "$TMPDIR_TEST" add tests/unit/qa-BUG-023-edge.test.ts
  git -C "$TMPDIR_TEST" commit -q -m "add qa file"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=adopt-phase" ]
}

@test "BUG-023 FR-7 row 1a: initial-run PASS + un-adopted qa-*.bats → dispatch=adopt-phase" {
  seed_qa_state FEAT-032 0 PASS
  mkdir -p "${TMPDIR_TEST}/tests/bats/qa"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "${TMPDIR_TEST}/tests/bats/qa/qa-BUG-023-edge.bats"
  git -C "$TMPDIR_TEST" add tests/bats/qa/qa-BUG-023-edge.bats
  git -C "$TMPDIR_TEST" commit -q -m "add qa bats file"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=adopt-phase" ]
}

# ---- FR-7 row 1b: initial-run PASS with no qa-* files → advance -----------------

@test "FR-7 row 1b: initial-run PASS (qaFixAttempts=0) + no qa-* files → dispatch=advance" {
  seed_qa_state FEAT-032 0 PASS
  # No qa-* files committed — only the README from setup().
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
}

# ---- No infinite loop: adoptedTests>0 → advance even with stray qa-* file ------

@test "BUG-023 no-loop guard: initial-PASS adoptedTests>0 → advance (loop termination)" {
  # After adoption, adoptedTests is non-empty. Even if a stray qa-* file were
  # somehow present, the adoptedTests>0 guard must win and return advance.
  seed_qa_state FEAT-032 0 PASS '["tests/unit/foo.qa.test.ts"]'
  mkdir -p "${TMPDIR_TEST}/tests/unit"
  printf 'test("edge", () => {});\n' > "${TMPDIR_TEST}/tests/unit/qa-stray.test.ts"
  git -C "$TMPDIR_TEST" add tests/unit/qa-stray.test.ts
  git -C "$TMPDIR_TEST" commit -q -m "add stray qa file"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
}

# ---- FR-7 row 2: EXPLORATORY-ONLY -----------------------------------------------

@test "FR-7 row 2: EXPLORATORY-ONLY → dispatch=advance" {
  seed_qa_state FEAT-032 0 EXPLORATORY-ONLY
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
}

# ---- FR-7 row 3: ISSUES-FOUND under cap → fix-phase ----------------------------

@test "FR-7 row 3: ISSUES-FOUND qaFixAttempts=0 < cap=2 → dispatch=fix-phase" {
  seed_qa_state FEAT-032 0 ISSUES-FOUND
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=fix-phase" ]
}

@test "FR-7 row 3: ISSUES-FOUND qaFixAttempts=1 < cap=2 → dispatch=fix-phase" {
  seed_qa_state FEAT-032 1 ISSUES-FOUND
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=fix-phase" ]
}

# ---- FR-7 row 4: ISSUES-FOUND at cap → pause:qa-loop-exhausted -----------------

@test "FR-7 row 4: ISSUES-FOUND qaFixAttempts=2 >= cap=2 → dispatch=pause:qa-loop-exhausted" {
  seed_qa_state FEAT-032 2 ISSUES-FOUND
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=pause:qa-loop-exhausted" ]
}

@test "FR-7 row 4: ISSUES-FOUND qaFixAttempts=3 > cap=2 → dispatch=pause:qa-loop-exhausted" {
  seed_qa_state FEAT-032 3 ISSUES-FOUND
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=pause:qa-loop-exhausted" ]
}

@test "FR-7 row 4: ISSUES-FOUND with elevated cap (qaFixAttempts=2 < cap=3) → dispatch=fix-phase" {
  seed_qa_state FEAT-032 2 ISSUES-FOUND "[]" 3
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=fix-phase" ]
}

# ---- FR-7 row 5: post-fix PASS, adoptedTests empty → adopt-phase ---------------

@test "FR-7 row 5: post-fix PASS qaFixAttempts=1 adoptedTests=empty → dispatch=adopt-phase" {
  seed_qa_state FEAT-032 1 PASS "[]"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=adopt-phase" ]
}

# ---- FR-7 row 6: post-adopt PASS, adoptedTests non-empty → advance -------------

@test "FR-7 row 6: post-adopt PASS qaFixAttempts=1 adoptedTests non-empty → dispatch=advance" {
  seed_qa_state FEAT-032 1 PASS '["tests/unit/foo.qa.test.ts"]'
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
}

# ---- FR-7 row 7: ERROR → pause:qa-error ----------------------------------------

@test "FR-7 row 7: ERROR → dispatch=pause:qa-error" {
  seed_qa_state FEAT-032 0 ERROR
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=pause:qa-error" ]
}

# ---- --explain flag ------------------------------------------------------------

@test "--explain emits context line to stderr, dispatch still on stdout" {
  seed_qa_state FEAT-032 0 PASS
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032 --explain
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
  [[ "$stderr" == *"advance"* ]]
}

# ---- missing args / bad args ---------------------------------------------------

@test "missing ID → exit 2" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD"
  [ "$status" -eq 2 ]
}

@test "invalid ID format → exit 2" {
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" invalid-id
  [ "$status" -eq 2 ]
}

# ---- migration path: pre-FEAT-032 state file does not contaminate JSON capture ---
# Regression: get-qa-state writes a `[workflow-state] debug: migrating ...` line
# to stderr on first read of an unmigrated state file. qa-dispatch must capture
# stderr separately so that line does not break the `jq -e 'type == "object"'`
# guard on the qa_json output.

@test "unmigrated state file (missing qa-loop fields) → migration debug stays out of JSON capture, dispatch=advance" {
  cat > "${TMPDIR_TEST}/.sdlc/workflows/FEAT-032.json" <<'EOF'
{
  "id": "FEAT-032",
  "type": "feature",
  "currentStep": 0,
  "status": "in-progress",
  "pauseReason": null,
  "steps": [
    {"name":"Doc","skill":"documenting-features","context":"main","status":"in-progress","artifact":null,"completedAt":null}
  ],
  "phases": {"total": 0, "completed": 0},
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-04-23T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "medium",
  "complexityStage": "init"
}
EOF
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$QD" FEAT-032
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]
  [[ "$stderr" == *"migrating"* ]]
}
