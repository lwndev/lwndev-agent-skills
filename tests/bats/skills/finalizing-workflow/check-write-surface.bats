#!/usr/bin/env bats
# check-write-surface.bats — Regression tests for
# finalizing-workflow/scripts/check-write-surface.sh (BUG-024 pre-merge guard).
#
# All tests operate on a real temp git repo. No live GitHub / network calls.
#
# Cases:
#   1. committed git rm of out-of-surface qa-* file past baseline → exit 2 + path
#   2. committed git mv rename of out-of-surface file → exit 2 + both paths
#   3. commit touching ONLY the requirement doc (BK-5 allowed) → exit 0
#   4. no baseline arg → exit 0 (cannot verify; do not block)
#   5. staged (uncommitted) out-of-surface deletion → exit 2 + "(staged)"
#   6. working-tree unstaged `rm` of out-of-surface file → exit 2 + "(working tree)"
#   7. multiple offending committed paths → all enumerated
#   8. clean tree at baseline → exit 0

CHECK="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)/check-write-surface.sh"

setup() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  mkdir -p tests/unit requirements/bugs
  echo "source" > src.ts
  echo "qa content" > tests/unit/qa-BUG-018-something.test.ts
  echo "other file" > some-other-file.ts
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

@test "1. committed git rm of qa-* file past baseline blocks (exit 2, path enumerated)" {
  cd "$REPO"
  git rm -q tests/unit/qa-BUG-018-something.test.ts
  git commit -q -m "chore: remove qa file"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts"* ]]
  [[ "$output" == *"write-surface guard"* ]]
}

@test "2. committed git mv rename of out-of-surface file blocks (exit 2, both paths)" {
  cd "$REPO"
  git mv tests/unit/qa-BUG-018-something.test.ts tests/unit/something.qa.test.ts
  git commit -q -m "chore: rename qa file"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts"* ]]
  [[ "$output" == *"tests/unit/something.qa.test.ts"* ]]
}

@test "3. commit touching ONLY the requirement doc (BK-5) is allowed (exit 0)" {
  cd "$REPO"
  echo "- updated" >> requirements/bugs/BUG-024-some-bug.md
  git add requirements/bugs/BUG-024-some-bug.md
  git commit -q -m "chore(BUG-024): finalize requirement document"

  run_check
  [ "$status" -eq 0 ]
}

@test "4. no baseline argument → exit 0 (cannot verify, does not block)" {
  run_check ""
  [ "$status" -eq 0 ]
}

@test "5. staged (uncommitted) out-of-surface deletion blocks (exit 2, staged)" {
  cd "$REPO"
  git rm -q --cached tests/unit/qa-BUG-018-something.test.ts

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts (staged)"* ]]
}

@test "6. working-tree unstaged rm of out-of-surface file blocks (exit 2, working tree)" {
  cd "$REPO"
  rm tests/unit/qa-BUG-018-something.test.ts

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts (working tree)"* ]]
}

@test "7. multiple offending committed paths → all enumerated" {
  cd "$REPO"
  git rm -q tests/unit/qa-BUG-018-something.test.ts some-other-file.ts
  git commit -q -m "chore: remove two files"

  run_check
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests/unit/qa-BUG-018-something.test.ts"* ]]
  [[ "$output" == *"some-other-file.ts"* ]]
}

@test "8. clean tree at baseline → exit 0" {
  run_check
  [ "$status" -eq 0 ]
}
