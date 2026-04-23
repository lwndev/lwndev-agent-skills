#!/usr/bin/env bats
# Bats fixture for check-deliverable.sh (FEAT-027 / FR-3).
#
# Covers: numeric-index dispatch, text-substring dispatch, phase-scoping,
# fence-awareness, idempotent no-op, and every documented exit code
# (0 / 1 / 2 / 3).
#
# Per-test mktemp'd fixture directory; parent-shell PATH never mutated.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/check-deliverable.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

  FIXTURE_DIR="$(mktemp -d)"
  DOC="${FIXTURE_DIR}/plan.md"
  # Work against a copy of the shared deliverables fixture so each test can
  # mutate freely without touching the on-disk fixture.
  cp "${FIXTURES}/deliverables-plan.md" "$DOC"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- numeric-index dispatch ----------

@test "index 1 on three-deliverable phase: already-checked alpha → already checked" {
  run bash "$SCRIPT" "$DOC" 1 1
  [ "$status" -eq 0 ]
  [ "$output" = "already checked" ]
}

@test "index 2 on three-deliverable phase: flips beta to checked" {
  run bash "$SCRIPT" "$DOC" 1 2
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/beta.sh`' "$DOC"
  # alpha stays checked, gamma stays unchecked.
  grep -q '^- \[x\] `scripts/alpha.sh`' "$DOC"
  grep -q '^- \[ \] `scripts/gamma.sh`' "$DOC"
}

@test "index 3 on three-deliverable phase: flips gamma to checked" {
  run bash "$SCRIPT" "$DOC" 1 3
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/gamma.sh`' "$DOC"
}

@test "index out of range (4 on 3-deliverable phase): exit 1 with range error" {
  run bash "$SCRIPT" "$DOC" 1 4
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of range"* ]]
  [[ "$output" == *"3 deliverables"* ]]
}

@test "index 0: exit 1 with range error" {
  # Selector '0' is still digits-only, so routed to index dispatch; 0 is out of range.
  run bash "$SCRIPT" "$DOC" 1 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of range"* ]]
}

@test "index on already-checked target: already checked, exit 0" {
  # Phase 3 deliverable index 3 is `scripts/toml-parser.sh` (already checked).
  run bash "$SCRIPT" "$DOC" 3 3
  [ "$status" -eq 0 ]
  [ "$output" = "already checked" ]
}

@test "index dispatch ignores fenced deliverables (phase 2 has only 1 real deliverable)" {
  # Phase 2 has fenced `- [ ]` lines that must NOT count. Only `scripts/delta.sh`
  # should be visible, making index 2 out of range.
  run bash "$SCRIPT" "$DOC" 2 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"out of range"* ]]
  [[ "$output" == *"1 deliverables"* ]]
}

@test "index 1 on phase 2 flips the real deliverable outside the fence" {
  run bash "$SCRIPT" "$DOC" 2 1
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/delta.sh`' "$DOC"
  # Fenced lines remain `- [ ]`.
  grep -q '^- \[ \] `fenced-template.ts`' "$DOC"
  grep -q '^- \[ \] `another-fenced.ts`' "$DOC"
}

# ---------- text-substring dispatch ----------

@test "text dispatch: unique unchecked substring → flips that line" {
  run bash "$SCRIPT" "$DOC" 1 "beta.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/beta.sh`' "$DOC"
}

@test "text dispatch: already-checked substring with no unchecked match → already checked" {
  # `alpha.sh` appears only as a checked line in phase 1.
  run bash "$SCRIPT" "$DOC" 1 "alpha.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "already checked" ]
}

@test "text dispatch: ambiguous substring matches two unchecked lines → exit 2" {
  # `parser` matches both json-parser.sh and yaml-parser.sh (unchecked) in phase 3.
  run bash "$SCRIPT" "$DOC" 3 "parser"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ambiguous"* ]]
  [[ "$output" == *"2 lines"* ]]
}

@test "text dispatch: ambiguity ignores already-checked substring matches" {
  # Swap in a fixture where only one unchecked line matches `parser` — the
  # already-checked `toml-parser.sh` does NOT count toward ambiguity.
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
#### Deliverables
- [ ] `scripts/json-parser.sh`
- [x] `scripts/toml-parser.sh`
EOF
  run bash "$SCRIPT" "$DOC" 1 "parser"
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/json-parser.sh`' "$DOC"
}

@test "text dispatch: substring only inside fenced block → exit 1 not found" {
  run bash "$SCRIPT" "$DOC" 2 "fenced-template.ts"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# ---------- phase-scoping ----------

@test "text matches a deliverable in a different phase → exit 1 not found in target phase" {
  # `phase-four-only.sh` exists only in phase 4, so targeting phase 1 must miss.
  run bash "$SCRIPT" "$DOC" 1 "phase-four-only.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "index dispatch is phase-scoped — phase 4 index 1 flips only phase 4 deliverable" {
  run bash "$SCRIPT" "$DOC" 4 1
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] `scripts/phase-four-only.sh`' "$DOC"
  # Phase 1 beta/gamma remain unchecked.
  grep -q '^- \[ \] `scripts/beta.sh`' "$DOC"
  grep -q '^- \[ \] `scripts/gamma.sh`' "$DOC"
}

# ---------- error paths ----------

@test "missing all args: exit 3" {
  run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"usage"* ]]
}

@test "missing two args: exit 3" {
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"usage"* ]]
}

@test "missing one arg: exit 3" {
  run bash "$SCRIPT" "$DOC" 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"usage"* ]]
}

@test "non-positive phase number (0): exit 3" {
  run bash "$SCRIPT" "$DOC" 0 "beta.sh"
  [ "$status" -eq 3 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "non-integer phase number: exit 3" {
  run bash "$SCRIPT" "$DOC" abc "beta.sh"
  [ "$status" -eq 3 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "/nonexistent/path/plan.md" 1 "beta.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"unreadable"* ]]
}

@test "phase number not in plan: exit 1" {
  run bash "$SCRIPT" "$DOC" 99 "beta.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "fence-awareness: fenced unchecked line is not flipped by text matcher" {
  # Text matcher for `fenced-template.ts` targets phase 2; substring lives
  # only inside the fence and thus is unreachable.
  before=$(md5 -q "$DOC" 2>/dev/null || md5sum "$DOC" | awk '{print $1}')
  run bash "$SCRIPT" "$DOC" 2 "fenced-template"
  [ "$status" -eq 1 ]
  after=$(md5 -q "$DOC" 2>/dev/null || md5sum "$DOC" | awk '{print $1}')
  # File unchanged — no flipping happened anywhere.
  [ "$before" = "$after" ]
}
