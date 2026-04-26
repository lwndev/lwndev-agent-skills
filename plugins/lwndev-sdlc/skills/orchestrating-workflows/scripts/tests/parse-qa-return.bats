#!/usr/bin/env bats
# Bats fixture for parse-qa-return.sh (FEAT-030 FR-12).
#
# Covers:
#   * Happy path each verdict (PASS, ISSUES-FOUND, ERROR, EXPLORATORY-ONLY)
#   * --stdin mode reads multi-line response and matches the LAST contract line
#   * Reject missing pipe separators → exit 1
#   * Reject non-numeric counts → exit 1
#   * Reject lowercase verdict → exit 1
#   * Reject extra trailing text → exit 1
#   * Reject extra leading whitespace → exit 1 (regex is anchored)
#   * Happy path with --artifact <path> deriving summary from ## Summary
#   * --artifact pointing to a missing file → graceful fallback summary

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  PARSE="${SCRIPT_DIR}/parse-qa-return.sh"
  ARTIFACT="${FIXTURES_DIR}/qa-artifacts/QA-results-FEAT-030.md"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---- Happy path: each verdict ------------------------------------------------

@test "PASS verdict → JSON with verdict=PASS passed=12 failed=0 errored=0" {
  run bash "$PARSE" "Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0"
  [ "$status" -eq 0 ]
  local verdict passed failed errored
  verdict=$(echo "$output" | jq -r '.verdict')
  passed=$(echo "$output" | jq -r '.passed')
  failed=$(echo "$output" | jq -r '.failed')
  errored=$(echo "$output" | jq -r '.errored')
  [ "$verdict" = "PASS" ]
  [ "$passed" = "12" ]
  [ "$failed" = "0" ]
  [ "$errored" = "0" ]
}

@test "ISSUES-FOUND verdict → JSON with verdict=ISSUES-FOUND passed=9 failed=3 errored=0" {
  run bash "$PARSE" "Verdict: ISSUES-FOUND | Passed: 9 | Failed: 3 | Errored: 0"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "ISSUES-FOUND" ]
  local failed
  failed=$(echo "$output" | jq -r '.failed')
  [ "$failed" = "3" ]
}

@test "ERROR verdict → JSON with verdict=ERROR errored=1" {
  run bash "$PARSE" "Verdict: ERROR | Passed: 0 | Failed: 0 | Errored: 1"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "ERROR" ]
  local errored
  errored=$(echo "$output" | jq -r '.errored')
  [ "$errored" = "1" ]
}

@test "EXPLORATORY-ONLY verdict → JSON with all counts zero" {
  run bash "$PARSE" "Verdict: EXPLORATORY-ONLY | Passed: 0 | Failed: 0 | Errored: 0"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "EXPLORATORY-ONLY" ]
  local passed failed errored
  passed=$(echo "$output" | jq -r '.passed')
  failed=$(echo "$output" | jq -r '.failed')
  errored=$(echo "$output" | jq -r '.errored')
  [ "$passed" = "0" ]
  [ "$failed" = "0" ]
  [ "$errored" = "0" ]
}

# ---- --stdin mode reads LAST matching contract line --------------------------

@test "--stdin mode extracts LAST contract line from multi-line response" {
  local input
  input="$(cat <<'EOF'
Some preamble text from the skill.
Verdict: PASS | Passed: 5 | Failed: 0 | Errored: 0
More text in the middle.
Verdict: ISSUES-FOUND | Passed: 9 | Failed: 3 | Errored: 0
EOF
)"
  run bash "$PARSE" --stdin <<< "$input"
  [ "$status" -eq 0 ]
  # Should match LAST line: ISSUES-FOUND.
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "ISSUES-FOUND" ]
  local failed
  failed=$(echo "$output" | jq -r '.failed')
  [ "$failed" = "3" ]
}

@test "--stdin mode with single contract line → matches it" {
  run bash "$PARSE" --stdin <<< "Verdict: ERROR | Passed: 0 | Failed: 0 | Errored: 1"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | jq -r '.verdict')
  [ "$verdict" = "ERROR" ]
}

@test "--stdin mode with no matching line → exit 1 with contract-mismatch" {
  run bash "$PARSE" --stdin <<< "No contract line here."
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

# ---- Reject malformed inputs → exit 1 ----------------------------------------

@test "missing pipe separators → exit 1" {
  run bash "$PARSE" "Verdict: PASS Passed: 12 Failed: 0 Errored: 0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

@test "non-numeric counts → exit 1" {
  run bash "$PARSE" "Verdict: PASS | Passed: abc | Failed: 0 | Errored: 0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

@test "lowercase verdict → exit 1" {
  run bash "$PARSE" "Verdict: pass | Passed: 12 | Failed: 0 | Errored: 0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

@test "extra trailing text → exit 1 (regex is anchored)" {
  run bash "$PARSE" "Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0 extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

@test "extra leading whitespace → exit 1 (regex is anchored at start)" {
  run bash "$PARSE" " Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract mismatch"* ]]
}

# ---- --artifact flag: derive summary from ## Summary section -----------------

@test "--artifact flag derives summary from first paragraph of ## Summary" {
  run bash "$PARSE" "Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0" \
    --artifact "$ARTIFACT"
  [ "$status" -eq 0 ]
  local summary
  summary=$(echo "$output" | jq -r '.summary')
  # Should contain text from ## Summary and the artifact path.
  [[ "$summary" == *"All QA tests passed"* ]]
  [[ "$summary" == *"artifact:"* ]]
}

@test "--artifact with --stdin also derives summary from artifact" {
  run bash "$PARSE" --stdin --artifact "$ARTIFACT" <<< \
    "Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0"
  [ "$status" -eq 0 ]
  local summary
  summary=$(echo "$output" | jq -r '.summary')
  [[ "$summary" == *"All QA tests passed"* ]]
}

# ---- --artifact pointing to missing file → graceful fallback -----------------

@test "--artifact missing file → graceful fallback summary containing artifact path" {
  local missing_path="${TMPDIR_TEST}/nonexistent/QA-results-FEAT-099.md"
  run bash "$PARSE" "Verdict: PASS | Passed: 12 | Failed: 0 | Errored: 0" \
    --artifact "$missing_path"
  [ "$status" -eq 0 ]
  local summary
  summary=$(echo "$output" | jq -r '.summary')
  # Graceful fallback: summary contains the artifact path.
  [[ "$summary" == *"${missing_path}"* ]]
}

# ---- No args → exit 2 --------------------------------------------------------

@test "no args → exit 2" {
  run bash "$PARSE"
  [ "$status" -eq 2 ]
}

# ---- Error message contains the verbatim regex literal -----------------------

@test "mismatch error message contains the canonical regex literal" {
  run bash "$PARSE" "not a contract line"
  [ "$status" -eq 1 ]
  [[ "$output" == *'^Verdict: (PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY)'* ]]
}
