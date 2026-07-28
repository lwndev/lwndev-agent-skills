#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Bats fixture for detect-phase.sh (FEAT-032 FR-4, BUG-023).
#
# Covers:
#   * ISSUES-FOUND + adoptedTests=[] → phase=fix
#   * post-fix PASS (attempts>0, adoptedTests=[], no qa-* files) → phase=adopt
#   * initial-PASS with un-adopted qa-* files (BUG-023) → phase=adopt
#   * initial-PASS with no qa-* files → phase=unknown (does NOT route to adopt)
#   * PASS + adoptedTests non-empty → phase=unknown (not adopt again)
#   * Missing args → exit 2

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  DETECT="${PLUGIN_DIR}/skills/addressing-qa-findings/scripts/detect-phase.sh"
  WS="${PLUGIN_DIR}/skills/orchestrating-workflows/scripts/workflow-state.sh"

  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
  # Real git repo so git ls-files can run without error.
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"
  printf 'placeholder\n' > "${TMPDIR_TEST}/README"
  git -C "$TMPDIR_TEST" add README
  git -C "$TMPDIR_TEST" commit -q -m "init"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Seed a state file with the FR-4 triple.
seed_state() {
  local id="$1"
  local verdict="$2"   # PASS | ISSUES-FOUND | null
  local attempts="$3"  # integer
  local adopted="$4"   # JSON array string, e.g. "[]"

  local verdict_json
  if [[ "$verdict" = "null" ]]; then
    verdict_json="null"
  else
    verdict_json="\"${verdict}\""
  fi

  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "bug",
  "currentStep": 0,
  "status": "in-progress",
  "pauseReason": null,
  "gate": null,
  "gateSetAt": null,
  "steps": [],
  "phases": {"total": 0, "completed": 0},
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-05-31T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "medium",
  "complexityStage": "init",
  "modelOverride": null,
  "modelSelections": [],
  "qaFixAttempts": ${attempts},
  "qaLastVerdict": ${verdict_json},
  "adoptedTests": ${adopted},
  "qaLoopCap": 2,
  "stateEvents": []
}
EOF
}

# ---- fix phase -----------------------------------------------------------------

@test "ISSUES-FOUND + adoptedTests=[] → phase=fix" {
  seed_state BUG-023 ISSUES-FOUND 0 "[]"
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=fix" ]
}

# ---- post-fix adopt (existing behavior, regression guard) ----------------------

@test "post-fix PASS (attempts=1, adoptedTests=[], no qa-* files) → phase=adopt" {
  seed_state BUG-023 PASS 1 "[]"
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=adopt" ]
}

# ---- initial-PASS with qa-* files (BUG-023) ------------------------------------

@test "BUG-023: initial-PASS (attempts=0) + committed qa-*.test.ts → phase=adopt" {
  seed_state BUG-023 PASS 0 "[]"
  mkdir -p "${TMPDIR_TEST}/tests/unit"
  printf 'test("edge", () => {});\n' > "${TMPDIR_TEST}/tests/unit/qa-BUG-023-edge.test.ts"
  git -C "$TMPDIR_TEST" add tests/unit/qa-BUG-023-edge.test.ts
  git -C "$TMPDIR_TEST" commit -q -m "add qa file"
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=adopt" ]
}

@test "BUG-023: initial-PASS (attempts=0) + committed qa-*.bats → phase=adopt" {
  seed_state BUG-023 PASS 0 "[]"
  mkdir -p "${TMPDIR_TEST}/tests/bats/qa"
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "${TMPDIR_TEST}/tests/bats/qa/qa-BUG-023-edge.bats"
  git -C "$TMPDIR_TEST" add tests/bats/qa/qa-BUG-023-edge.bats
  git -C "$TMPDIR_TEST" commit -q -m "add qa bats file"
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=adopt" ]
}

# ---- initial-PASS with NO qa-* files → phase=unknown (must NOT route to adopt) --

@test "BUG-023: initial-PASS (attempts=0) + no qa-* files → phase=unknown" {
  seed_state BUG-023 PASS 0 "[]"
  # No qa-* files — only the README from setup.
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=unknown" ]
}

# ---- post-adoption guard: adoptedTests non-empty → phase=unknown ---------------

@test "PASS + adoptedTests non-empty → phase=unknown (no re-adopt loop)" {
  seed_state BUG-023 PASS 1 '["tests/unit/foo.qa.test.ts"]'
  cd "$TMPDIR_TEST"
  run bash "$DETECT" BUG-023
  [ "$status" -eq 0 ]
  [ "$output" = "phase=unknown" ]
}

# ---- missing args --------------------------------------------------------------

@test "missing ID → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$DETECT"
  [ "$status" -eq 2 ]
}
