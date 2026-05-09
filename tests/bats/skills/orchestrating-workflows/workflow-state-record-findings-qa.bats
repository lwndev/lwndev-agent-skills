#!/usr/bin/env bats
# Bats fixture for workflow-state.sh record-findings --type qa (FEAT-030 FR-11).
#
# Covers:
#   * Happy-path persist for each verdict: PASS, ISSUES-FOUND, ERROR, EXPLORATORY-ONLY
#   * Reject malformed verdict (e.g., BROKEN) → exit 1 with verdict-enum error
#   * Reject negative counts → exit 1
#   * Reject non-integer counts → exit 1
#   * Reject missing arg → exit 2
#   * NFR-1 backward-compatibility: load a pre-FEAT-030 fixture lacking
#     `findings` block on QA step; subsequent record-findings --type qa adds it
#   * Reject stepIndex pointing to a non-QA step → exit 1
#   * Existing record-findings (no --type flag) continues to work — zero regression

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/../../../fixtures/orchestrating-workflows"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Copy a static state file fixture into the sandbox, renaming to <id>.json.
seed_state() {
  local fixture_name="$1"
  local id="$2"
  cp "${FIXTURES_DIR}/sdlc-workflows/${fixture_name}.json" "${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
}

# ---- Happy-path: PASS verdict -----------------------------------------------

@test "record-findings --type qa PASS verdict persists verdict/counts/summary" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings --type qa FEAT-030 8 PASS 12 0 0 "All tests passed."
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.steps[8].findings.verdict')
  [ "$verdict" = "PASS" ]
  local passed
  passed=$(echo "$output" | jq -r '.steps[8].findings.passed')
  [ "$passed" = "12" ]
  local failed
  failed=$(echo "$output" | jq -r '.steps[8].findings.failed')
  [ "$failed" = "0" ]
  local errored
  errored=$(echo "$output" | jq -r '.steps[8].findings.errored')
  [ "$errored" = "0" ]
  local summary
  summary=$(echo "$output" | jq -r '.steps[8].findings.summary')
  [ "$summary" = "All tests passed." ]
}

# ---- Happy-path: ISSUES-FOUND verdict ----------------------------------------

@test "record-findings --type qa ISSUES-FOUND verdict persists correctly" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings --type qa FEAT-030 8 ISSUES-FOUND 9 3 0 "3 tests failed."
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.steps[8].findings.verdict')
  [ "$verdict" = "ISSUES-FOUND" ]
  local failed
  failed=$(echo "$output" | jq -r '.steps[8].findings.failed')
  [ "$failed" = "3" ]
}

# ---- Happy-path: ERROR verdict -----------------------------------------------

@test "record-findings --type qa ERROR verdict persists correctly" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings --type qa FEAT-030 8 ERROR 0 0 1 "Runner crash."
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.steps[8].findings.verdict')
  [ "$verdict" = "ERROR" ]
  local errored
  errored=$(echo "$output" | jq -r '.steps[8].findings.errored')
  [ "$errored" = "1" ]
}

# ---- Happy-path: EXPLORATORY-ONLY verdict ------------------------------------

@test "record-findings --type qa EXPLORATORY-ONLY verdict persists correctly" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings --type qa FEAT-030 8 EXPLORATORY-ONLY 0 0 0 "No test framework."
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.steps[8].findings.verdict')
  [ "$verdict" = "EXPLORATORY-ONLY" ]
  local passed
  passed=$(echo "$output" | jq -r '.steps[8].findings.passed')
  [ "$passed" = "0" ]
}

# ---- Reject malformed verdict ------------------------------------------------

@test "record-findings --type qa rejects malformed verdict BROKEN → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 BROKEN 0 0 0 "summary"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict must be one of"* ]] || [[ "${output}" == *"PASS"* ]]
}

# ---- Reject negative counts --------------------------------------------------

@test "record-findings --type qa rejects negative passed count → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS -1 0 0 "summary"
  [ "$status" -eq 1 ]
}

@test "record-findings --type qa rejects negative failed count → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS 0 -1 0 "summary"
  [ "$status" -eq 1 ]
}

@test "record-findings --type qa rejects negative errored count → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS 0 0 -1 "summary"
  [ "$status" -eq 1 ]
}

# ---- Reject non-integer counts -----------------------------------------------

@test "record-findings --type qa rejects non-integer passed → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS abc 0 0 "summary"
  [ "$status" -eq 1 ]
}

@test "record-findings --type qa rejects non-integer failed → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS 0 1.5 0 "summary"
  [ "$status" -eq 1 ]
}

@test "record-findings --type qa rejects non-integer errored → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS 0 0 "two" "summary"
  [ "$status" -eq 1 ]
}

# ---- Reject missing arg -------------------------------------------------------

@test "record-findings --type qa with missing summary arg → exit 2" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  # Missing errored and summary — only 5 positional args provided.
  run bash "$WS" record-findings --type qa FEAT-030 8 PASS 0
  [ "$status" -eq 2 ]
}

# ---- NFR-1: backward-compatibility with pre-FEAT-030 fixture -----------------

@test "NFR-1: pre-FEAT-030 fixture lacking findings block — record-findings --type qa adds it" {
  seed_state "CHORE-002-pre-feat030" "CHORE-002"
  cd "$TMPDIR_TEST"
  # QA step is at index 5 in CHORE-002 fixture.
  run --separate-stderr bash "$WS" record-findings --type qa CHORE-002 5 PASS 8 0 0 "All clean."
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.steps[5].findings.verdict')
  [ "$verdict" = "PASS" ]
  # Confirm findings key now exists.
  local has_findings
  has_findings=$(echo "$output" | jq '.steps[5] | has("findings")')
  [ "$has_findings" = "true" ]
}

# ---- Reject stepIndex pointing to non-QA step --------------------------------

@test "record-findings --type qa rejects stepIndex pointing to non-QA step → exit 1" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  # Step 1 is reviewing-requirements, not executing-qa.
  run bash "$WS" record-findings --type qa FEAT-030 1 PASS 0 0 0 "summary"
  [ "$status" -eq 1 ]
  [[ "$output" == *"executing-qa"* ]]
}

# ---- Zero-regression: existing record-findings (no --type flag) still works --

@test "zero-regression: record-findings without --type flag defaults to review type" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  # Step 1 is reviewing-requirements — valid for review type.
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 2 1 0 advanced "Minor warnings."
  [ "$status" -eq 0 ]
  local decision
  decision=$(echo "$output" | jq -r '.steps[1].findings.decision')
  [ "$decision" = "advanced" ]
  local errors
  errors=$(echo "$output" | jq -r '.steps[1].findings.errors')
  [ "$errors" = "2" ]
}

# ---- FEAT-032 FR-7a: pause-reason allow-list extension ----------------------
#
# The cmd_pause allow-list now accepts the four new QA-loop reasons in
# addition to the original three. The rejection message is pinned verbatim per
# FR-7a (load-bearing carve-out).

@test "FR-7a: pause qa-error → status=paused, pauseReason=qa-error" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 qa-error
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "paused" ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "qa-error" ]
}

@test "FR-7a: pause qa-loop-exhausted → status=paused, pauseReason=qa-loop-exhausted" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 qa-loop-exhausted
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "paused" ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "qa-loop-exhausted" ]
}

@test "FR-7a: pause fix-suite-failed → status=paused, pauseReason=fix-suite-failed" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 fix-suite-failed
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "paused" ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "fix-suite-failed" ]
}

@test "FR-7a: pause adoption-failed → status=paused, pauseReason=adoption-failed" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 adoption-failed
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "paused" ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "adoption-failed" ]
}

@test "FR-7a: existing reasons still accepted — pause plan-approval" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 plan-approval
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "plan-approval" ]
}

@test "FR-7a: existing reasons still accepted — pause pr-review" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 pr-review
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "pr-review" ]
}

@test "FR-7a: existing reasons still accepted — pause review-findings" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 review-findings
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.pauseReason')" = "review-findings" ]
}

@test "FR-7a: unknown pause reason → exit 1 with verbatim rejection message" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" pause FEAT-030 nonsense-reason
  [ "$status" -eq 1 ]
  # FR-7a load-bearing carve-out — message text pinned verbatim.
  # The NFR-3 migration debug line may precede the error; assert the rejection
  # message appears in stderr verbatim rather than asserting equality against
  # the full stderr blob.
  [[ "$stderr" == *"Error: Invalid pause reason 'nonsense-reason'. Expected one of: plan-approval, pr-review, review-findings, qa-error, qa-loop-exhausted, fix-suite-failed, adoption-failed."* ]]
}
