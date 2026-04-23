#!/usr/bin/env bats
# Bats fixture for backend-detect.sh (FEAT-025 / FR-1).
#
# Pure-function coverage — no stubs required.
#   * GitHub ref happy path (#183)
#   * Jira ref happy path (PROJ-123)
#   * Alphanumeric project keys (PROJ2-456, AB1-789)
#   * No-match cases: plain string, #abc, lowercase proj-123, underscore PROJ_123
#   * Usage errors: missing arg, empty arg, whitespace-only arg
#   * Whitespace trimming: " #183 " trims and matches

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  DETECT="${SCRIPT_DIR}/backend-detect.sh"
}

@test "github ref happy path: #183" {
  run bash "$DETECT" "#183"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"issueNumber":183'* ]]
}

@test "jira ref happy path: PROJ-123" {
  run bash "$DETECT" "PROJ-123"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"jira"'* ]]
  [[ "$output" == *'"projectKey":"PROJ"'* ]]
  [[ "$output" == *'"issueNumber":123'* ]]
}

@test "alphanumeric project key: PROJ2-456" {
  run bash "$DETECT" "PROJ2-456"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"jira"'* ]]
  [[ "$output" == *'"projectKey":"PROJ2"'* ]]
  [[ "$output" == *'"issueNumber":456'* ]]
}

@test "short alphanumeric project key: AB1-789" {
  run bash "$DETECT" "AB1-789"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"projectKey":"AB1"'* ]]
  [[ "$output" == *'"issueNumber":789'* ]]
}

@test "no-match plain string: foo → null" {
  run bash "$DETECT" "foo"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "no-match non-numeric github: #abc → null" {
  run bash "$DETECT" "#abc"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "no-match lowercase jira: proj-123 → null (edge case 4)" {
  run bash "$DETECT" "proj-123"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "no-match underscore separator: PROJ_123 → null (edge case 4)" {
  run bash "$DETECT" "PROJ_123"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "missing arg → exit 2" {
  run bash "$DETECT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[error]"* ]]
}

@test "empty arg → exit 2 (edge case 1)" {
  run bash "$DETECT" ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"[error]"* ]]
}

@test "whitespace-only arg → exit 2 (edge case 2)" {
  run bash "$DETECT" "   "
  [ "$status" -eq 2 ]
  [[ "$output" == *"[error]"* ]]
}

@test "leading/trailing whitespace trimmed: ' #183 ' (edge case 3)" {
  run bash "$DETECT" " #183 "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"github"'* ]]
  [[ "$output" == *'"issueNumber":183'* ]]
}

@test "leading/trailing whitespace trimmed: '\tPROJ-5\t' (edge case 3)" {
  run bash "$DETECT" $'\tPROJ-5\t'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"jira"'* ]]
  [[ "$output" == *'"projectKey":"PROJ"'* ]]
  [[ "$output" == *'"issueNumber":5'* ]]
}

@test "github ref with extra trailing text does not match: #183-foo → null" {
  run bash "$DETECT" "#183-foo"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "jira-like with leading digit in project key: 1PROJ-123 → null" {
  run bash "$DETECT" "1PROJ-123"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
