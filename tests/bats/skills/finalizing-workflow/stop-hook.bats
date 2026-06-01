#!/usr/bin/env bats
# stop-hook.bats — Regression tests for finalizing-workflow/scripts/stop-hook.sh.
#
# All tests operate on a real temp git repo. No live GitHub / network calls.
#
# Cases:
#   1. git rm of out-of-surface qa-* file committed past baseline → exit 2 + path enumerated
#   2. git mv rename of out-of-surface file committed past baseline → exit 2 + both paths enumerated
#   3. Commit touching ONLY the requirement doc (BK-5 allowed) → exit 0
#   4. No active marker → exit 0 (no-op)
#   5. Active marker present but no baseline file → exit 2 (fail closed)

STOP_HOOK="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)/stop-hook.sh"

# Minimal stop-hook JSON (no special flags).
HOOK_INPUT='{"stop_hook_active": false, "last_assistant_message": "done"}'

setup() {
  # Create a real git repo so git commands inside the hook work.
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  # Seed the repo with some tracked files at the initial commit.
  mkdir -p tests/unit tests/bats/qa requirements/bugs
  echo "source" > src.ts
  echo "qa content" > tests/unit/qa-BUG-018-something.test.ts
  echo "other file" > some-other-file.ts
  echo "req doc" > requirements/bugs/BUG-024-some-bug.md
  git add .
  git commit -q -m "initial"

  # Record this as the baseline (before any finalize-related changes).
  BASELINE_SHA="$(git rev-parse HEAD)"

  # Create the .sdlc/finalize directory for markers.
  mkdir -p .sdlc/finalize
}

teardown() {
  if [ -n "${REPO:-}" ] && [ -d "$REPO" ]; then
    rm -rf "$REPO"
  fi
}

# Write the active marker and baseline SHA.
write_markers() {
  local id="${1:-BUG-024}"
  touch "$REPO/.sdlc/finalize/.finalize-active"
  echo "$BASELINE_SHA" > "$REPO/.sdlc/finalize/.finalize-baseline-${id}"
}

# Run the stop hook from inside the repo, feeding HOOK_INPUT on stdin.
run_hook() {
  cd "$REPO"
  run bash "$STOP_HOOK" <<< "$HOOK_INPUT"
}

# ---------------------------------------------------------------------------
# Case 1: git rm of out-of-surface qa-* file committed past baseline -> exit 2
# ---------------------------------------------------------------------------
@test "1. committed git rm of qa-* file past baseline blocks Stop (exit 2, path enumerated)" {
  write_markers

  cd "$REPO"
  # Commit a deletion of the qa-* file after the baseline.
  git rm -q tests/unit/qa-BUG-018-something.test.ts
  git commit -q -m "chore: remove qa file"

  run_hook

  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts"* ]]
}

# ---------------------------------------------------------------------------
# Case 2: git mv rename of out-of-surface file committed past baseline -> exit 2
# ---------------------------------------------------------------------------
@test "2. committed git mv rename of out-of-surface file blocks Stop (exit 2, both paths enumerated)" {
  write_markers

  cd "$REPO"
  # Commit a rename (git mv) of the qa-* file after the baseline.
  git mv tests/unit/qa-BUG-018-something.test.ts tests/unit/qa-BUG-018-something.qa.test.ts
  git commit -q -m "chore: rename qa file"

  run_hook

  [ "$status" -eq 2 ]
  # Both old and new paths must appear in the error output.
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts"* ]]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.qa.test.ts"* ]]
}

# ---------------------------------------------------------------------------
# Case 3: commit touching ONLY the requirement doc -> exit 0 (BK-5 allowed)
# ---------------------------------------------------------------------------
@test "3. BK-5 commit (requirement doc only) past baseline exits 0" {
  write_markers

  cd "$REPO"
  # Commit an update to only the requirement doc (BK-5 bookkeeping).
  echo "Status: Completed" >> requirements/bugs/BUG-024-some-bug.md
  git add requirements/bugs/BUG-024-some-bug.md
  git commit -q -m "chore(BUG-024): finalize requirement document"

  run_hook

  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Case 4: no active marker -> exit 0 (hook no-ops)
# ---------------------------------------------------------------------------
@test "4. no active marker exits 0 (hook is a no-op)" {
  # Do NOT write markers.
  cd "$REPO"

  # Commit something that would be blocked if markers were present.
  git rm -q tests/unit/qa-BUG-018-something.test.ts
  git commit -q -m "chore: remove qa file"

  run_hook

  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Case 5: active marker present but no baseline file -> fail closed (exit 2)
# ---------------------------------------------------------------------------
@test "5. active marker present but no baseline file fails closed (exit 2)" {
  cd "$REPO"
  # Write only the active marker, no baseline file.
  touch .sdlc/finalize/.finalize-active

  run_hook

  [ "$status" -eq 2 ]
  [[ "$output" == *"no baseline file found"* ]]
}
