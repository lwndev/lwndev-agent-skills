#!/usr/bin/env bats
# Bats test suite for stop-hook.sh FR-10 diff guard (FEAT-030 / Phase 4).
#
# Uses a real ephemeral git repo fixture so git commands work without mocking.
# Each test:
#   1. Initialises a throwaway git repo in a temp dir.
#   2. Creates a minimal v2 QA results artifact + a capability JSON.
#   3. Writes the baseline marker (simulating qa-baseline.sh init).
#   4. Optionally modifies files between the baseline and the hook.
#   5. Runs stop-hook.sh via stdin JSON and asserts exit code + stderr.

SCRIPT_DIR=""
STOP_HOOK=""

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  STOP_HOOK="${SCRIPT_DIR}/stop-hook.sh"

  # Create a throwaway workspace.
  TMPDIR_TEST="$(mktemp -d)"

  # Initialise a git repo (identity required for commits).
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"

  # Create required directories.
  mkdir -p "$TMPDIR_TEST/.sdlc/qa"
  mkdir -p "$TMPDIR_TEST/qa/test-results"
  mkdir -p "$TMPDIR_TEST/qa/test-plans"
  mkdir -p "$TMPDIR_TEST/src"
  mkdir -p "$TMPDIR_TEST/__tests__"

  # Create a placeholder source file and commit it as the initial state.
  printf 'export const x = 1;\n' > "$TMPDIR_TEST/src/index.ts"
  printf '// test file\n' > "$TMPDIR_TEST/__tests__/foo.spec.ts"
  git -C "$TMPDIR_TEST" add .
  git -C "$TMPDIR_TEST" commit -q -m "initial"

  # Write a valid v2 QA results artifact.
  write_results_artifact "$TMPDIR_TEST" "FEAT-030" "PASS"

  # Write a vitest capability JSON.
  write_capability_json "$TMPDIR_TEST" "FEAT-030" "vitest"

  # Write the ACTIVE file so the hook is not short-circuited.
  touch "$TMPDIR_TEST/.sdlc/qa/.executing-active"

  # Change to the repo root so relative paths inside stop-hook.sh resolve.
  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_results_artifact() {
  local repo="$1" id="$2" verdict="$3"
  local path="$repo/qa/test-results/QA-results-${id}.md"
  cat > "$path" <<EOF
---
id: ${id}
version: 2
timestamp: 2026-04-25T00:00:00Z
verdict: ${verdict}
persona: qa
---

## Summary

QA run for ${id}.

## Capability Report

vitest detected.

## Execution Results

- Total: 5
- Passed: 5
- Failed: 0
- Errored: 0
- Exit code: 0

## Scenarios Run

| # | Scenario | Status |
|---|----------|--------|
| 1 | Happy path | PASS |

## Findings

No issues.

## Reconciliation Delta

### Coverage beyond requirements

None.

### Coverage gaps

None.

### Summary

coverage-surplus: 0
coverage-gap: 0
EOF
}

write_capability_json() {
  local repo="$1" id="$2" framework="$3"
  local path="/tmp/qa-capability-${id}.json"
  jq -n --arg id "$id" --arg fw "$framework" \
    '{id: $id, timestamp: "2026-04-25T00:00:00Z", mode: "test-framework",
      framework: $fw, packageManager: "npm", testCommand: "npm test",
      language: "typescript", notes: []}' > "$path"
}

build_hook_input() {
  local id="$1"
  jq -n --arg msg "Results saved to qa/test-results/QA-results-${id}.md" \
    '{stop_hook_active: false, last_assistant_message: $msg}'
}

write_baseline() {
  local repo="$1" id="$2"
  git -C "$repo" rev-parse HEAD > "$repo/.sdlc/qa/.executing-qa-baseline-${id}"
}

# ---------------------------------------------------------------------------
# Test 1: Pure addition inside test root — hook passes
# ---------------------------------------------------------------------------

@test "FR-10: pure addition inside test root is allowed" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Add a new spec file inside __tests__.
  printf 'test("qa", () => {})\n' > "$TMPDIR_TEST/__tests__/qa-inputs.spec.ts"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 0 ]
  # Active file should be removed.
  [ ! -f "$TMPDIR_TEST/.sdlc/qa/.executing-active" ]
}

# ---------------------------------------------------------------------------
# Test 2: Modification inside test root — hook passes
# ---------------------------------------------------------------------------

@test "FR-10: modification of existing test file inside test root is allowed" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Modify existing spec.
  printf '// updated\ntest("qa", () => {})\n' > "$TMPDIR_TEST/__tests__/foo.spec.ts"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 3: Edit outside test root — hook blocks (FR-10 error message)
# ---------------------------------------------------------------------------

@test "FR-10: edit outside test root is blocked with verbatim error" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Commit a production file modification after baseline.
  printf 'export const x = 2;\n' > "$TMPDIR_TEST/src/index.ts"
  git -C "$TMPDIR_TEST" add "src/index.ts"
  git -C "$TMPDIR_TEST" commit -q -m "qa: accidentally edit production file"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Stop hook: executing-qa modified production files outside the framework test root"* ]]
  [[ "$output" == *"src/index.ts"* ]]
  [[ "$output" == *"QA is report-only; do not edit production code to make tests pass"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: QA artifacts are always allowed
# ---------------------------------------------------------------------------

@test "FR-10: QA result and plan artifacts are always allowed" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Modify the QA results artifact itself.
  # (already written by write_results_artifact; just touch it)
  printf '# extra line\n' >> "$TMPDIR_TEST/qa/test-results/QA-results-FEAT-030.md"

  # Also add a test plan artifact.
  mkdir -p "$TMPDIR_TEST/qa/test-plans"
  printf '# test plan\n' > "$TMPDIR_TEST/qa/test-plans/QA-plan-FEAT-030.md"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 5: Pre-existing uncommitted changes outside test root NOT blocked
# ---------------------------------------------------------------------------

@test "FR-10: pre-existing uncommitted changes before baseline are NOT blocked" {
  cd "$TMPDIR_TEST"

  # Modify src/index.ts BEFORE writing the baseline.
  printf 'export const x = 99;\n' > "$TMPDIR_TEST/src/index.ts"

  # Baseline captures HEAD (the original commit, before this dirty change).
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # No further changes to src/index.ts after baseline — git diff HEAD..HEAD is empty
  # for committed files, but src/index.ts is only staged/modified; since diff is
  # computed against committed HEAD, uncommitted workspace changes since the
  # baseline may appear. However the design intent is that only changes COMMITTED
  # after the baseline are guarded. The diff guard uses `git diff <sha>` which
  # includes staged + committed since sha, but not untracked.
  # For this test: the file was dirty BEFORE the baseline, baseline = HEAD,
  # and git diff HEAD shows only working-tree changes which are not in committed
  # history. So the diff output for committed changes (tracked by git diff HEAD)
  # is empty for src/index.ts because only the index was changed before baseline.
  # We verify hook passes (no false positive).
  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test 6: Missing baseline marker → fail closed
# ---------------------------------------------------------------------------

@test "FR-10: missing baseline marker causes fail-closed error" {
  cd "$TMPDIR_TEST"
  # Deliberately do NOT write the baseline marker.

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing baseline marker"* ]]
  [[ "$output" == *".executing-qa-baseline-FEAT-030"* ]]
  [[ "$output" == *"Re-run executing-qa from the start"* ]]
}

# ---------------------------------------------------------------------------
# Test 7: Rename from inside test root to outside is BLOCKED
# ---------------------------------------------------------------------------

@test "FR-10: rename from inside test root to outside is blocked" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Commit a rename after baseline: move __tests__/foo.spec.ts -> src/foo.spec.ts
  git -C "$TMPDIR_TEST" mv "__tests__/foo.spec.ts" "src/foo.spec.ts"
  git -C "$TMPDIR_TEST" commit -q -m "rename spec out of test root"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Stop hook: executing-qa modified production files"* ]]
  [[ "$output" == *"src/foo.spec.ts"* ]]
}

# ---------------------------------------------------------------------------
# Test 8: Cleanup — both marker and active file removed on success and failure
# ---------------------------------------------------------------------------

@test "FR-10: cleanup on success removes both active file and baseline marker" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 0 ]
  [ ! -f "$TMPDIR_TEST/.sdlc/qa/.executing-active" ]
  [ ! -f "$TMPDIR_TEST/.sdlc/qa/.executing-qa-baseline-FEAT-030" ]
}

@test "FR-10: cleanup on failure removes both active file and baseline marker" {
  cd "$TMPDIR_TEST"
  write_baseline "$TMPDIR_TEST" "FEAT-030"

  # Cause a failure by committing a production file modification after baseline.
  printf 'export const x = 2;\n' > "$TMPDIR_TEST/src/index.ts"
  git -C "$TMPDIR_TEST" add "src/index.ts"
  git -C "$TMPDIR_TEST" commit -q -m "qa: accidentally edit production file"

  run bash "$STOP_HOOK" <<< "$(build_hook_input "FEAT-030")"
  [ "$status" -eq 2 ]
  [ ! -f "$TMPDIR_TEST/.sdlc/qa/.executing-active" ]
  [ ! -f "$TMPDIR_TEST/.sdlc/qa/.executing-qa-baseline-FEAT-030" ]
}
