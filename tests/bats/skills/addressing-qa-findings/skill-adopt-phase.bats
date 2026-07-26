#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats coverage for the addressing-qa-findings adopt-phase loop driver
# (FEAT-032 / Phase 2 / FR-4 / FR-5).
#
# Covers:
#   * happy path: multiple QA test files → all moved → stdout streams one
#     adopted path per line → exit 0 → adoption commit can be authored.
#   * FR-4 partial-success: first file adopts, second hits exit 2 → loop
#     aborts → prior path was emitted → failure return contract is verbatim.
#   * exit 2 on no QA files matching v1 globs (no-op).
#   * stderr surfaces the failing-script structured line.

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  ADDR_SCRIPTS="${PLUGIN_DIR}/skills/addressing-qa-findings/scripts"
  LOOP="${ADDR_SCRIPTS}/run-adopt-loop.sh"
  ADOPT="${ADDR_SCRIPTS}/adopt-qa-test.sh"

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

# --- happy path -------------------------------------------------------------

@test "adopt-loop: two QA test files → both adopted → stdout streams two paths → exit 0" {
  mkdir -p src tests/unit
  cat > src/foo.ts <<'EOF'
export const foo = 1;
EOF
  cat > src/bar.ts <<'EOF'
export const bar = 2;
EOF
  cat > tests/unit/foo.test.ts <<'EOF'
import { foo } from "../../src/foo";
test("foo", () => { expect(foo).toBe(1); });
EOF
  cat > tests/unit/bar.test.ts <<'EOF'
import { bar } from "../../src/bar";
test("bar", () => { expect(bar).toBe(2); });
EOF
  cat > tests/unit/qa-foo-edge.test.ts <<'EOF'
import { foo } from "../../src/foo";
test("foo-edge", () => { expect(foo).toBe(1); });
EOF
  cat > tests/unit/qa-bar-edge.test.ts <<'EOF'
import { bar } from "../../src/bar";
test("bar-edge", () => { expect(bar).toBe(2); });
EOF
  git add . && git commit -q -m "init"

  run bash "$LOOP"
  [ "$status" -eq 0 ]
  # stdout has both adopted paths, one per line, in glob order.
  echo "$output" | grep -qxF "tests/unit/bar.qa.test.ts"
  echo "$output" | grep -qxF "tests/unit/foo.qa.test.ts"
  [ -f "tests/unit/foo.qa.test.ts" ]
  [ -f "tests/unit/bar.qa.test.ts" ]
  [ ! -f "tests/unit/qa-foo-edge.test.ts" ]
  [ ! -f "tests/unit/qa-bar-edge.test.ts" ]
}

# --- FR-4 partial-success ---------------------------------------------------

@test "adopt-loop: first adopts, second has no peer → exit 1 with verbatim partial-success message" {
  mkdir -p src tests/unit
  cat > src/foo.ts <<'EOF'
export const foo = 1;
EOF
  cat > tests/unit/foo.test.ts <<'EOF'
import { foo } from "../../src/foo";
test("foo", () => { expect(foo).toBe(1); });
EOF
  # First QA file: peer exists → adoption succeeds.
  cat > tests/unit/qa-foo-edge.test.ts <<'EOF'
import { foo } from "../../src/foo";
test("foo-edge", () => { expect(foo).toBe(1); });
EOF
  # Second QA file: imports a SUT that has no peer test.
  cat > src/lonely.ts <<'EOF'
export const lonely = 2;
EOF
  cat > tests/unit/qa-lonely-edge.test.ts <<'EOF'
import { lonely } from "../../src/lonely";
test("lonely-edge", () => { expect(lonely).toBe(2); });
EOF
  git add . && git commit -q -m "init"

  run bash "$LOOP"
  [ "$status" -eq 1 ]
  # stdout has the first successful adopted path AND the verbatim failure line.
  echo "$output" | grep -qxF "tests/unit/foo.qa.test.ts"
  echo "$output" | grep -qxF "failed | adoption failed for tests/unit/qa-lonely-edge.test.ts; 1 adopted, 1 remaining"
  # The first move went through; the second QA file is still on disk.
  [ -f "tests/unit/foo.qa.test.ts" ]
  [ -f "tests/unit/qa-lonely-edge.test.ts" ]
}

@test "adopt-loop: first file fails outright → exit 1 with 0 adopted" {
  mkdir -p src tests/unit
  cat > src/lonely.ts <<'EOF'
export const lonely = 2;
EOF
  cat > tests/unit/qa-lonely-only.test.ts <<'EOF'
import { lonely } from "../../src/lonely";
test("lonely-only", () => { expect(lonely).toBe(2); });
EOF
  git add . && git commit -q -m "init"

  run bash "$LOOP"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qxF "failed | adoption failed for tests/unit/qa-lonely-only.test.ts; 0 adopted, 1 remaining"
}

# --- empty / no-op ----------------------------------------------------------

@test "adopt-loop: no committed QA files matching v1 globs → exit 2" {
  printf 'placeholder\n' > README
  git add . && git commit -q -m "init"

  run bash "$LOOP"
  [ "$status" -eq 2 ]
}

# --- stderr passthrough -----------------------------------------------------

@test "adopt-loop: stderr surfaces the failing-script structured line" {
  mkdir -p src tests/unit
  cat > src/lonely.ts <<'EOF'
export const lonely = 2;
EOF
  cat > tests/unit/qa-lonely.test.ts <<'EOF'
import { lonely } from "../../src/lonely";
test("lonely", () => { expect(lonely).toBe(2); });
EOF
  git add . && git commit -q -m "init"

  run bash -c "bash \"$LOOP\" 2>&1 1>/dev/null || true"
  echo "$output" | grep -qF "adopt-qa-test: tests/unit/qa-lonely.test.ts: no existing peer test found for any imported SUT"
}
