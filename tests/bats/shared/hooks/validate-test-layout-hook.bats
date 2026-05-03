#!/usr/bin/env bats
# Bats coverage for FEAT-031 Phase 6 — validate-test-layout-hook.ts.
#
# Coverage matrix (per Phase 6 plan):
#   * Rejects misplaced *.test.ts outside tests/unit/   (ts-outside-tests-unit)
#   * Rejects *.spec.ts anywhere                        (spec-extension-disallowed)
#   * Rejects misplaced *.bats outside tests/bats/      (bats-outside-tests-bats)
#   * Allow-rule: feat-030-known-buggy fixture passes through
#   * Non-test edits (*.md, *.ts without test extensions) are no-ops
#   * Edge Case 4 fail-open: malformed JSON exits 0 + no rejection message

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../../" && pwd)"
  HOOK="${REPO_ROOT}/scripts/hooks/validate-test-layout-hook.ts"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: fire the hook with a file_path value via stdin JSON.
fire_hook() {
  local file_path="$1"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$file_path" \
    | tsx "$HOOK"
}

# Helper: fire the hook with a MultiEdit-shaped payload (single file_path,
# multiple edits) — exercises the matcher's MultiEdit entry point.
fire_hook_multiedit() {
  local file_path="$1"
  printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s","edits":[{"old_string":"a","new_string":"b"}]}}' "$file_path" \
    | tsx "$HOOK"
}

# ---------------------------------------------------------------------------
# Rule: ts-outside-tests-unit — *.test.ts outside tests/unit/ is rejected
# ---------------------------------------------------------------------------

@test "rejects *.test.ts placed at repo root" {
  run fire_hook "foo.test.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates ts-outside-tests-unit"* ]]
}

@test "rejects *.test.ts under scripts/ (not in tests/unit/)" {
  run fire_hook "scripts/foo.test.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates ts-outside-tests-unit"* ]]
}

@test "rejects *.test.ts under plugins/ subtree" {
  run fire_hook "plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa-dimension.test.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates ts-outside-tests-unit"* ]]
}

@test "allows *.test.ts under tests/unit/" {
  run fire_hook "tests/unit/validate-test-layout.test.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "rejection message names canonical destination tests/unit/" {
  run fire_hook "scripts/misplaced.test.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tests/unit/"* ]]
}

# ---------------------------------------------------------------------------
# Rule: spec-extension-disallowed — *.spec.ts is rejected everywhere
# ---------------------------------------------------------------------------

@test "rejects *.spec.ts under tests/unit/" {
  run fire_hook "tests/unit/foo.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates spec-extension-disallowed"* ]]
}

@test "rejects *.spec.ts at repo root" {
  run fire_hook "foo.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates spec-extension-disallowed"* ]]
}

@test "rejects *.spec.ts under plugins/" {
  run fire_hook "plugins/lwndev-sdlc/skills/executing-qa/scripts/__tests__/qa.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates spec-extension-disallowed"* ]]
}

@test "rejection message for spec extension names canonical destination" {
  run fire_hook "foo.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tests/unit/"* ]]
}

# ---------------------------------------------------------------------------
# Rule: bats-outside-tests-bats — *.bats outside tests/bats/ is rejected
# ---------------------------------------------------------------------------

@test "rejects *.bats under plugins/ subtree" {
  run fire_hook "plugins/lwndev-sdlc/skills/executing-qa/scripts/tests/qa.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates bats-outside-tests-bats"* ]]
}

@test "rejects *.bats at repo root" {
  run fire_hook "my-script.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates bats-outside-tests-bats"* ]]
}

@test "allows *.bats under tests/bats/" {
  run fire_hook "tests/bats/shared/hooks/validate-test-layout-hook.bats"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "rejection message for bats outside tests/bats/ names canonical destination" {
  run fire_hook "plugins/foo.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tests/bats/"* ]]
}

# ---------------------------------------------------------------------------
# Allow-rule: feat-030-known-buggy fixture passes through (Edge Case 4 allow)
# ---------------------------------------------------------------------------

@test "allow-rule: feat-030-known-buggy spec.ts fixture is not rejected" {
  run fire_hook "scripts/__tests__/fixtures/feat-030-known-buggy/__tests__/qa-buggy.spec.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

# ---------------------------------------------------------------------------
# Non-test paths: hook is a no-op for non-test extensions
# ---------------------------------------------------------------------------

@test "allows *.md files (no-op)" {
  run fire_hook "README.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "allows *.ts files without test extension (non-test source)" {
  run fire_hook "scripts/build.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "allows *.json files (no-op)" {
  run fire_hook ".claude/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "allows *.sh scripts (no-op)" {
  run fire_hook "plugins/lwndev-sdlc/scripts/hooks/guard-state-transitions.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

# ---------------------------------------------------------------------------
# MultiEdit entry point — same hook script, MultiEdit-shaped payload
# ---------------------------------------------------------------------------

@test "MultiEdit: rejects misplaced *.bats" {
  run fire_hook_multiedit "plugins/lwndev-sdlc/scripts/tests/x.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates bats-outside-tests-bats"* ]]
}

@test "MultiEdit: rejects *.spec.ts" {
  run fire_hook_multiedit "tests/unit/foo.spec.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violates spec-extension-disallowed"* ]]
}

@test "MultiEdit: allows *.test.ts under tests/unit/" {
  run fire_hook_multiedit "tests/unit/foo.test.ts"
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

# ---------------------------------------------------------------------------
# Edge Case 4 fail-open: malformed JSON exits 0 + no rejection
# ---------------------------------------------------------------------------

@test "EC4: completely malformed JSON exits 0 (fail-open)" {
  run bash -c 'printf "not valid json" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "EC4: truncated JSON exits 0 (fail-open)" {
  run bash -c 'printf "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "EC4: empty stdin exits 0 (fail-open)" {
  run bash -c 'printf "" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "EC4: JSON missing tool_input exits 0 (fail-open)" {
  run bash -c 'printf "{\"tool_name\":\"Write\"}" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "EC4: JSON with null tool_input exits 0 (fail-open)" {
  run bash -c 'printf "{\"tool_name\":\"Write\",\"tool_input\":null}" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}

@test "EC4: JSON with missing file_path exits 0 (fail-open)" {
  run bash -c 'printf "{\"tool_name\":\"Write\",\"tool_input\":{}}" | tsx "'"$HOOK"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"reject"* ]]
}
