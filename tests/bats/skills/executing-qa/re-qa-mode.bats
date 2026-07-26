#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# FEAT-032 FR-3 — re-QA mode auto-detection (detect-re-qa-mode.sh) + FR-13
# negative invariant (re-QA never deletes QA files).
# BUG-022 — state-cross-check: detect uses qaFixAttempts/qaLastVerdict, not marker.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/executing-qa/scripts" && pwd)"
  SCRIPT="${SCRIPT_DIR}/detect-re-qa-mode.sh"
  WFSTATE="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: init workflow state for an ID so get-qa-state succeeds.
_wf_init() {
  local id="$1"
  bash "$WFSTATE" init "$id" bug >/dev/null
}

# Helper: set genuine prior-run state (qaFixAttempts=1, qaLastVerdict=ISSUES-FOUND).
_wf_set_prior_run() {
  local id="$1"
  _wf_init "$id"
  bash "$WFSTATE" inc-qa-fix-attempts "$id" >/dev/null
  bash "$WFSTATE" set-qa-verdict "$id" ISSUES-FOUND >/dev/null
}

# --- arg validation ---------------------------------------------------------

@test "no args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "empty ID -> exit 2" {
  run bash "$SCRIPT" ""
  [ "$status" -eq 2 ]
}

# --- mode detection ---------------------------------------------------------

@test "no marker, no QA files -> mode=initial" {
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
  echo "$output" | jq -e '.files | length == 0' >/dev/null
}

@test "marker present, no QA files tracked -> mode=initial (skip)" {
  mkdir -p .sdlc/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "no marker, QA files tracked -> mode=initial (skip)" {
  mkdir -p tests/unit
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# BUG-022: genuine prior run (qaFixAttempts>=1) + committed QA .test.ts -> re-qa
@test "prior run state + tracked QA .test.ts -> mode=re-qa" {
  _wf_set_prior_run FEAT-100
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files | length == 1' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/unit/qa-foo.test.ts"' >/dev/null
}

# BUG-022: genuine prior run + committed QA .test.js -> re-qa
@test "prior run state + tracked QA .test.js -> mode=re-qa" {
  _wf_set_prior_run FEAT-100
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.js
  git add tests/unit/qa-foo.test.js
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/unit/qa-foo.test.js"' >/dev/null
}

# BUG-022: genuine prior run + committed QA .bats -> re-qa
@test "prior run state + tracked QA .bats under tests/bats/qa/ -> mode=re-qa" {
  _wf_set_prior_run FEAT-100
  mkdir -p .sdlc/qa tests/bats/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "@test 'a' { :; }" > tests/bats/qa/qa-foo.bats
  git add tests/bats/qa/qa-foo.bats
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/bats/qa/qa-foo.bats"' >/dev/null
}

@test "marker + UNTRACKED QA file -> mode=initial (FR-3 tracked-files only)" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// untracked" > tests/unit/qa-foo.test.ts
  # don't git add
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "forward-compat .py / .go are NO-OPS in v1 — even with marker, mode=initial" {
  mkdir -p .sdlc/qa tests/python pkg/validate
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "def t(): pass" > tests/python/qa_input.py
  echo "package x" > pkg/validate/qa_input_test.go
  git add tests/python/qa_input.py pkg/validate/qa_input_test.go
  git commit -q -m "qa(FEAT-100): py+go (v1 no-op)"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  # v1 globs only catch .test.ts / .test.js / .bats
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# BUG-022: genuine prior run + multiple tracked QA files -> re-qa with all files
@test "prior run state + multiple tracked QA files -> mode=re-qa with all files in array" {
  _wf_set_prior_run FEAT-100
  mkdir -p .sdlc/qa tests/unit tests/bats/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// a" > tests/unit/qa-a.test.ts
  echo "// b" > tests/unit/qa-b.test.ts
  echo "@test x { :; }" > tests/bats/qa/qa-c.bats
  git add tests/unit/qa-a.test.ts tests/unit/qa-b.test.ts tests/bats/qa/qa-c.bats
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files | length == 3' >/dev/null
}

# --- BUG-022 regression: false-positive case --------------------------------

# Fresh ID (qaFixAttempts==0, qaLastVerdict==null) + committed qa-* files +
# marker present -> must resolve mode=initial (not re-qa).
@test "BUG-022: fresh ID + committed qa-* files + marker -> mode=initial (not re-qa)" {
  # Init state with zero attempts, null verdict (fresh workflow).
  _wf_init FEAT-200
  mkdir -p .sdlc/qa tests/unit
  # Marker present (as it would be after qa-baseline.sh init runs before detect).
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-200
  # Committed qa-* files from an unrelated prior workflow.
  echo "// leftover from prior workflow" > tests/unit/qa-leftover.test.ts
  git add tests/unit/qa-leftover.test.ts
  git commit -q -m "qa(FEAT-111): leftover from prior workflow"
  run bash "$SCRIPT" FEAT-200
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# BUG-022 regression: true-positive case.
# Prior run (qaFixAttempts>=1 OR qaLastVerdict set) + committed qa-* files
# -> mode=re-qa (genuine re-QA path does not regress).
@test "BUG-022: prior run (qaFixAttempts=1) + committed qa-* files -> mode=re-qa" {
  _wf_set_prior_run FEAT-201
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-201
  echo "// qa test from prior run" > tests/unit/qa-fix1.test.ts
  git add tests/unit/qa-fix1.test.ts
  git commit -q -m "qa(FEAT-201): add fix1 tests"
  run bash "$SCRIPT" FEAT-201
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
}

# BUG-022 regression: qaLastVerdict set (PASS), qaFixAttempts=0
# -> still re-qa because qaLastVerdict is non-null.
@test "BUG-022: qaLastVerdict=PASS, qaFixAttempts=0 + committed qa-* files -> mode=re-qa" {
  _wf_init FEAT-202
  bash "$WFSTATE" set-qa-verdict FEAT-202 PASS >/dev/null
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-202
  echo "// qa test" > tests/unit/qa-pass.test.ts
  git add tests/unit/qa-pass.test.ts
  git commit -q -m "qa(FEAT-202): add pass tests"
  run bash "$SCRIPT" FEAT-202
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
}

# BUG-022 regression: fail-safe path — no state file at all -> mode=initial.
# Simulates running detect in an environment where workflow-state.sh can't find
# the state file (fresh branch with no .sdlc/workflows/).
@test "BUG-022: no state file (fail-safe) + committed qa-* files + marker -> mode=initial" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-203
  echo "// qa test" > tests/unit/qa-failsafe.test.ts
  git add tests/unit/qa-failsafe.test.ts
  git commit -q -m "qa(FEAT-203): add tests"
  # No workflow state initialized for FEAT-203 — get-qa-state will fail.
  run bash "$SCRIPT" FEAT-203
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# --- FR-13 negative invariant: detect doesn't delete files ------------------

@test "FR-13: detect-re-qa-mode.sh never deletes QA files" {
  _wf_set_prior_run FEAT-100
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa: add"
  before="$(git ls-files tests/unit/ | wc -l | tr -d ' ')"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  after="$(git ls-files tests/unit/ | wc -l | tr -d ' ')"
  [ "$before" -eq "$after" ]
  [ -f tests/unit/qa-foo.test.ts ]
}
