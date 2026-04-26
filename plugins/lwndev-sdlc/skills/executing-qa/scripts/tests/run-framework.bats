#!/usr/bin/env bats
# Bats fixture for run-framework.sh (FEAT-030 / FR-5).
#
# Covers the full contract: arg validation, every supported framework parser,
# runner-could-not-start, unsupported framework, and runner-crash. Uses the
# capability JSON's `testCommand` to inline a stub (printf or a PATH-shadowed
# binary), keeping every test hermetic.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/run-framework.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  # PATH-shadow dir for fake framework binaries.
  FAKE_BIN="${TMPDIR_TEST}/fake-bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
}

teardown() {
  PATH="$ORIG_PATH"
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

write_capability() {
  local fw="$1"; local cmd="$2"; local out="${3:-cap.json}"
  jq -n --arg fw "$fw" --arg cmd "$cmd" \
    '{framework:$fw, language:"typescript", packageManager:"npm", testCommand:$cmd, mode:"test-framework", notes:[]}' \
    > "$out"
}

# --- Arg validation ---------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "one arg → exit 2" {
  run bash "$SCRIPT" cap.json
  [ "$status" -eq 2 ]
}

@test "missing capability JSON → exit 2" {
  run bash "$SCRIPT" no.json "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"capability JSON not found"* ]]
}

@test "malformed capability JSON → exit 2" {
  printf 'not json' > cap.json
  run bash "$SCRIPT" cap.json "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

# --- Capability fields ------------------------------------------------------

@test "capability JSON missing 'framework' → exit 1" {
  jq -n '{testCommand:"true"}' > cap.json
  run bash "$SCRIPT" cap.json "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing 'framework' field"* ]]
}

@test "capability JSON missing 'testCommand' → exit 1" {
  jq -n '{framework:"vitest"}' > cap.json
  run bash "$SCRIPT" cap.json "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing 'testCommand' field"* ]]
}

@test "unsupported framework → exit 1" {
  write_capability "mocha" "echo hi"
  run bash "$SCRIPT" cap.json "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported framework"* ]]
}

# --- Vitest parser ---------------------------------------------------------

@test "vitest happy path — passing tests parsed" {
  write_capability "vitest" 'printf "Tests       3 passed (3)\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 3 and .passed == 3 and .failed == 0 and .errored == 0 and (.failingNames | length == 0) and .exitCode == 0'
}

@test "vitest failing tests — failingNames extracted" {
  write_capability "vitest" 'printf "Tests       2 passed | 1 failed (3)\nFAIL src/foo.test.ts > my failing test (1ms)\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 3 and .passed == 2 and .failed == 1 and (.failingNames | length == 1) and .failingNames[0] == "src/foo.test.ts > my failing test"'
}

# --- Jest parser -----------------------------------------------------------

@test "jest happy path — passing tests parsed" {
  write_capability "jest" 'printf "Tests:       12 passed, 12 total\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 12 and .passed == 12 and .failed == 0'
}

@test "jest failing tests — failingNames extracted" {
  write_capability "jest" 'printf "Tests:       1 failed, 12 passed, 13 total\n  ● my suite > my failing test\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 13 and .passed == 12 and .failed == 1 and (.failingNames | length == 1)'
}

# --- Pytest parser ---------------------------------------------------------

@test "pytest happy path — passing tests parsed" {
  write_capability "pytest" 'printf "===== 12 passed in 0.42s =====\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 12 and .passed == 12 and .failed == 0'
}

@test "pytest failing tests — failingNames extracted" {
  write_capability "pytest" 'printf "FAILED tests/test_x.py::test_one\n===== 1 failed, 12 passed in 0.42s =====\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.passed == 12 and .failed == 1 and .failingNames[0] == "tests/test_x.py::test_one"'
}

# --- Go test parser --------------------------------------------------------

@test "go-test happy path — passing tests parsed" {
  write_capability "go-test" 'printf "=== RUN   TestA\n--- PASS: TestA (0.00s)\n=== RUN   TestB\n--- PASS: TestB (0.00s)\nPASS\nok      pkg     0.123s\n"'
  run bash "$SCRIPT" cap.json "./..."
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.passed == 2 and .failed == 0'
}

@test "go-test failing tests — failingNames extracted" {
  write_capability "go-test" 'printf "=== RUN   TestA\n--- FAIL: TestA (0.00s)\n--- PASS: TestB (0.00s)\nFAIL    pkg     0.123s\n"'
  run bash "$SCRIPT" cap.json "./..."
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.passed == 1 and .failed == 1 and .failingNames[0] == "TestA"'
}

# --- Edge cases -----------------------------------------------------------

@test "runner could not start (binary missing) → exit 1" {
  write_capability "vitest" "/nonexistent/binary"
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.exitCode == 127'
}

@test "runner ran but reported failures — script still exits 0 (counts surface)" {
  write_capability "vitest" 'printf "Tests       0 passed | 1 failed (1)\nFAIL solo (0ms)\n"; exit 1'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.failed == 1 and .exitCode == 1'
}

@test "zero matching test files (testCommand emits empty output) → script still exits 0 with zeros" {
  write_capability "vitest" 'true'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total == 0 and .passed == 0 and .failed == 0 and .exitCode == 0'
}

@test "runner crash mid-run — non-zero exit + counts derive from partial output" {
  write_capability "vitest" 'printf "Tests       2 passed | 1 failed (3)\nFAIL crashed (0ms)\n"; kill -SEGV $$ 2>/dev/null; exit 139'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.exitCode != 0'
}

# --- truncatedOutput cap ---------------------------------------------------

@test "very large output is truncated to 16 KiB" {
  # Print ~32 KiB of content, then a summary line.
  write_capability "vitest" 'yes A | head -c 32768; printf "\nTests       1 passed (1)\n"'
  run bash "$SCRIPT" cap.json ""
  [ "$status" -eq 0 ]
  truncated_len=$(echo "$output" | jq -r '.truncatedOutput' | wc -c | tr -d ' ')
  # Allow a slack range just under 16 KiB +1 newline
  [ "$truncated_len" -le 16385 ]
}
