#!/usr/bin/env bats
# Bats fixture for reconcile-test-plan.sh (FEAT-026 / FR-5).
#
# Covers every match class (R1 gaps, R2 contradictions, R3 surplus, R4 drift,
# R5 modeMismatch), both test-plan formats (version-2 prose + legacy table,
# per NFR-3), exit codes 0/1/2, and the edge cases enumerated in the FEAT-026
# testing section (missing `## Acceptance Criteria`, zero scenarios).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/reconcile-test-plan.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

  REQ_V2="${FIXTURES}/req-doc-reconcile.md"
  PLAN_V2="${FIXTURES}/qa-plan-v2-prose.md"
  PLAN_LEGACY="${FIXTURES}/qa-plan-legacy-table.md"

  TMP_DIR="$(mktemp -d)"
}

teardown() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

# =====================================================================
# Arg-validation
# =====================================================================

@test "missing both args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: reconcile-test-plan.sh"* ]]
}

@test "missing plan-doc arg -> exit 2" {
  run bash "$SCRIPT" "$REQ_V2"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: reconcile-test-plan.sh"* ]]
}

@test "non-existent req-doc -> exit 1" {
  run bash "$SCRIPT" "${TMP_DIR}/nope.md" "$PLAN_V2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read req-doc"* ]]
}

@test "non-existent plan-doc -> exit 1" {
  run bash "$SCRIPT" "$REQ_V2" "${TMP_DIR}/nope.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read plan-doc"* ]]
}

# =====================================================================
# Edge-case inputs
# =====================================================================

@test "req-doc without '## Acceptance Criteria' -> exit 1 with helpful stderr" {
  cat > "${TMP_DIR}/req-no-ac.md" <<'EOF'
# No AC heading

### FR-1: Do the thing
Body.
EOF
  run bash "$SCRIPT" "${TMP_DIR}/req-no-ac.md" "$PLAN_V2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing '## Acceptance Criteria'"* ]]
}

@test "test plan with zero scenarios -> exit 1" {
  cat > "${TMP_DIR}/plan-empty.md" <<'EOF'
# Empty

This plan has no P0/P1/P2 lines and no legacy table rows.
EOF
  run bash "$SCRIPT" "$REQ_V2" "${TMP_DIR}/plan-empty.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no parseable scenario lines"* ]]
}

# =====================================================================
# Version-2 prose format coverage (NFR-3)
# =====================================================================

@test "v2 prose: output shape has all five arrays always present" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gaps":'* ]]
  [[ "$output" == *'"contradictions":'* ]]
  [[ "$output" == *'"surplus":'* ]]
  [[ "$output" == *'"drift":'* ]]
  [[ "$output" == *'"modeMismatch":'* ]]
}

@test "v2 prose: R1 gaps — uncovered requirement IDs surface" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  # AC-2 and RC-1 are not referenced by any scenario.
  [[ "$output" == *'"id":"AC-2"'* ]]
  [[ "$output" == *'"id":"RC-1"'* ]]
}

@test "v2 prose: R3 surplus — scenario with no req ID surfaces" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"surplus"* ]]
  [[ "$output" == *"Exploratory surplus check"* ]]
}

@test "v2 prose: R3 surplus — scenario with only unknown FR-99 surfaces" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FR-99"* ]]
  [[ "$output" == *"no known requirement ID"* ]]
}

@test "v2 prose: R4 drift — scenario priority disagrees with req priority" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  # NFR-1 doc-level priority is P1, scenario is P0.
  [[ "$output" == *'"id":"NFR-1"'* ]]
  [[ "$output" == *"scenario priority P0"* ]]
}

@test "v2 prose: R2 contradictions — expected: phrase shares no word with requirement body" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  # AC-1 scenario's expected: 'quietly silent no output at all' shares no
  # 4+ letter word with AC-1 requirement body ('confirmation' / 'emits').
  [[ "$output" == *"contradictions"* ]]
  [[ "$output" == *"quietly silent"* ]]
}

@test "v2 prose: R5 modeMismatch — scenario mode disagrees with Testing Requirements" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_V2"
  [ "$status" -eq 0 ]
  # Testing Requirements says executable; AC-1 scenario uses mode: manual.
  [[ "$output" == *"modeMismatch"* ]]
  [[ "$output" == *"manual"* ]]
  [[ "$output" == *"executable"* ]]
}

@test "v2 prose: embedded FR-N in expected: text is recognized as coverage" {
  # Scenario `[P1] AC-1 confirmation ...` references both AC-1 and (implicit
  # none in expected) — create a smaller doc where only FR coverage lives in
  # expected: text.
  cat > "${TMP_DIR}/req-min.md" <<'EOF'
# Minimal

Priority: P0

### FR-7: Special case
Behavior description.

## Acceptance Criteria
- AC-7: The thing works.
EOF
  cat > "${TMP_DIR}/plan-min.md" <<'EOF'
# Plan

[P0] Scenario for special case | mode: executable | expected: FR-7 condition 1 satisfied
EOF
  run bash "$SCRIPT" "${TMP_DIR}/req-min.md" "${TMP_DIR}/plan-min.md"
  [ "$status" -eq 0 ]
  # FR-7 should NOT be in gaps (it is referenced inside `expected:` text).
  ! [[ "$output" == *'"id":"FR-7","location":"req-doc"'*'no test-plan scenario'* ]]
  # AC-7 should be in gaps (not referenced anywhere).
  [[ "$output" == *'"id":"AC-7"'* ]]
}

# =====================================================================
# Legacy table format coverage (NFR-3)
# =====================================================================

@test "legacy table: parses | RC-N | AC-N | columns as scenario references" {
  run bash "$SCRIPT" "$REQ_V2" "$PLAN_LEGACY"
  [ "$status" -eq 0 ]
  # RC-99 / AC-99 are not in req-doc -> surplus scenario surfaces.
  [[ "$output" == *"RC-99"* ]]
  [[ "$output" == *"surplus"* ]]
}

@test "legacy table: RC-1 column entry is recognized as RC-1 coverage" {
  cat > "${TMP_DIR}/req-rc.md" <<'EOF'
# Bug RC fixture

### RC-1: Reproducing case
Body.

## Acceptance Criteria
- AC-1: Fix works.
EOF
  cat > "${TMP_DIR}/plan-rc.md" <<'EOF'
| RC   | AC   | Description |
|------|------|-------------|
| RC-1 | AC-1 | Reproduce and verify |
EOF
  run bash "$SCRIPT" "${TMP_DIR}/req-rc.md" "${TMP_DIR}/plan-rc.md"
  [ "$status" -eq 0 ]
  # RC-1 and AC-1 are covered -> not in gaps.
  ! [[ "$output" == *'"id":"RC-1","location":"req-doc"'*'no test-plan scenario'* ]]
  ! [[ "$output" == *'"id":"AC-1","location":"req-doc"'*'no test-plan scenario'* ]]
}

@test "legacy table: AC-99 column entry produces surplus when not in req-doc" {
  cat > "${TMP_DIR}/req-tiny.md" <<'EOF'
# Tiny
### FR-1: Something
Body.
## Acceptance Criteria
- AC-1: Foo.
EOF
  cat > "${TMP_DIR}/plan-surplus.md" <<'EOF'
| AC   | Description |
|------|-------------|
| AC-1 | ok scenario |
| AC-99 | surplus scenario |
EOF
  run bash "$SCRIPT" "${TMP_DIR}/req-tiny.md" "${TMP_DIR}/plan-surplus.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AC-99"* ]]
  [[ "$output" == *"surplus"* ]]
}

# =====================================================================
# Clean match
# =====================================================================

@test "clean match: all requirement IDs referenced, no surplus/drift -> empty arrays" {
  cat > "${TMP_DIR}/req-clean.md" <<'EOF'
# Clean match fixture

Priority: P0

### FR-1: Tidy behavior
Body.

## Acceptance Criteria
- AC-1: Works.
EOF
  cat > "${TMP_DIR}/plan-clean.md" <<'EOF'
# Clean match plan

[P0] FR-1 scenario | mode: executable | expected: tidy behavior verified
[P0] AC-1 passes | mode: executable | expected: works as documented
EOF
  run bash "$SCRIPT" "${TMP_DIR}/req-clean.md" "${TMP_DIR}/plan-clean.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gaps":[]'* ]]
  [[ "$output" == *'"surplus":[]'* ]]
  [[ "$output" == *'"drift":[]'* ]]
}
