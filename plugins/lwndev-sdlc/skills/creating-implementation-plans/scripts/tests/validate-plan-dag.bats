#!/usr/bin/env bats
# Bats fixture for validate-plan-dag.sh (FEAT-029 / FR-2).
#
# Covers:
#   * Happy path: valid 3-phase DAG → stdout `ok`, exit 0.
#   * 2-cycle: Phase 2 ⇄ Phase 4 → exit 1, stderr lists both phases.
#   * Larger 3-cycle: synthesised inline → exit 1, stderr lists all three.
#   * Unresolved reference (Phase 1 depends on Phase 99) → exit 1, stderr
#     names both phases.
#   * Fence-awareness: fenced `Phase 99` reference ignored, real `Phase 1`
#     reference parsed → stdout `ok`, exit 0.
#   * Absence of `**Depends on:**` line treated as no deps → stdout `ok`.
#   * Free-text token (`PR #123 merging`) ignored → stdout `ok`.
#   * Missing arg → exit 2.
#   * Non-existent file → exit 1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/validate-plan-dag.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

# --- happy paths -------------------------------------------------------------

@test "valid 3-phase DAG: stdout 'ok', exit 0" {
  run bash "$SCRIPT" "${FIXTURES}/dag-valid-plan.md"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "fence-awareness: fenced Phase 99 reference ignored" {
  run bash "$SCRIPT" "${FIXTURES}/dag-fenced-plan.md"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "absence of Depends on line: treated as no deps, stdout 'ok'" {
  cat > "${WORK_DIR}/no-deps.md" <<'EOF'
# Plan

### Phase 1: Solo

**Status:** Pending

#### Deliverables
- [ ] `solo.sh`
EOF
  run bash "$SCRIPT" "${WORK_DIR}/no-deps.md"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "free-text token (PR #123) ignored, stdout 'ok'" {
  cat > "${WORK_DIR}/free-text.md" <<'EOF'
# Plan

### Phase 1: Foundation

**Status:** Pending

#### Deliverables
- [ ] `one.sh`

### Phase 2: Builds On

**Status:** Pending
**Depends on:** Phase 1, PR #123 merging

#### Deliverables
- [ ] `two.sh`
EOF
  run bash "$SCRIPT" "${WORK_DIR}/free-text.md"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

# --- cycle detection ---------------------------------------------------------

@test "2-cycle (Phase 2 <-> Phase 4): exit 1, stderr lists both" {
  run bash "$SCRIPT" "${FIXTURES}/dag-cycle-plan.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: cycle detected involving phases'
  echo "$output" | grep -q '2'
  echo "$output" | grep -q '4'
}

@test "3-cycle (Phase 1 -> 2 -> 3 -> 1): exit 1, stderr lists all three" {
  cat > "${WORK_DIR}/3-cycle.md" <<'EOF'
# Plan

### Phase 1: A

**Status:** Pending
**Depends on:** Phase 3

#### Deliverables
- [ ] `a.sh`

### Phase 2: B

**Status:** Pending
**Depends on:** Phase 1

#### Deliverables
- [ ] `b.sh`

### Phase 3: C

**Status:** Pending
**Depends on:** Phase 2

#### Deliverables
- [ ] `c.sh`
EOF
  run bash "$SCRIPT" "${WORK_DIR}/3-cycle.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: cycle detected involving phases'
  echo "$output" | grep -q '1'
  echo "$output" | grep -q '2'
  echo "$output" | grep -q '3'
}

# --- reference resolution ----------------------------------------------------

@test "unresolved reference: exit 1, stderr names both phases" {
  cat > "${WORK_DIR}/unresolved.md" <<'EOF'
# Plan

### Phase 1: First

**Status:** Pending
**Depends on:** Phase 99

#### Deliverables
- [ ] `one.sh`
EOF
  run bash "$SCRIPT" "${WORK_DIR}/unresolved.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: phase 1 depends on non-existent phase 99'
}

# --- error paths -------------------------------------------------------------

@test "missing arg: exit 2 with usage message" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "${WORK_DIR}/does-not-exist.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: plan file not found'
}

@test "plan with no Phase blocks: exit 1" {
  cat > "${WORK_DIR}/no-phases.md" <<'EOF'
# Plan

Just prose. No phase headings.
EOF
  run bash "$SCRIPT" "${WORK_DIR}/no-phases.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'no `### Phase` blocks'
}
