#!/usr/bin/env bats
# Bats coverage for adopt-qa-test.sh (FEAT-032 / Phase 2 / FR-5 / FR-6 / FR-13).
#
# Covers per-framework dispatch + exit-code surface:
#   * Vitest happy path — TS file with relative import → peer test located →
#     git mv succeeds → stdout prints new path.
#   * Bats happy path — load directive → peer .bats located → git mv succeeds.
#   * Exit-2 — no resolvable imports.
#   * Exit-2 — multiple plausible peer tests.
#   * Exit-2 — no existing peer test.
#   * Exit-2 — pytest stub (framework not supported in v1).
#   * Exit-2 — go-test stub (framework not supported in v1).
#   * Exit-1 — git mv fails (target already exists).
#   * Structured stderr message format pinned per FR-5.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts" && pwd)"
  ADOPT="${SCRIPT_DIR}/adopt-qa-test.sh"

  TMPDIR_TEST="$(mktemp -d)"
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"

  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---- Vitest happy path ------------------------------------------------------

@test "vitest happy path: TS QA test → adopted next to peer test" {
  mkdir -p src tests/unit
  cat > src/buggy-fn.ts <<'EOF'
export function buggyFn(x: number): number {
  return x + 1;
}
EOF
  cat > tests/unit/buggy-fn.test.ts <<'EOF'
import { buggyFn } from "../../src/buggy-fn";
test("works", () => { expect(buggyFn(1)).toBe(2); });
EOF
  cat > tests/unit/qa-input-validation.test.ts <<'EOF'
import { buggyFn } from "../../src/buggy-fn";
test("rejects negative", () => { expect(() => buggyFn(-1)).toThrow(); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-input-validation.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "tests/unit/buggy-fn.qa.test.ts" ]
  [ -f "tests/unit/buggy-fn.qa.test.ts" ]
  [ ! -f "tests/unit/qa-input-validation.test.ts" ]
}

# ---- Bats happy path --------------------------------------------------------

@test "bats happy path: QA bats file with load directive → adopted next to peer .bats" {
  mkdir -p tests/bats/shared tests/bats/qa
  cat > tests/bats/shared/check-acceptance.sh <<'EOF'
#!/usr/bin/env bash
echo "noop"
EOF
  chmod +x tests/bats/shared/check-acceptance.sh
  cat > tests/bats/shared/check-acceptance.bats <<'EOF'
#!/usr/bin/env bats
@test "trivial" { :; }
EOF
  cat > tests/bats/qa/qa-acceptance-edge.bats <<'EOF'
#!/usr/bin/env bats
load '../shared/check-acceptance.sh'
@test "edge case" { :; }
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/bats/qa/qa-acceptance-edge.bats
  [ "$status" -eq 0 ]
  [ "$output" = "tests/bats/shared/check-acceptance.qa.bats" ]
  [ -f "tests/bats/shared/check-acceptance.qa.bats" ]
  [ ! -f "tests/bats/qa/qa-acceptance-edge.bats" ]
}

# ---- Exit-2: no resolvable imports -----------------------------------------

@test "exit 2 when QA test has no resolvable imports" {
  mkdir -p tests/unit
  cat > tests/unit/qa-orphan.test.ts <<'EOF'
test("orphan", () => { expect(true).toBe(true); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-orphan.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/unit/qa-orphan.test.ts: no resolvable imports found in QA test"* ]]
}

# ---- Exit-2: no existing peer test -----------------------------------------

@test "exit 2 when no existing peer test for imported SUT" {
  mkdir -p src tests/unit
  cat > src/lonely.ts <<'EOF'
export const lonely = 1;
EOF
  cat > tests/unit/qa-lonely-edge.test.ts <<'EOF'
import { lonely } from "../../src/lonely";
test("edge", () => { expect(lonely).toBe(1); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-lonely-edge.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/unit/qa-lonely-edge.test.ts: no existing peer test found for any imported SUT"* ]]
}

# ---- Exit-2: multiple plausible peer tests ---------------------------------

@test "exit 2 when QA test imports multiple SUTs each with a peer test" {
  mkdir -p src tests/unit
  cat > src/a.ts <<'EOF'
export const a = 1;
EOF
  cat > src/b.ts <<'EOF'
export const b = 2;
EOF
  cat > tests/unit/a.test.ts <<'EOF'
import { a } from "../../src/a";
test("a", () => { expect(a).toBe(1); });
EOF
  cat > tests/unit/b.test.ts <<'EOF'
import { b } from "../../src/b";
test("b", () => { expect(b).toBe(2); });
EOF
  cat > tests/unit/qa-cross.test.ts <<'EOF'
import { a } from "../../src/a";
import { b } from "../../src/b";
test("cross", () => { expect(a + b).toBe(3); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-cross.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/unit/qa-cross.test.ts: multiple plausible peer tests found; expected exactly one"* ]]
}

# ---- Exit-2: framework not supported in v1 ---------------------------------

@test "exit 2 with structured pytest stub for .py extension" {
  mkdir -p tests
  cat > tests/qa_input.py <<'EOF'
def test_input(): assert True
EOF
  # Must be named with qa- prefix for typical naming, but the script keys off
  # extension only. Use an actual .py file.
  mv tests/qa_input.py tests/qa-input.py
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/qa-input.py
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/qa-input.py: framework not supported in v1: pytest"* ]]
}

@test "exit 2 with structured go-test stub for .go extension" {
  mkdir -p pkg
  cat > pkg/qa-input.go <<'EOF'
package pkg
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" pkg/qa-input.go
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: pkg/qa-input.go: framework not supported in v1: go-test"* ]]
}

# ---- Exit-1: git mv target already exists ----------------------------------

@test "exit 1 when target sibling path already exists" {
  mkdir -p src tests/unit
  cat > src/buggy.ts <<'EOF'
export const buggy = 1;
EOF
  cat > tests/unit/buggy.test.ts <<'EOF'
import { buggy } from "../../src/buggy";
test("p", () => { expect(buggy).toBe(1); });
EOF
  cat > tests/unit/buggy.qa.test.ts <<'EOF'
// pre-existing collision
EOF
  cat > tests/unit/qa-collision.test.ts <<'EOF'
import { buggy } from "../../src/buggy";
test("c", () => { expect(buggy).toBe(1); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-collision.test.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"target path already exists"* ]]
}

# ---- Missing arg ------------------------------------------------------------

@test "exit 2 with usage when no arg" {
  run bash "$ADOPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected exactly 1 argument"* ]]
}

@test "exit 2 when path does not exist" {
  run bash "$ADOPT" "tests/unit/missing.qa.ts"
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/unit/missing.qa.ts: file not found"* ]]
}
