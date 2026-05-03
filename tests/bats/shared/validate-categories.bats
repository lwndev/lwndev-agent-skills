#!/usr/bin/env bats
# Bats fixture for validate-categories.sh (CHORE-036 item 1.4).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/scripts" && pwd)"
  VALIDATE="${SCRIPT_DIR}/validate-categories.sh"
}

# ---------- FEAT branch (silent no-op) ----------

@test "FEAT: exits 0 silently regardless of category arg" {
  run bash "$VALIDATE" FEAT anything
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "FEAT: exits 0 with empty category" {
  run bash "$VALIDATE" FEAT ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- CHORE happy paths ----------

@test "CHORE: accepts dependencies" {
  run bash "$VALIDATE" CHORE dependencies
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CHORE: accepts documentation" {
  run bash "$VALIDATE" CHORE documentation
  [ "$status" -eq 0 ]
}

@test "CHORE: accepts refactoring" {
  run bash "$VALIDATE" CHORE refactoring
  [ "$status" -eq 0 ]
}

@test "CHORE: accepts configuration" {
  run bash "$VALIDATE" CHORE configuration
  [ "$status" -eq 0 ]
}

@test "CHORE: accepts cleanup" {
  run bash "$VALIDATE" CHORE cleanup
  [ "$status" -eq 0 ]
}

# ---------- CHORE rejection ----------

@test "CHORE: rejects unknown category with exit 2 and error on stderr" {
  run bash "$VALIDATE" CHORE bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid chore category 'bogus'"* ]]
  [[ "$output" == *"dependencies"* ]]
  [[ "$output" == *"documentation"* ]]
  [[ "$output" == *"refactoring"* ]]
  [[ "$output" == *"configuration"* ]]
  [[ "$output" == *"cleanup"* ]]
}

@test "CHORE: rejects bug-only category 'security' with exit 2" {
  run bash "$VALIDATE" CHORE security
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid chore category 'security'"* ]]
}

# ---------- BUG happy paths ----------

@test "BUG: accepts runtime-error" {
  run bash "$VALIDATE" BUG runtime-error
  [ "$status" -eq 0 ]
}

@test "BUG: accepts logic-error" {
  run bash "$VALIDATE" BUG logic-error
  [ "$status" -eq 0 ]
}

@test "BUG: accepts ui-defect" {
  run bash "$VALIDATE" BUG ui-defect
  [ "$status" -eq 0 ]
}

@test "BUG: accepts performance" {
  run bash "$VALIDATE" BUG performance
  [ "$status" -eq 0 ]
}

@test "BUG: accepts security" {
  run bash "$VALIDATE" BUG security
  [ "$status" -eq 0 ]
}

@test "BUG: accepts regression" {
  run bash "$VALIDATE" BUG regression
  [ "$status" -eq 0 ]
}

# ---------- BUG rejection ----------

@test "BUG: rejects unknown category with exit 2 and error on stderr" {
  run bash "$VALIDATE" BUG bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid bug category 'bogus'"* ]]
  [[ "$output" == *"runtime-error"* ]]
  [[ "$output" == *"logic-error"* ]]
  [[ "$output" == *"ui-defect"* ]]
  [[ "$output" == *"performance"* ]]
  [[ "$output" == *"security"* ]]
  [[ "$output" == *"regression"* ]]
}

@test "BUG: rejects chore-only category 'cleanup' with exit 2" {
  run bash "$VALIDATE" BUG cleanup
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid bug category 'cleanup'"* ]]
}

# ---------- usage and type errors ----------

@test "missing args: exit 2 with usage error" {
  run bash "$VALIDATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: usage:"* ]]
}

@test "single arg: exit 2 with usage error" {
  run bash "$VALIDATE" CHORE
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: usage:"* ]]
}

@test "invalid type (lowercase): exit 2" {
  run bash "$VALIDATE" chore documentation
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid type 'chore'"* ]]
}

@test "invalid type (FEATURE): exit 2" {
  run bash "$VALIDATE" FEATURE bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: invalid type 'FEATURE'"* ]]
}
