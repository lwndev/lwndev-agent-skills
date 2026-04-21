#!/usr/bin/env bats
# Bats fixture for next-id.sh (FR-1).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  NEXT_ID="${SCRIPT_DIR}/next-id.sh"
  TMPDIR_TEST="$(mktemp -d)"
  ORIG_PWD="$PWD"
  cd "$TMPDIR_TEST"
  mkdir -p requirements/features requirements/chores requirements/bugs
}

teardown() {
  cd "$ORIG_PWD"
  rm -rf "$TMPDIR_TEST"
}

@test "happy path: returns 004 after FEAT-001..003" {
  touch requirements/features/FEAT-001-alpha.md
  touch requirements/features/FEAT-002-beta.md
  touch requirements/features/FEAT-003-gamma.md
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "004" ]
}

@test "empty directory: returns 001" {
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "001" ]
}

@test "missing directory: returns 001" {
  rm -rf requirements/features
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "001" ]
}

@test "missing arg: exit 2 with error on stderr" {
  run bash "$NEXT_ID"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "invalid lowercase type: exit 2" {
  run bash "$NEXT_ID" feat
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "invalid type (FEATURE): exit 2" {
  run bash "$NEXT_ID" FEATURE
  [ "$status" -eq 2 ]
}

@test "CHORE type uses requirements/chores" {
  touch requirements/chores/CHORE-001-foo.md
  touch requirements/chores/CHORE-005-bar.md
  run bash "$NEXT_ID" CHORE
  [ "$status" -eq 0 ]
  [ "$output" = "006" ]
}

@test "BUG type uses requirements/bugs" {
  touch requirements/bugs/BUG-001-foo.md
  run bash "$NEXT_ID" BUG
  [ "$status" -eq 0 ]
  [ "$output" = "002" ]
}

@test "idempotency: two invocations without new files return same value" {
  touch requirements/features/FEAT-007-foo.md
  run bash "$NEXT_ID" FEAT
  first="$output"
  run bash "$NEXT_ID" FEAT
  second="$output"
  [ "$first" = "$second" ]
  [ "$first" = "008" ]
}

@test "AC-8 contract: with FEAT-001..019 present, returns 020" {
  for n in $(seq -f "%03g" 1 19); do
    touch "requirements/features/FEAT-${n}-test.md"
  done
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "020" ]
}

@test "ignores non-matching files in directory" {
  touch requirements/features/FEAT-001-foo.md
  touch requirements/features/README.md
  touch requirements/features/notes.txt
  touch requirements/features/FEAT-abc-broken.md
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "002" ]
}

@test "handles gaps in numbering: takes max and adds 1" {
  touch requirements/features/FEAT-001-a.md
  touch requirements/features/FEAT-010-b.md
  run bash "$NEXT_ID" FEAT
  [ "$status" -eq 0 ]
  [ "$output" = "011" ]
}
