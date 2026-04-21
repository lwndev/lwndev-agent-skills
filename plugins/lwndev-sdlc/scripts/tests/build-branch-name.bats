#!/usr/bin/env bats
# Bats fixture for build-branch-name.sh (FR-4).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  BUILD="${SCRIPT_DIR}/build-branch-name.sh"
}

@test "happy path: feat FEAT-001 'scaffold skill' → feat/FEAT-001-scaffold-skill" {
  run bash "$BUILD" feat FEAT-001 "scaffold skill"
  [ "$status" -eq 0 ]
  [ "$output" = "feat/FEAT-001-scaffold-skill" ]
}

@test "stopword summary: feat FEAT-001 'The Art of War' → feat/FEAT-001-art-war" {
  run bash "$BUILD" feat FEAT-001 "The Art of War"
  [ "$status" -eq 0 ]
  [ "$output" = "feat/FEAT-001-art-war" ]
}

@test "chore type: chore CHORE-023 'cleanup deps' → chore/CHORE-023-cleanup-deps" {
  run bash "$BUILD" chore CHORE-023 "cleanup deps"
  [ "$status" -eq 0 ]
  [ "$output" = "chore/CHORE-023-cleanup-deps" ]
}

@test "fix type: fix BUG-011 'null crash' → fix/BUG-011-null-crash" {
  run bash "$BUILD" fix BUG-011 "null crash"
  [ "$status" -eq 0 ]
  [ "$output" = "fix/BUG-011-null-crash" ]
}

@test "invalid type 'foobar': exit 2" {
  run bash "$BUILD" foobar FEAT-001 "scaffold skill"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"invalid type"* ]]
}

@test "invalid type 'feature' (long form rejected): exit 2" {
  run bash "$BUILD" feature FEAT-001 "scaffold skill"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "empty summary (all stopwords): exit 1 propagated from slugify" {
  run bash "$BUILD" feat FEAT-001 "the and or"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error:"* ]]
}

@test "punctuation-only summary: exit 1 propagated from slugify" {
  run bash "$BUILD" feat FEAT-001 "!!"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error:"* ]]
}

@test "missing args (zero): exit 2" {
  run bash "$BUILD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
}

@test "missing args (two): exit 2" {
  run bash "$BUILD" feat FEAT-001
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "slugify is called via the sibling script regardless of CWD" {
  cd /tmp
  run bash "$BUILD" feat FEAT-001 "scaffold skill"
  [ "$status" -eq 0 ]
  [ "$output" = "feat/FEAT-001-scaffold-skill" ]
}
