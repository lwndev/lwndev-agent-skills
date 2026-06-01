#!/usr/bin/env bats
# check-write-surface.qa.bats — Adopted QA regression for the BUG-024 pre-merge
# write-surface guard (finalizing-workflow/scripts/check-write-surface.sh).
#
# Adopted from the ephemeral executing-qa test qa-BUG-024-write-surface.bats
# (manual adoption — adopt-qa-test.sh cannot resolve a load/source peer for an
# inline-path bats test, issue #304). Sibling of check-write-surface.bats.
# Targets gaps NOT covered by the developer's check-write-surface.bats, which
# exercises only git rm / git mv:
#   - content edit (M-status) to an out-of-surface tracked file (committed,
#     staged, working-tree) — the plan's Inputs P1 scenario
#   - awkward filenames (space, leading dash, Unicode, nested dir) — Inputs P2,
#     the only place a parse/word-splitting bug could hide
#   - bulk blast-radius enumeration — Inputs P0, every offending path listed,
#     no "partial allow"
#
# All tests run against a real temp git repo. No network / GitHub calls.

CHECK="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)/check-write-surface.sh"

setup() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config core.quotePath true

  mkdir -p tests/unit requirements/bugs src
  echo "qa content" > tests/unit/qa-BUG-018-something.test.ts
  echo "lib source" > src/lib.ts
  echo "req doc" > requirements/bugs/BUG-024-some-bug.md
  git add .
  git commit -q -m "initial"

  BASELINE_SHA="$(git rev-parse HEAD)"
}

teardown() {
  if [ -n "${REPO:-}" ] && [ -d "$REPO" ]; then
    rm -rf "$REPO"
  fi
}

run_check() {
  cd "$REPO"
  run bash "$CHECK" "${1-$BASELINE_SHA}"
}

# --- Inputs P1: content edit (M-status), not a delete/rename ----------------

@test "content edit committed past baseline to out-of-surface tracked file blocks (exit 2)" {
  cd "$REPO"
  echo "// sneaky edit" >> src/lib.ts
  git add src/lib.ts
  git commit -q -m "edit unrelated source"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"src/lib.ts"* ]]
}

@test "content edit STAGED (uncommitted) to out-of-surface tracked file blocks (exit 2, staged)" {
  cd "$REPO"
  echo "// staged edit" >> src/lib.ts
  git add src/lib.ts

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"src/lib.ts (staged)"* ]]
}

@test "content edit in WORKING TREE (unstaged) to out-of-surface tracked file blocks (exit 2, working tree)" {
  cd "$REPO"
  echo "// working-tree edit" >> src/lib.ts

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"src/lib.ts (working tree)"* ]]
}

@test "content edit to the requirement doc itself is allowed (exit 0)" {
  cd "$REPO"
  echo "- finalize note" >> requirements/bugs/BUG-024-some-bug.md
  git add requirements/bugs/BUG-024-some-bug.md
  git commit -q -m "chore(BUG-024): finalize requirement doc"

  run_check
  [ "$status" -eq 0 ]
}

# --- Inputs P2: awkward filenames (parse / word-splitting robustness) --------

@test "out-of-surface file with SPACES in path is detected and blocked (exit 2)" {
  cd "$REPO"
  echo "x" > "src/weird name.ts"
  git add -A
  git commit -q -m "add spaced file"

  run_check
  [ "$status" -eq 2 ]
  # quotePath may render the space-bearing path quoted; assert the stable stem.
  [[ "$output" == *"weird name.ts"* || "$output" == *"weird"*"name.ts"* ]]
}

@test "out-of-surface file with LEADING DASH is detected and not misparsed as a flag (exit 2)" {
  cd "$REPO"
  echo "x" > "src/-dashfile.ts"
  git add -A
  git commit -q -m "add dash file"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"dashfile.ts"* ]]
}

@test "out-of-surface file with UNICODE name is detected and blocked (exit 2)" {
  cd "$REPO"
  echo "x" > "src/café-données.ts"
  git add -A
  git commit -q -m "add unicode file"

  run_check
  [ "$status" -eq 2 ]
  # With quotePath on, non-ASCII is octal-escaped; assert the safe surrounding stem.
  [[ "$output" == *"src/caf"* ]]
}

@test "out-of-surface file in a DEEPLY NESTED dir is detected and blocked (exit 2)" {
  cd "$REPO"
  mkdir -p a/b/c/d
  echo "x" > a/b/c/d/deep.ts
  git add -A
  git commit -q -m "add nested file"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"a/b/c/d/deep.ts"* ]]
}

# --- Inputs P0: bulk blast radius — every offending path enumerated ----------

@test "bulk out-of-surface deletion enumerates EVERY offending path, no partial-allow (exit 2)" {
  cd "$REPO"
  for i in $(seq 1 30); do
    echo "qa $i" > "tests/unit/qa-BULK-${i}.test.ts"
  done
  git add -A
  git commit -q -m "seed bulk qa files"
  BASELINE_SHA="$(git rev-parse HEAD)"

  # Now bulk-rename all 30 out of the qa- prefix (FEAT-020 blast-radius modality).
  for i in $(seq 1 30); do
    git mv "tests/unit/qa-BULK-${i}.test.ts" "tests/unit/BULK-${i}.qa.test.ts"
  done
  git commit -q -m "bulk rename to dodge prefix glob"

  run_check
  [ "$status" -eq 2 ]
  # Every source AND destination path must appear — spot-check first, mid, last.
  [[ "$output" == *"tests/unit/qa-BULK-1.test.ts"* ]]
  [[ "$output" == *"tests/unit/BULK-1.qa.test.ts"* ]]
  [[ "$output" == *"tests/unit/qa-BULK-15.test.ts"* ]]
  [[ "$output" == *"tests/unit/qa-BULK-30.test.ts"* ]]
  [[ "$output" == *"tests/unit/BULK-30.qa.test.ts"* ]]
  # 30 renames × 2 paths (src+dst) = 60 offending lines, all enumerated.
  count="$(printf '%s\n' "$output" | grep -cE '(qa-BULK-|BULK-).*\.test\.ts')"
  [ "$count" -ge 60 ]
}

# --- Allowed: mixed commit touching ONLY requirement docs across types -------

@test "commit touching multiple requirement docs (across types) stays allowed (exit 0)" {
  cd "$REPO"
  mkdir -p requirements/features requirements/chores
  echo "f" > requirements/features/FEAT-001-x.md
  echo "c" > requirements/chores/CHORE-001-y.md
  echo "- note" >> requirements/bugs/BUG-024-some-bug.md
  git add -A
  git commit -q -m "bookkeeping across requirement docs"

  run_check
  [ "$status" -eq 0 ]
}
