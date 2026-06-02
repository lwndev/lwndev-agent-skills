#!/usr/bin/env bats
# QA (BUG-025) — adversarial coverage for adopt-qa-test.sh multi-SUT tolerance.
#
# SUT: plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts/adopt-qa-test.sh
# The SUT is a Bash script; capability-discovery reports vitest but run-framework
# is vitest-only, so these QA scenarios are Bats cases graded on exit code +
# stdout/stderr (npx bats returns non-zero if any case fails).
#
# Dimension map (QA-plan-BUG-025):
#   Inputs            -> multi-SUT pick, dedup, ext-normalization, zero-peer guard
#   State transitions -> idempotency, target-collision, git-mv-is-deletion
#   Cross-cutting     -> full-path-vs-basename determinism, reproducibility
#   Dependency        -> restored <<MULTI>>-no-singular ambiguity reason (RC fix 80653d1)

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../plugins/lwndev-sdlc/skills/addressing-qa-findings/scripts" && pwd)"
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

# ---- Inputs: 3+ distinct SUTs, peers in different dirs ----------------------

@test "[P0] 3 distinct SUTs each with a peer -> exit 0, picks lex-first peer by full path" {
  mkdir -p src/charlie src/alpha src/bravo tests/unit
  for s in charlie/c alpha/a bravo/b; do
    base="$(basename "$s")"
    dir="$(dirname "$s")"
    printf 'export const x=1;\n' > "src/${s}.ts"
    printf 'import { x } from "../../src/%s";\ntest("t",()=>{expect(x).toBe(1)});\n' "$s" \
      > "src/${dir}/${base}.test.ts"
  done
  cat > tests/unit/qa-multi.test.ts <<'EOF'
import { x } from "../../src/charlie/c";
import { x as y } from "../../src/alpha/a";
import { x as z } from "../../src/bravo/b";
test("multi", () => { expect(x + y + z).toBe(3); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-multi.test.ts
  [ "$status" -eq 0 ]
  # LC_ALL=C full-path sort: src/alpha/a.test.ts is first -> sibling under src/alpha
  [ "$output" = "src/alpha/a.qa.test.ts" ]
  [ -f "src/alpha/a.qa.test.ts" ]
  [ ! -f "tests/unit/qa-multi.test.ts" ]
}

# ---- Cross-cutting: full-path order, not basename, decides the winner -------

@test "[P0] basename order opposite to full-path order -> full path wins" {
  # Peers: src/zeta/a.test.ts (basename 'a') vs src/alpha/z.test.ts (basename 'z').
  # Basename sort would pick 'a' (src/zeta); full-path sort picks src/alpha/z.
  mkdir -p src/zeta src/alpha tests/unit
  printf 'export const a=1;\n' > src/zeta/a.ts
  printf 'export const z=1;\n' > src/alpha/z.ts
  printf 'import {a} from "../../src/zeta/a";\ntest("t",()=>{expect(a).toBe(1)});\n' > src/zeta/a.test.ts
  printf 'import {z} from "../../src/alpha/z";\ntest("t",()=>{expect(z).toBe(1)});\n' > src/alpha/z.test.ts
  cat > tests/unit/qa-order.test.ts <<'EOF'
import { a } from "../../src/zeta/a";
import { z } from "../../src/alpha/z";
test("order", () => { expect(a + z).toBe(2); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-order.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "src/alpha/z.qa.test.ts" ]
  [ ! -f "src/zeta/a.qa.test.ts" ]
}

# ---- Inputs: zero peers -> genuine no-peer guard must NOT weaken ------------

@test "[P0] imports SUTs with no peer test anywhere -> exit 2, no-peer reason" {
  mkdir -p src tests/unit
  printf 'export const x=1;\n' > src/lonely.ts
  cat > tests/unit/qa-nopeer.test.ts <<'EOF'
import { x } from "../../src/lonely";
test("nopeer", () => { expect(x).toBe(1); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-nopeer.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"no existing peer test found for any imported SUT"* ]]
  # File must remain — failed adoption does not delete.
  [ -f "tests/unit/qa-nopeer.test.ts" ]
}

# ---- Inputs: duplicate import of same SUT -> deduped, not mis-counted -------

@test "[P1] same SUT imported twice -> single peer, exit 0 (not spurious multi)" {
  mkdir -p src tests/unit
  printf 'export const x=1;\nexport const y=2;\n' > src/dup.ts
  printf 'import {x} from "../../src/dup";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/dup.test.ts
  cat > tests/unit/qa-dup.test.ts <<'EOF'
import { x } from "../../src/dup";
import { y } from "../../src/dup";
test("dup", () => { expect(x + y).toBe(3); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-dup.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "src/dup.qa.test.ts" ]
}

# ---- Inputs: mixed ext / extensionless for same SUT -> one peer -------------

@test "[P1] './foo' and './foo.ts' resolve to one peer -> exit 0" {
  mkdir -p src tests/unit
  printf 'export const x=1;\nexport const y=2;\n' > src/mix.ts
  printf 'import {x} from "../../src/mix";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/mix.test.ts
  cat > tests/unit/qa-mix.test.ts <<'EOF'
import { x } from "../../src/mix";
import { y } from "../../src/mix.ts";
test("mix", () => { expect(x + y).toBe(3); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-mix.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "src/mix.qa.test.ts" ]
}

# ---- State transition: idempotency — second run after move -> exit 2 --------

@test "[P0] second adopt run after the file is already moved -> exit 2 file not found" {
  mkdir -p src tests/unit
  printf 'export const x=1;\n' > src/idem.ts
  printf 'import {x} from "../../src/idem";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/idem.test.ts
  cat > tests/unit/qa-idem.test.ts <<'EOF'
import { x } from "../../src/idem";
test("idem", () => { expect(x).toBe(1); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-idem.test.ts
  [ "$status" -eq 0 ]
  # Second run: original path is gone.
  run bash "$ADOPT" tests/unit/qa-idem.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"file not found"* ]]
}

# ---- State transition: target sibling exists -> exit 1, no silent fallthrough

@test "[P1] target *.qa.test sibling already exists -> exit 1, no fallthrough pick" {
  mkdir -p src/one src/two tests/unit
  printf 'export const x=1;\n' > src/one/one.ts
  printf 'export const x=1;\n' > src/two/two.ts
  printf 'import {x} from "../../src/one/one";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/one/one.test.ts
  printf 'import {x} from "../../src/two/two";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/two/two.test.ts
  # Pre-create the collision at the lex-first winner (src/one/one.qa.test.ts).
  printf '// pre-existing\n' > src/one/one.qa.test.ts
  cat > tests/unit/qa-collide.test.ts <<'EOF'
import { x } from "../../src/one/one";
import { x as y } from "../../src/two/two";
test("collide", () => { expect(x + y).toBe(2); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-collide.test.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"target path already exists"* ]]
  # Must NOT have fallen through to the other peer.
  [ ! -f "src/two/two.qa.test.ts" ]
  # Original QA file still present (no move occurred).
  [ -f "tests/unit/qa-collide.test.ts" ]
}

# ---- State transition: multi-peer pick routes through git mv (sole deleter) -

@test "[P1] multi-peer adoption -> original removed, sibling git-tracked" {
  mkdir -p src/aa src/bb tests/unit
  printf 'export const x=1;\n' > src/aa/aa.ts
  printf 'export const x=1;\n' > src/bb/bb.ts
  printf 'import {x} from "../../src/aa/aa";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/aa/aa.test.ts
  printf 'import {x} from "../../src/bb/bb";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/bb/bb.test.ts
  cat > tests/unit/qa-mv.test.ts <<'EOF'
import { x } from "../../src/aa/aa";
import { x as y } from "../../src/bb/bb";
test("mv", () => { expect(x + y).toBe(2); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-mv.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "src/aa/aa.qa.test.ts" ]
  [ ! -f "tests/unit/qa-mv.test.ts" ]
  # Sibling is git-tracked (move staged), original no longer tracked.
  run git ls-files --error-unmatch src/aa/aa.qa.test.ts
  [ "$status" -eq 0 ]
  run git ls-files --error-unmatch tests/unit/qa-mv.test.ts
  [ "$status" -ne 0 ]
}

# ---- Cross-cutting: deterministic / reproducible pick across two repos ------

@test "[P1] identical multi-peer layout in two repos -> identical chosen sibling" {
  make_layout() {
    mkdir -p src/m1 src/m2 tests/unit
    printf 'export const x=1;\n' > src/m1/m1.ts
    printf 'export const x=1;\n' > src/m2/m2.ts
    printf 'import {x} from "../../src/m1/m1";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/m1/m1.test.ts
    printf 'import {x} from "../../src/m2/m2";\ntest("t",()=>{expect(x).toBe(1)});\n' > src/m2/m2.test.ts
    cat > tests/unit/qa-det.test.ts <<'EOF'
import { x } from "../../src/m1/m1";
import { x as y } from "../../src/m2/m2";
test("det", () => { expect(x + y).toBe(2); });
EOF
  }
  make_layout
  git add . && git commit -q -m init
  run bash "$ADOPT" tests/unit/qa-det.test.ts
  [ "$status" -eq 0 ]
  first="$output"

  R2="$(mktemp -d)"
  git -C "$R2" init -q
  git -C "$R2" config user.email "test@bats"
  git -C "$R2" config user.name "Bats Test"
  cd "$R2"
  make_layout
  git add . && git commit -q -m init
  run bash "$ADOPT" tests/unit/qa-det.test.ts
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  rm -rf "$R2"
}

# ---- Dependency: <<MULTI>> with NO singular peer -> restored exit-2 reason --

@test "[P2] single SUT base matches 2+ peers, no other singular -> exit 2 ambiguity reason" {
  # Two peers under tests/ share the base name 'amb' but live in different dirs.
  # The QA file imports only that single ambiguous SUT -> <<MULTI>>, seen_count=0.
  mkdir -p src pkgA pkgB tests/a tests/b
  printf 'export const x=1;\n' > src/amb.ts
  printf 'import {x} from "../src/amb";\ntest("t",()=>{expect(x).toBe(1)});\n' > tests/a/amb.test.ts
  printf 'import {x} from "../src/amb";\ntest("t",()=>{expect(x).toBe(1)});\n' > tests/b/amb.test.ts
  cat > tests/qa-amb.test.ts <<'EOF'
import { x } from "../src/amb";
test("amb", () => { expect(x).toBe(1); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/qa-amb.test.ts
  [ "$status" -eq 2 ]
  [[ "$output" == *"multiple plausible peer tests match a single imported SUT"* ]]
}

# ---- Dependency: <<MULTI>> ambiguous SUT + another singular peer -> exit 0 --

@test "[P2] ambiguous SUT base + a second singular SUT -> exit 0, singular peer wins" {
  mkdir -p src tests/a tests/b tests/unit
  printf 'export const x=1;\n' > src/amb2.ts
  printf 'export const x=1;\n' > src/solo.ts
  printf 'import {x} from "../src/amb2";\ntest("t",()=>{expect(x).toBe(1)});\n' > tests/a/amb2.test.ts
  printf 'import {x} from "../src/amb2";\ntest("t",()=>{expect(x).toBe(1)});\n' > tests/b/amb2.test.ts
  printf 'import {x} from "../../src/solo";\ntest("t",()=>{expect(x).toBe(1)});\n' > tests/unit/solo.test.ts
  cat > tests/unit/qa-amb2.test.ts <<'EOF'
import { x } from "../../src/amb2";
import { x as y } from "../../src/solo";
test("amb2", () => { expect(x + y).toBe(2); });
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/unit/qa-amb2.test.ts
  [ "$status" -eq 0 ]
  # The ambiguous SUT contributes <<MULTI>> (skipped); solo resolves singularly.
  [ "$output" = "tests/unit/solo.qa.test.ts" ]
}

# ---- Bats path: load two scripts each with a .bats peer -> lex-first --------

@test "[P1] bats QA loads two scripts each with a peer .bats -> exit 0 lex-first" {
  mkdir -p tests/bats/zeta tests/bats/alpha tests/bats/qa
  for d in zeta alpha; do
    printf '#!/usr/bin/env bash\necho noop\n' > "tests/bats/${d}/${d}.sh"
    printf '#!/usr/bin/env bats\n@test "t" { :; }\n' > "tests/bats/${d}/${d}.bats"
  done
  cat > tests/bats/qa/qa-load.bats <<'EOF'
#!/usr/bin/env bats
load '../zeta/zeta.sh'
load '../alpha/alpha.sh'
@test "edge" { :; }
EOF
  git add . && git commit -q -m init

  run bash "$ADOPT" tests/bats/qa/qa-load.bats
  [ "$status" -eq 0 ]
  # Full-path lex sort: tests/bats/alpha/alpha.bats first.
  [ "$output" = "tests/bats/alpha/alpha.qa.bats" ]
  [ ! -f "tests/bats/qa/qa-load.bats" ]
}
