#!/usr/bin/env bash
set -euo pipefail

# run-framework.sh (FR-5) — Run a test framework against a supplied test-file
# glob, parse runner output, emit an execution-results JSON.
#
# Usage:
#   run-framework.sh <capability-json> <test-file-glob>
#
# Args:
#   <capability-json> Path to a capability JSON (output of capability-discovery.sh).
#                     Required keys: framework, testCommand.
#   <test-file-glob>  Glob (or single file) selecting test files to run. Passed
#                     verbatim to the framework's testCommand. Quote it from the
#                     caller — the script does not re-expand globs.
#
# Output:
#   stdout JSON {total, passed, failed, errored, failingNames, truncatedOutput,
#                exitCode, durationMs}.
#
# Exit codes:
#   0  runner ran (counts may indicate failures; check `failed`/`errored`)
#   1  runner could not start (binary missing, capability JSON malformed, etc.)
#   2  missing/invalid args

usage() {
  echo "Usage: run-framework.sh <capability-json> <test-file-glob>" >&2
}

if [[ $# -ne 2 ]]; then
  echo "Error: expected 2 args, got $#." >&2
  usage
  exit 2
fi

CAPABILITY_JSON_PATH="$1"
TEST_GLOB="$2"

if [[ ! -f "$CAPABILITY_JSON_PATH" ]]; then
  echo "Error: capability JSON not found: $CAPABILITY_JSON_PATH" >&2
  exit 2
fi
if ! jq -e . "$CAPABILITY_JSON_PATH" >/dev/null 2>&1; then
  echo "Error: capability JSON is not valid JSON: $CAPABILITY_JSON_PATH" >&2
  exit 2
fi

FRAMEWORK="$(jq -r '.framework // empty' "$CAPABILITY_JSON_PATH")"
TEST_COMMAND="$(jq -r '.testCommand // empty' "$CAPABILITY_JSON_PATH")"

if [[ -z "$FRAMEWORK" ]]; then
  echo "Error: capability JSON missing 'framework' field." >&2
  exit 1
fi
if [[ -z "$TEST_COMMAND" ]]; then
  echo "Error: capability JSON missing 'testCommand' field." >&2
  exit 1
fi

# Truncate runner output to keep emitted JSON manageable. 16 KiB is enough to
# contain a handful of failing-test stack traces; the field is only consulted
# when parsing fails.
MAX_OUTPUT_BYTES=16384

case "$FRAMEWORK" in
  vitest|jest|pytest|go-test) ;;
  *)
    echo "Error: unsupported framework: '$FRAMEWORK' (supported: vitest jest pytest go-test)" >&2
    exit 1
    ;;
esac

# Build the full command. For vitest/jest, append the glob as a positional arg.
# For pytest, the glob slot is also a positional arg. For go test, replace
# `./...` with the glob if the user provided a specific test path.
CMD=""
case "$FRAMEWORK" in
  vitest|jest|pytest)
    CMD="$TEST_COMMAND $TEST_GLOB"
    ;;
  go-test)
    if [[ "$TEST_COMMAND" == *"./..."* ]]; then
      CMD="${TEST_COMMAND//\.\/\.\.\./$TEST_GLOB}"
    else
      CMD="$TEST_COMMAND $TEST_GLOB"
    fi
    ;;
esac

# Capture stdout+stderr together; preserve runner exit code via PIPESTATUS.
START_NS=$(date +%s%N 2>/dev/null || echo "")
if [[ -z "$START_NS" || "$START_NS" == *"N" ]]; then
  # macOS `date` lacks %N; fall back to second precision.
  START_S=$(date +%s)
  START_NS=$((START_S * 1000000000))
fi

# Run the command; capture combined output + exit code without aborting on
# non-zero. `set +e` keeps the runner's failure from killing the script.
set +e
RUNNER_OUTPUT="$(bash -c "$CMD" 2>&1)"
RUNNER_EXIT=$?
set -e

END_NS=$(date +%s%N 2>/dev/null || echo "")
if [[ -z "$END_NS" || "$END_NS" == *"N" ]]; then
  END_S=$(date +%s)
  END_NS=$((END_S * 1000000000))
fi
DURATION_MS=$(( (END_NS - START_NS) / 1000000 ))
if [[ "$DURATION_MS" -lt 0 ]]; then
  DURATION_MS=0
fi

# If the runner could not even start (e.g., command not found shells back 127
# from `bash -c`), report exit 1.
if [[ "$RUNNER_EXIT" -eq 127 ]]; then
  # Emit a minimal JSON so callers can still surface the failure context.
  jq -nc \
    --arg out "$(printf '%s' "$RUNNER_OUTPUT" | head -c "$MAX_OUTPUT_BYTES")" \
    --argjson exitCode "$RUNNER_EXIT" \
    --argjson durationMs "$DURATION_MS" \
    '{
      total: 0, passed: 0, failed: 0, errored: 0,
      failingNames: [],
      truncatedOutput: $out,
      exitCode: $exitCode,
      durationMs: $durationMs
    }'
  exit 1
fi

# Parse the runner output per framework. The parsers are heuristic — the
# canonical totals/failing-names line shapes are covered for stable releases
# of each runner.

TOTAL=0
PASSED=0
FAILED=0
ERRORED=0
FAILING_NAMES_JSON="[]"

# Helpers shared by every parse_* — extract first integer matching a pattern
# from a single line of input. Returns "0" when no match.
extract_count() {
  local pattern="$1"; local line="$2"
  local result
  result="$(printf '%s' "$line" | grep -oE "$pattern" | head -n 1 | grep -oE '[0-9]+' || true)"
  printf '%s' "${result:-0}"
}

# grep_filter — wrap grep so it always returns 0 (no match yields empty stdout).
# Lets caller pipelines avoid `set -o pipefail` aborts on a no-match.
grep_filter() {
  grep "$@" || true
}

# Build a JSON array of strings from a list of pre-filtered names on stdin.
# Always emits a valid JSON array (`[]` on empty).
names_to_json_array() {
  local input
  input="$(cat)"
  if [[ -z "$input" ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "$input" | jq -R -s 'split("\n") | map(select(length > 0))'
}

parse_vitest() {
  # vitest summary lines:
  #   Test Files  3 passed (3)
  #   Tests       12 passed | 1 failed (13)
  #   Tests       12 passed (12)
  local out="$1"
  local tests_line
  tests_line="$(printf '%s\n' "$out" | grep -E '^[[:space:]]*Tests[[:space:]]+' | tail -n 1 || true)"
  if [[ -n "$tests_line" ]]; then
    PASSED=$(extract_count '[0-9]+ passed' "$tests_line")
    FAILED=$(extract_count '[0-9]+ failed' "$tests_line")
    ERRORED=$(extract_count '[0-9]+ errored' "$tests_line")
    local total_in_parens
    total_in_parens="$(printf '%s' "$tests_line" | grep -oE '\([0-9]+\)' | head -n 1 | tr -d '()' || true)"
    if [[ -n "$total_in_parens" ]]; then
      TOTAL="$total_in_parens"
    else
      TOTAL=$((PASSED + FAILED + ERRORED))
    fi
  fi
  # Failing test names: vitest prints `× <name>` or `FAIL <file> > <name>`
  FAILING_NAMES_JSON="$(printf '%s\n' "$out" \
    | grep_filter -E '^[[:space:]]*(FAIL|×|✗)[[:space:]]' \
    | sed -E 's/^[[:space:]]*(FAIL|×|✗)[[:space:]]+//' \
    | sed -E 's/[[:space:]]+\([0-9]+ms?\)$//' \
    | names_to_json_array)"
}

parse_jest() {
  # jest summary line:
  #   Tests:       1 failed, 12 passed, 13 total
  local out="$1"
  local tests_line
  tests_line="$(printf '%s\n' "$out" | grep -E '^Tests:' | tail -n 1 || true)"
  if [[ -n "$tests_line" ]]; then
    PASSED=$(extract_count '[0-9]+ passed' "$tests_line")
    FAILED=$(extract_count '[0-9]+ failed' "$tests_line")
    ERRORED=$(extract_count '[0-9]+ errored' "$tests_line")
    TOTAL=$(extract_count '[0-9]+ total' "$tests_line")
  fi
  # Failing test names: jest prints `● <name>`
  FAILING_NAMES_JSON="$(printf '%s\n' "$out" \
    | grep_filter -E '^[[:space:]]*●[[:space:]]' \
    | sed -E 's/^[[:space:]]*●[[:space:]]+//' \
    | names_to_json_array)"
}

parse_pytest() {
  # pytest short summary:
  #   ===== 1 failed, 12 passed in 0.42s =====
  #   ===== 12 passed in 0.42s =====
  local out="$1"
  local summary_line
  summary_line="$(printf '%s\n' "$out" | grep -E '^=+[[:space:]].*[[:space:]]in[[:space:]]' | tail -n 1 || true)"
  if [[ -n "$summary_line" ]]; then
    PASSED=$(extract_count '[0-9]+ passed' "$summary_line")
    FAILED=$(extract_count '[0-9]+ failed' "$summary_line")
    ERRORED=$(extract_count '[0-9]+ error' "$summary_line")
    TOTAL=$((PASSED + FAILED + ERRORED))
  fi
  # Failing test names: pytest's short test summary lines are `FAILED path::name`
  FAILING_NAMES_JSON="$(printf '%s\n' "$out" \
    | grep_filter -E '^FAILED[[:space:]]' \
    | sed -E 's/^FAILED[[:space:]]+//' \
    | sed -E 's/[[:space:]]+-[[:space:]].*$//' \
    | names_to_json_array)"
}

parse_go_test() {
  # go test prints:
  #   --- FAIL: TestX (0.00s)
  #   --- PASS: TestY (0.00s)
  #   ok  pkg  0.123s
  #   FAIL  pkg  0.123s
  local out="$1"
  local pass_count fail_count
  pass_count="$(printf '%s\n' "$out" | grep -cE '^--- PASS: ' || true)"
  fail_count="$(printf '%s\n' "$out" | grep -cE '^--- FAIL: ' || true)"
  PASSED="${pass_count:-0}"
  FAILED="${fail_count:-0}"
  ERRORED=0
  TOTAL=$((PASSED + FAILED))
  FAILING_NAMES_JSON="$(printf '%s\n' "$out" \
    | grep_filter -E '^--- FAIL: ' \
    | sed -E 's/^--- FAIL:[[:space:]]+//' \
    | sed -E 's/[[:space:]]+\([0-9.]+s?\)$//' \
    | names_to_json_array)"
}

case "$FRAMEWORK" in
  vitest)  parse_vitest "$RUNNER_OUTPUT" ;;
  jest)    parse_jest "$RUNNER_OUTPUT" ;;
  pytest)  parse_pytest "$RUNNER_OUTPUT" ;;
  go-test) parse_go_test "$RUNNER_OUTPUT" ;;
esac

# Truncate the runner output for embedding. `head -c` may close the pipe
# before printf finishes writing — disable pipefail just for this line so
# SIGPIPE on the upstream printf does not abort the script.
set +o pipefail
TRUNCATED="$(printf '%s' "$RUNNER_OUTPUT" | head -c "$MAX_OUTPUT_BYTES")"
set -o pipefail

jq -nc \
  --argjson total "${TOTAL:-0}" \
  --argjson passed "${PASSED:-0}" \
  --argjson failed "${FAILED:-0}" \
  --argjson errored "${ERRORED:-0}" \
  --argjson failingNames "$FAILING_NAMES_JSON" \
  --arg truncatedOutput "$TRUNCATED" \
  --argjson exitCode "$RUNNER_EXIT" \
  --argjson durationMs "$DURATION_MS" \
  '{
    total: $total,
    passed: $passed,
    failed: $failed,
    errored: $errored,
    failingNames: $failingNames,
    truncatedOutput: $truncatedOutput,
    exitCode: $exitCode,
    durationMs: $durationMs
  }'

exit 0
