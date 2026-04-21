#!/usr/bin/env bats
# Bats fixture for resolve-requirement-doc.sh (FR-3).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  RESOLVE="${SCRIPT_DIR}/resolve-requirement-doc.sh"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: single FEAT-001 match prints the path and exits 0" {
  mkdir -p requirements/features
  : > requirements/features/FEAT-001-some-feature.md
  run bash "$RESOLVE" FEAT-001
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/features/FEAT-001-some-feature.md" ]
}

@test "happy path: CHORE-023 resolves to chores dir" {
  mkdir -p requirements/chores
  : > requirements/chores/CHORE-023-cleanup.md
  run bash "$RESOLVE" CHORE-023
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/chores/CHORE-023-cleanup.md" ]
}

@test "happy path: BUG-011 resolves to bugs dir" {
  mkdir -p requirements/bugs
  : > requirements/bugs/BUG-011-null-crash.md
  run bash "$RESOLVE" BUG-011
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/bugs/BUG-011-null-crash.md" ]
}

@test "AC-10: FEAT-020 resolves to this feature's doc in the real repo" {
  cd "$REPO_ROOT"
  run bash "$RESOLVE" FEAT-020
  [ "$status" -eq 0 ]
  [ "$output" = "requirements/features/FEAT-020-plugin-shared-scripts-library.md" ]
}

@test "zero matches: exit 1 with 'error: no file matches'" {
  mkdir -p requirements/features
  run bash "$RESOLVE" FEAT-999
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: no file matches FEAT-999"* ]]
}

@test "multiple matches: exit 2 with 'error: ambiguous' and candidate list" {
  mkdir -p requirements/features
  : > requirements/features/FEAT-001-alpha.md
  : > requirements/features/FEAT-001-beta.md
  run bash "$RESOLVE" FEAT-001
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: ambiguous"* ]]
  [[ "$output" == *"FEAT-001-alpha.md"* ]]
  [[ "$output" == *"FEAT-001-beta.md"* ]]
}

@test "lowercase ID: exit 3 (malformed)" {
  run bash "$RESOLVE" feat-001
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"malformed"* ]]
}

@test "missing arg: exit 3 (usage)" {
  run bash "$RESOLVE"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
}

@test "unknown prefix: exit 3 (malformed)" {
  run bash "$RESOLVE" TASK-001
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
}

@test "missing numeric suffix: exit 3 (malformed)" {
  run bash "$RESOLVE" FEAT-abc
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
}
