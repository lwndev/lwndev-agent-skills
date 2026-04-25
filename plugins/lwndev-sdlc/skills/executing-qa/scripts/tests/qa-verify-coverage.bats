#!/usr/bin/env bats
# Bats fixture for qa-verify-coverage.sh (FEAT-030 / FR-9).
#
# Behavior matrix lifted from agents/qa-verifier.md (the deleted agent's
# reference spec):
#   * Happy path: COVERAGE-ADEQUATE (all five dimensions covered or justified,
#     valid metadata, no spec drift)
#   * Happy path: COVERAGE-GAPS with named gaps
#   * Per-dimension status enumeration (covered / justified / missing)
#   * Priority enum violation (P3, missing priority)
#   * Execution-mode enum violation (e2e, missing mode)
#   * Empty-findings directive violation (results artifact: scenario ran, zero
#     findings, no justification)
#   * No-spec drift detection (plan with FR-3 in ## Scenarios)
#   * Missing artifact path → exit 2

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/qa-verify-coverage.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---- Helpers ---------------------------------------------------------------

write_plan_adequate() {
  local path="${1:-QA-plan-FEAT-001.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-001
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P0] Input with empty string exits 2 | mode: test-framework | expected: bats case

### State transitions

- [P1] Concurrent writes do not collide | mode: test-framework | expected: vitest case

### Environment

- [P1] Missing jq on PATH falls back gracefully | mode: exploratory | expected: bats case

### Dependency failure

- [P0] Upstream script exits non-zero: caller propagates error | mode: test-framework | expected: bats case

### Cross-cutting

- [P2] Unicode in file paths round-trips without corruption | mode: exploratory | expected: manual run
EOF
}

write_plan_with_spec_drift() {
  local path="${1:-QA-plan-FEAT-002.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-002
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P0] FR-3 validation of input field | mode: test-framework | expected: bats case

### State transitions

- [P1] State resets after cancel | mode: test-framework | expected: bats case

### Environment

- [P1] No external deps; env isolation confirmed | mode: exploratory | expected: manual

### Dependency failure

- [P0] Upstream fails with exit 1; caller propagates | mode: test-framework | expected: bats

### Cross-cutting

- [P2] Unicode paths handled | mode: exploratory | expected: manual
EOF
}

write_plan_missing_dimensions() {
  local path="${1:-QA-plan-FEAT-003.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-003
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P0] Input validation tested | mode: test-framework | expected: bats case

### State transitions

- [P1] Reset scenario tested | mode: test-framework | expected: bats case

EOF
  # Environment, Dependency failure, Cross-cutting are absent.
}

write_plan_bad_priority() {
  local path="${1:-QA-plan-FEAT-004.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-004
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P3] Invalid priority label | mode: test-framework | expected: bats case
- [P0] Valid priority label | mode: test-framework | expected: bats case

### State transitions

- No priority listed here — a scenario with no bracket | mode: test-framework | expected: bats

### Environment

- [P1] Environment covered | mode: test-framework | expected: bats

### Dependency failure

- [P0] Dependency failure covered | mode: test-framework | expected: bats

### Cross-cutting

- [P2] Cross-cutting covered | mode: test-framework | expected: bats
EOF
}

write_plan_bad_mode() {
  local path="${1:-QA-plan-FEAT-005.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-005
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P0] Invalid execution mode | mode: e2e | expected: bats case
- [P1] No mode declaration at all, just a scenario line

### State transitions

- [P1] State covered | mode: test-framework | expected: bats

### Environment

- [P1] Env covered | mode: test-framework | expected: bats

### Dependency failure

- [P0] Dep covered | mode: test-framework | expected: bats

### Cross-cutting

- [P2] Cross-cutting covered | mode: exploratory | expected: manual
EOF
}

write_results_empty_findings() {
  local path="${1:-QA-results-FEAT-006.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-006
version: 2
persona: qa
verdict: PASS
---

## Summary

All tests passed.

## Scenarios Run

### Inputs

- [P0] Input validation | mode: test-framework | expected: bats case

### State transitions

- [P1] State covered | mode: test-framework | expected: bats

### Environment

- [P1] Env covered | mode: exploratory | expected: manual

### Dependency failure

- [P0] Dep covered | mode: test-framework | expected: bats

### Cross-cutting

- [P2] Cross-cutting covered | mode: exploratory | expected: manual

## Findings

## Reconciliation Delta

### Coverage beyond requirements
### Coverage gaps
### Summary
- coverage-surplus: 0
- coverage-gap: 0
EOF
}

write_plan_justified_dimension() {
  local path="${1:-QA-plan-FEAT-007.md}"
  cat > "$path" <<'EOF'
---
id: FEAT-007
version: 2
persona: qa
---

## Scenarios

### Inputs

- [P0] Input covered | mode: test-framework | expected: bats

### State transitions

- [P1] State covered | mode: test-framework | expected: bats

### Environment

- [P1] Env covered | mode: test-framework | expected: bats

### Dependency failure

Not applicable: this skill is a pure filesystem transform with no external dependencies.

### Cross-cutting

- [P2] Cross-cutting covered | mode: exploratory | expected: manual
EOF
}

# ---- Arg validation --------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "missing artifact path → exit 2 with usage" {
  run bash "$SCRIPT" /tmp/no-such-qa-artifact-xyzzy.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"artifact not found"* ]]
}

@test "empty string arg → exit 2" {
  run bash "$SCRIPT" ""
  [ "$status" -eq 2 ]
}

# ---- Happy path: COVERAGE-ADEQUATE -----------------------------------------

@test "happy path: all five dimensions covered → COVERAGE-ADEQUATE, exit 0" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-ADEQUATE" ]
}

@test "happy path: COVERAGE-ADEQUATE → empty gaps array" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  gaps_len="$(echo "$output" | jq '.gaps | length')"
  [ "$gaps_len" -eq 0 ]
}

@test "happy path: COVERAGE-ADEQUATE → perDimension has five entries" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  dim_len="$(echo "$output" | jq '.perDimension | length')"
  [ "$dim_len" -eq 5 ]
}

@test "happy path: COVERAGE-ADEQUATE → all dimensions 'covered'" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  missing="$(echo "$output" | jq '[.perDimension[] | select(.status != "covered")] | length')"
  [ "$missing" -eq 0 ]
}

# ---- Happy path: COVERAGE-GAPS with named gaps ------------------------------

@test "COVERAGE-GAPS: missing dimensions → verdict COVERAGE-GAPS" {
  write_plan_missing_dimensions
  run bash "$SCRIPT" QA-plan-FEAT-003.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-GAPS" ]
}

@test "COVERAGE-GAPS: three missing dimensions → three coverage gaps" {
  write_plan_missing_dimensions
  run bash "$SCRIPT" QA-plan-FEAT-003.md
  [ "$status" -eq 0 ]
  gaps_len="$(echo "$output" | jq '.gaps | length')"
  [ "$gaps_len" -ge 3 ]
}

@test "COVERAGE-GAPS: gap text names the missing dimensions" {
  write_plan_missing_dimensions
  run bash "$SCRIPT" QA-plan-FEAT-003.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"Environment"* ]]
  [[ "$output" == *"Dependency failure"* ]]
  [[ "$output" == *"Cross-cutting"* ]]
}

# ---- Per-dimension status enumeration --------------------------------------

@test "per-dimension status: covered dimension → status 'covered'" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  inputs_status="$(echo "$output" | jq -r '.perDimension[] | select(.dimension=="Inputs") | .status')"
  [ "$inputs_status" = "covered" ]
}

@test "per-dimension status: justified dimension → status 'justified'" {
  write_plan_justified_dimension
  run bash "$SCRIPT" QA-plan-FEAT-007.md
  [ "$status" -eq 0 ]
  dep_status="$(echo "$output" | jq -r '.perDimension[] | select(.dimension=="Dependency failure") | .status')"
  [ "$dep_status" = "justified" ]
}

@test "per-dimension status: missing dimension → status 'missing'" {
  write_plan_missing_dimensions
  run bash "$SCRIPT" QA-plan-FEAT-003.md
  [ "$status" -eq 0 ]
  env_status="$(echo "$output" | jq -r '.perDimension[] | select(.dimension=="Environment") | .status')"
  [ "$env_status" = "missing" ]
}

@test "per-dimension status: scenarioCount matches actual scenario count" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  # Each dimension in write_plan_adequate has exactly 1 scenario.
  for dim in "Inputs" "State transitions" "Environment" "Dependency failure" "Cross-cutting"; do
    count="$(echo "$output" | jq --arg d "$dim" '.perDimension[] | select(.dimension==$d) | .scenarioCount')"
    [ "$count" -eq 1 ]
  done
}

@test "per-dimension status: justified dimension has scenarioCount 0" {
  write_plan_justified_dimension
  run bash "$SCRIPT" QA-plan-FEAT-007.md
  [ "$status" -eq 0 ]
  dep_count="$(echo "$output" | jq -r '.perDimension[] | select(.dimension=="Dependency failure") | .scenarioCount')"
  [ "$dep_count" -eq 0 ]
}

# ---- Priority enum violations -----------------------------------------------

@test "priority violation P3: verdict COVERAGE-GAPS" {
  write_plan_bad_priority
  run bash "$SCRIPT" QA-plan-FEAT-004.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-GAPS" ]
}

@test "priority violation P3: gap text mentions invalid priority" {
  write_plan_bad_priority
  run bash "$SCRIPT" QA-plan-FEAT-004.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"priority"* ]] || [[ "$output" == *"P0|P1|P2"* ]]
}

@test "missing priority: scenario with no bracket → gap reported" {
  write_plan_bad_priority
  run bash "$SCRIPT" QA-plan-FEAT-004.md
  [ "$status" -eq 0 ]
  gaps_len="$(echo "$output" | jq '.gaps | length')"
  # At least the two priority violations (P3 + no-bracket).
  [ "$gaps_len" -ge 2 ]
}

# ---- Execution-mode enum violations -----------------------------------------

@test "execution-mode violation e2e: verdict COVERAGE-GAPS" {
  write_plan_bad_mode
  run bash "$SCRIPT" QA-plan-FEAT-005.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-GAPS" ]
}

@test "execution-mode violation e2e: gap text mentions invalid mode" {
  write_plan_bad_mode
  run bash "$SCRIPT" QA-plan-FEAT-005.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
}

@test "missing execution mode: scenario with no mode field → gap reported" {
  write_plan_bad_mode
  run bash "$SCRIPT" QA-plan-FEAT-005.md
  [ "$status" -eq 0 ]
  gaps_len="$(echo "$output" | jq '.gaps | length')"
  # At least: e2e mode + missing mode.
  [ "$gaps_len" -ge 2 ]
}

# ---- Empty-findings directive (results artifact) ----------------------------

@test "empty-findings: results with scenarios but empty Findings → COVERAGE-GAPS" {
  write_results_empty_findings
  run bash "$SCRIPT" QA-results-FEAT-006.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-GAPS" ]
}

@test "empty-findings: gap text names the suspicious dimension" {
  write_results_empty_findings
  run bash "$SCRIPT" QA-results-FEAT-006.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"zero findings"* ]] || [[ "$output" == *"findings"* ]]
}

@test "empty-findings: plan artifact skips this check (no false positives)" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-ADEQUATE" ]
}

# ---- No-spec drift (plan only) ---------------------------------------------

@test "no-spec drift: plan with FR-3 in Scenarios → COVERAGE-GAPS" {
  write_plan_with_spec_drift
  run bash "$SCRIPT" QA-plan-FEAT-002.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  [ "$verdict" = "COVERAGE-GAPS" ]
}

@test "no-spec drift: gap text identifies the leaked spec token" {
  write_plan_with_spec_drift
  run bash "$SCRIPT" QA-plan-FEAT-002.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"FR-3"* ]]
}

@test "no-spec drift: results artifact skips this check" {
  # Write a results file that would trigger spec-drift if it were a plan.
  cat > QA-results-FEAT-008.md <<'EOF'
---
id: FEAT-008
version: 2
persona: qa
verdict: PASS
---

## Summary

All tests passed.

## Scenarios Run

### Inputs

- [P0] FR-1 validated by test | mode: test-framework | expected: bats

### State transitions

- [P1] State transitions covered | mode: test-framework | expected: bats

### Environment

- [P1] Env covered | mode: exploratory | expected: manual

### Dependency failure

- [P0] Dep covered | mode: test-framework | expected: bats

### Cross-cutting

- [P2] Cross-cutting covered | mode: exploratory | expected: manual

## Findings

All tests passed — no findings.

## Reconciliation Delta

### Coverage beyond requirements
### Coverage gaps
### Summary
- coverage-surplus: 0
- coverage-gap: 0
EOF
  run bash "$SCRIPT" QA-results-FEAT-008.md
  [ "$status" -eq 0 ]
  verdict="$(echo "$output" | jq -r '.verdict')"
  # FR-1 in results should NOT trigger spec-drift gap; findings present → COVERAGE-ADEQUATE.
  [ "$verdict" = "COVERAGE-ADEQUATE" ]
}

# ---- JSON output shape ------------------------------------------------------

@test "output is valid JSON with required top-level keys" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict' >/dev/null
  echo "$output" | jq -e '.perDimension' >/dev/null
  echo "$output" | jq -e '.gaps' >/dev/null
}

@test "perDimension entries each have dimension, status, scenarioCount fields" {
  write_plan_adequate
  run bash "$SCRIPT" QA-plan-FEAT-001.md
  [ "$status" -eq 0 ]
  bad="$(echo "$output" | jq '[.perDimension[] | select((.dimension==null) or (.status==null) or (.scenarioCount==null))] | length')"
  [ "$bad" -eq 0 ]
}
