#!/usr/bin/env bats
# Bats fixture for parse-findings.sh (FEAT-028 / FR-2).
#
# Covers:
#   * Happy path: zero-findings (no summary line), canonical summary +
#     individual findings, test-plan mode prefix on summary line, ASCII
#     double-hyphen fallback, bold and unbold finding markers.
#   * Warn emission: counts.warnings + counts.info > 0 AND individual empty.
#   * Warn suppression: errors-only counts with individual empty.
#   * Shape guarantees: counts + individual keys always present.
#   * Errors: missing arg (2), non-existent file (1).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  PARSE="${SCRIPT_DIR}/parse-findings.sh"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---- helpers -----------------------------------------------------------------

# Extract a jq-style numeric path from the output JSON. Uses jq if available,
# else grep. Returns the value on stdout.
get_count() {
  local json="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".counts.${key}"
  else
    # crude pure-bash fallback — not used on the CI box
    printf '%s' "$json" | sed -E "s/.*\"${key}\":([0-9]+).*/\1/"
  fi
}

individual_length() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.individual | length'
  else
    # count '{"id":' occurrences as a weak fallback
    printf '%s' "$json" | grep -o '{"id":' | wc -l | tr -d ' '
  fi
}

# ---- zero-findings ----------------------------------------------------------

@test "zero-findings fixture → counts all zero, individual empty, exit 0" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-zero-findings.txt"
  [ "$status" -eq 0 ]
  [ "$(get_count "$output" errors)" = "0" ]
  [ "$(get_count "$output" warnings)" = "0" ]
  [ "$(get_count "$output" info)" = "0" ]
  [ "$(individual_length "$output")" = "0" ]
}

# ---- canonical summary + individual -----------------------------------------

@test "canonical summary → counts match, individual populated" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-canonical-summary.txt"
  [ "$status" -eq 0 ]
  [ "$(get_count "$output" errors)" = "0" ]
  [ "$(get_count "$output" warnings)" = "2" ]
  [ "$(get_count "$output" info)" = "1" ]
  [ "$(individual_length "$output")" = "3" ]
}

@test "canonical summary → W1 severity warning with correct category" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-canonical-summary.txt"
  [ "$status" -eq 0 ]
  local got
  got=$(printf '%s' "$output" | jq -r '.individual[0].id')
  [ "$got" = "W1" ]
  got=$(printf '%s' "$output" | jq -r '.individual[0].severity')
  [ "$got" = "warning" ]
  got=$(printf '%s' "$output" | jq -r '.individual[0].category')
  [ "$got" = "reference" ]
  got=$(printf '%s' "$output" | jq -r '.individual[0].description')
  [ "$got" = "FR-3 cites \`references/reviewing-requirements-flow.md\` but does not name the exact subsection." ]
}

@test "canonical summary → I1 severity info" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-canonical-summary.txt"
  [ "$status" -eq 0 ]
  local got
  got=$(printf '%s' "$output" | jq -r '.individual[2].id')
  [ "$got" = "I1" ]
  got=$(printf '%s' "$output" | jq -r '.individual[2].severity')
  [ "$got" = "info" ]
}

# ---- test-plan mode prefix --------------------------------------------------

@test "test-plan-mode prefix on summary line → counts extracted despite prefix" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-test-plan-prefix.txt"
  [ "$status" -eq 0 ]
  [ "$(get_count "$output" errors)" = "1" ]
  [ "$(get_count "$output" warnings)" = "0" ]
  [ "$(get_count "$output" info)" = "0" ]
}

# ---- ASCII dash fallback ----------------------------------------------------

@test "ASCII double-hyphen findings → parsed like em dash" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-ascii-dash.txt"
  [ "$status" -eq 0 ]
  [ "$(get_count "$output" errors)" = "0" ]
  [ "$(get_count "$output" warnings)" = "1" ]
  [ "$(get_count "$output" info)" = "1" ]
  [ "$(individual_length "$output")" = "2" ]
  local got
  got=$(printf '%s' "$output" | jq -r '.individual[0].id')
  [ "$got" = "W1" ]
  got=$(printf '%s' "$output" | jq -r '.individual[0].category')
  [ "$got" = "reference" ]
}

# ---- bold / unbold markers --------------------------------------------------

@test "bold markers stripped from description; unbold also accepted" {
  # Write an inline fixture with one bold-wrapped finding and one plain.
  cat > "${TMPDIR_TEST}/mixed.txt" <<'EOF'
Found **0 errors**, **1 warnings**, **1 info**

**[W1] category-a — bold description**
[I1] category-b — plain description
EOF
  run bash "$PARSE" "${TMPDIR_TEST}/mixed.txt"
  [ "$status" -eq 0 ]
  [ "$(individual_length "$output")" = "2" ]
  local got
  got=$(printf '%s' "$output" | jq -r '.individual[0].description')
  [ "$got" = "bold description" ]
  got=$(printf '%s' "$output" | jq -r '.individual[1].description')
  [ "$got" = "plain description" ]
}

# ---- warn-emission tests ----------------------------------------------------

@test "counts-only fixture (warnings/info > 0, individual empty) → [warn] to stderr" {
  local err_file="${TMPDIR_TEST}/err.log"
  bash "$PARSE" "${FIXTURES_DIR}/rr-output-counts-only.txt" >/dev/null 2>"$err_file"
  [ "$?" -eq 0 ] || true
  grep -q '\[warn\] parse-findings: counts non-zero but no individual findings parsed' "$err_file"
}

@test "counts-only fixture → output JSON still has zero individual array" {
  # Capture stdout only — stderr carries the [warn] line and corrupts JSON parse.
  local out_file="${TMPDIR_TEST}/out.json"
  bash "$PARSE" "${FIXTURES_DIR}/rr-output-counts-only.txt" >"$out_file" 2>/dev/null
  [ "$?" -eq 0 ] || true
  local json
  json="$(cat "$out_file")"
  [ "$(individual_length "$json")" = "0" ]
  [ "$(get_count "$json" warnings)" = "2" ]
  [ "$(get_count "$json" info)" = "1" ]
}

@test "errors-only counts + empty individual → NO [warn] emitted" {
  # Capture stderr separately using a temp file.
  local err_file="${TMPDIR_TEST}/err.log"
  bash "$PARSE" "${FIXTURES_DIR}/rr-output-errors-only.txt" >/dev/null 2>"$err_file"
  [ "$?" -eq 0 ] || true
  [ ! -s "$err_file" ]
}

@test "errors-only fixture → counts.errors=1, individual empty" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-errors-only.txt"
  [ "$status" -eq 0 ]
  [ "$(get_count "$output" errors)" = "1" ]
  [ "$(individual_length "$output")" = "0" ]
}

# ---- JSON shape guarantees --------------------------------------------------

@test "zero counts and empty individual → counts and individual keys still present" {
  run bash "$PARSE" "${FIXTURES_DIR}/rr-output-zero-findings.txt"
  [ "$status" -eq 0 ]
  local keys
  keys=$(printf '%s' "$output" | jq -r 'keys_unsorted | join(",")')
  [ "$keys" = "counts,individual" ]
}

# ---- error-exit tests -------------------------------------------------------

@test "missing arg → exit 2" {
  run bash "$PARSE"
  [ "$status" -eq 2 ]
}

@test "non-existent file → exit 1" {
  run bash "$PARSE" "${TMPDIR_TEST}/does-not-exist.txt"
  [ "$status" -eq 1 ]
}
