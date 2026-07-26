#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats coverage for adopt-qa-test.sh (FEAT-032 / Phase 2 / FR-5 / FR-6 / FR-13 / BUG-025).
#
# Covers per-framework dispatch + exit-code surface:
#   * Vitest happy path — TS file with relative import → peer test located →
#     git mv succeeds → stdout prints new path.
#   * Bats happy path — load directive → peer .bats located → git mv succeeds.
#   * Exit-2 — no resolvable imports.
#   * Exit-0 — multi-SUT vitest: picks lexicographically-first peer by full path (BUG-025 RC-1).
#   * Exit-0 — multi-SUT vitest full-path vs basename determinism (BUG-025 RC-1 P0).
#   * Exit-0 — <<MULTI>> parallel-root + singular peer: picks singular peer (BUG-025 RC-1 P2).
#   * Exit-0 — multi-load bats: picks lexicographically-first peer (BUG-025 RC-2).
#   * Exit-2 — no existing peer test (genuine no-peer guard unchanged).
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

# ---- Exit-2: <<MULTI>> sentinel with no singular peer (ambiguous reason) -----

@test "exit 2 MULTI sentinel with no other singular peer: multi-peer reason verbatim" {
  # Single SUT (widget) base matches 2+ peers under tests/ -> <<MULTI>> sentinel.
  # No other import resolves singularly -> seen_count=0, multi_seen=1.
  # Must exit 2 with the multi-peer reason, NOT "no existing peer test found".
  mkdir -p src tests/unit tests/integration
  cat > src/widget.ts <<'EOF'
export const widget = 0;
EOF
  cat > tests/unit/widget.test.ts <<'EOF'
test("widget unit", () => {});
EOF
  cat > tests/integration/widget.test.ts <<'EOF'
test("widget int", () => {});
EOF
  cat > tests/unit/qa-widget-only.test.ts <<'EOF'
import { widget } from "../../src/widget";
test("widget", () => {});
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-widget-only.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopt-qa-test: tests/unit/qa-widget-only.test.ts: multiple plausible peer tests match a single imported SUT; cannot disambiguate"* ]]
  # QA file untouched (no adoption occurred)
  [ -f "tests/unit/qa-widget-only.test.ts" ]
}

# ---- Exit-0: multi-SUT vitest picks lexicographically-first peer -----------

@test "exit 0 when QA test imports multiple SUTs: picks lex-first peer by full path" {
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
  # Both peers exist; lex-first by full path: tests/unit/a.test.ts < tests/unit/b.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "tests/unit/a.qa.test.ts" ]
  [ -f "tests/unit/a.qa.test.ts" ]
  [ ! -f "tests/unit/qa-cross.test.ts" ]
}

# ---- Exit-0: multi-SUT full-path vs basename determinism -------------------

@test "exit 0 multi-SUT: full-path sort, not basename sort, determines winner" {
  # peers: src/alpha/z.test.ts and src/zeta/a.test.ts
  # Basename order: a.test.ts < z.test.ts  -> would pick src/zeta/a
  # Full-path order: src/alpha/z.test.ts < src/zeta/a.test.ts -> must pick src/alpha/z
  mkdir -p src/alpha src/zeta tests/unit
  cat > src/alpha/z.ts <<'EOF'
export const z = 26;
EOF
  cat > src/zeta/a.ts <<'EOF'
export const a = 1;
EOF
  cat > src/alpha/z.test.ts <<'EOF'
import { z } from "./z";
test("z", () => { expect(z).toBe(26); });
EOF
  cat > src/zeta/a.test.ts <<'EOF'
import { a } from "./a";
test("a", () => { expect(a).toBe(1); });
EOF
  cat > tests/unit/qa-multi-determinism.test.ts <<'EOF'
import { z } from "../../src/alpha/z";
import { a } from "../../src/zeta/a";
test("cross", () => { expect(z + a).toBe(27); });
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-multi-determinism.test.ts
  # Full-path lex: src/alpha/z.test.ts < src/zeta/a.test.ts -> winner is src/alpha/z
  [ "$status" -eq 0 ]
  [ "$output" = "src/alpha/z.qa.test.ts" ]
  [ -f "src/alpha/z.qa.test.ts" ]
  [ ! -f "tests/unit/qa-multi-determinism.test.ts" ]
}

# ---- Exit-0: <<MULTI>> parallel-root + singular peer -----------------------

@test "exit 0 MULTI sentinel: singular peer from other import takes lex-first pick" {
  # One SUT (widget) hits the <<MULTI>> sentinel (two tests/ matches).
  # Another SUT (helper) has exactly one peer.
  # Result: seen_count=1 (helper's peer); <<MULTI>> does NOT exit 2; pick helper.
  mkdir -p src tests/unit tests/integration
  cat > src/helper.ts <<'EOF'
export const helper = 42;
EOF
  cat > src/widget.ts <<'EOF'
export const widget = 0;
EOF
  # Two matches for 'widget' in tests/ -> triggers <<MULTI>> sentinel
  cat > tests/unit/widget.test.ts <<'EOF'
test("widget unit", () => {});
EOF
  cat > tests/integration/widget.test.ts <<'EOF'
test("widget int", () => {});
EOF
  # Singular match for 'helper'
  cat > tests/unit/helper.test.ts <<'EOF'
import { helper } from "../../src/helper";
test("helper", () => { expect(helper).toBe(42); });
EOF
  cat > tests/unit/qa-multi-sentinel.test.ts <<'EOF'
import { widget } from "../../src/widget";
import { helper } from "../../src/helper";
test("combined", () => {});
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/unit/qa-multi-sentinel.test.ts
  # <<MULTI>> for widget is skipped; helper resolves to tests/unit/helper.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "tests/unit/helper.qa.test.ts" ]
  [ -f "tests/unit/helper.qa.test.ts" ]
  [ ! -f "tests/unit/qa-multi-sentinel.test.ts" ]
}

# ---- Exit-0: multi-load bats picks lexicographically-first peer ------------

@test "exit 0 when bats QA test loads multiple scripts each with a peer .bats" {
  mkdir -p tests/bats/shared tests/bats/qa
  cat > tests/bats/shared/alpha.sh <<'EOF'
#!/usr/bin/env bash
echo "alpha"
EOF
  chmod +x tests/bats/shared/alpha.sh
  cat > tests/bats/shared/zeta.sh <<'EOF'
#!/usr/bin/env bash
echo "zeta"
EOF
  chmod +x tests/bats/shared/zeta.sh
  cat > tests/bats/shared/alpha.bats <<'EOF'
#!/usr/bin/env bats
@test "alpha" { :; }
EOF
  cat > tests/bats/shared/zeta.bats <<'EOF'
#!/usr/bin/env bats
@test "zeta" { :; }
EOF
  cat > tests/bats/qa/qa-multi-load.bats <<'EOF'
#!/usr/bin/env bats
load '../shared/alpha.sh'
load '../shared/zeta.sh'
@test "combined" { :; }
EOF
  git add . && git commit -q -m "init"

  run bash "$ADOPT" tests/bats/qa/qa-multi-load.bats
  # Lex-first by full path: tests/bats/shared/alpha.bats < tests/bats/shared/zeta.bats
  [ "$status" -eq 0 ]
  [ "$output" = "tests/bats/shared/alpha.qa.bats" ]
  [ -f "tests/bats/shared/alpha.qa.bats" ]
  [ ! -f "tests/bats/qa/qa-multi-load.bats" ]
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
