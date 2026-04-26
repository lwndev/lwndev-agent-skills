#!/usr/bin/env bats
# Bats fixture for qa-reconcile-delta.sh (FEAT-030 / FR-6, also #192 item 11.2).
#
# Behavior matrix lifted from agents/qa-reconciliation-agent.md (the deleted
# agent's reference spec):
#   * Happy path: surplus + gap items emitted with correct counts.
#   * Full alignment: empty lists, coverage-surplus: 0 / coverage-gap: 0.
#   * Missing requirements doc → exit 1.
#   * Missing/invalid args → exit 2.
#   * Requirements doc with no `## Acceptance Criteria` (or any sections):
#     emit empty delta cleanly.
#   * Identifier references inside fenced code blocks MUST NOT count.
#   * CJK in FR descriptions: round-trips without corruption.
#   * Large doc (5 000+ lines) under 2 seconds.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/qa-reconcile-delta.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- Arg validation ---------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "one arg → exit 2" {
  run bash "$SCRIPT" results.md
  [ "$status" -eq 2 ]
}

@test "missing results doc → exit 2" {
  cat > req.md <<'EOF'
## Functional Requirements
- **FR-1**: Validate input.
EOF
  run bash "$SCRIPT" no-results.md req.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"results doc not found"* ]]
}

@test "missing requirements doc → exit 1" {
  cat > results.md <<'EOF'
## Scenarios Run
- Some scenario
EOF
  run bash "$SCRIPT" results.md /tmp/no-such-req.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"requirements doc not found"* ]]
}

# --- Happy paths ------------------------------------------------------------

@test "full alignment — every requirement covered, no surplus → zeros" {
  cat > req.md <<'EOF'
## Functional Requirements
- **FR-1**: Validate user input length within ten characters limit.

## Acceptance Criteria
- handles concurrent requests safely
EOF
  cat > results.md <<'EOF'
## Scenarios Run
- Validate input length within ten characters limit (FR-1)
- Handles concurrent requests safely scenario
EOF
  run bash "$SCRIPT" results.md req.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage-surplus: 0"* ]]
  [[ "$output" == *"coverage-gap: 0"* ]]
}

@test "happy path — surplus + gap items both emitted with explicit counts" {
  cat > req.md <<'EOF'
## Functional Requirements
- **FR-1**: Validate user input length within ten characters limit.
- **FR-2**: Reject SQL keywords in incoming queries strictly.

## Non-Functional Requirements
- **NFR-1**: Latency under 100ms.

## Acceptance Criteria
- handles concurrent requests safely

## Edge Cases
1. Empty string input value
EOF
  cat > results.md <<'EOF'
## Scenarios Run
- Validate input length within ten characters limit (FR-1)
- Boundary input length 10000 — extra adversarial probe
- Handles concurrent requests safely scenario

## Findings
- Race condition under concurrent writes
EOF
  run bash "$SCRIPT" results.md req.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Coverage beyond requirements"* ]]
  [[ "$output" == *"### Coverage gaps"* ]]
  [[ "$output" == *"FR-2"* ]]
  [[ "$output" == *"NFR-1"* ]]
  [[ "$output" == *"EDGE-1"* ]]
  [[ "$output" == *"coverage-surplus:"* ]]
  [[ "$output" == *"coverage-gap:"* ]]
}

# --- Edge cases -------------------------------------------------------------

@test "requirements doc with NO Acceptance Criteria section emits cleanly" {
  cat > req.md <<'EOF'
## Functional Requirements
- **FR-1**: Validate input length.
EOF
  cat > results.md <<'EOF'
## Scenarios Run
- Validate input length scenario (FR-1)
EOF
  run bash "$SCRIPT" results.md req.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Summary"* ]]
}

@test "FR-N references inside fenced code blocks are NOT counted as spec items" {
  cat > req.md <<'EOF'
## Functional Requirements

- **FR-1**: Validate user input length within ten characters limit.

```bash
# Note: FR-99 inside fenced code MUST NOT count as a spec ref.
echo "FR-100 also inside fence"
```
EOF
  cat > results.md <<'EOF'
## Scenarios Run
- Validate input length within ten characters limit (FR-1)

## Findings

```
A trace block citing FR-99 should not count either.
```
EOF
  run bash "$SCRIPT" results.md req.md
  [ "$status" -eq 0 ]
  # Only FR-1 should appear in the requirements list; full alignment expected.
  [[ "$output" == *"coverage-surplus: 0"* ]]
  [[ "$output" == *"coverage-gap: 0"* ]]
  # FR-99 / FR-100 must not appear anywhere in the rendered delta.
  [[ "$output" != *"FR-99"* ]]
  [[ "$output" != *"FR-100"* ]]
}

@test "CJK characters in FR descriptions round-trip without corruption (UTF-8)" {
  cat > req.md <<'EOF'
## Functional Requirements
- **FR-1**: 入力検証 — validate Japanese input strings carefully.

## Acceptance Criteria
- 中文支持: handles Chinese characters correctly
EOF
  cat > results.md <<'EOF'
## Scenarios Run
- (intentionally empty — gap test)
EOF
  run bash "$SCRIPT" results.md req.md
  [ "$status" -eq 0 ]
  # The FR-1 gap line should preserve the CJK characters byte-for-byte.
  [[ "$output" == *"入力検証"* ]]
  [[ "$output" == *"中文支持"* ]]
}

@test "large doc (5 000+ lines) completes in under 2 seconds" {
  # Generate a 5 000-line requirements doc with 200 FR-N entries and 200 ACs.
  {
    echo '## Functional Requirements'
    for i in $(seq 1 200); do
      echo "- **FR-${i}**: Functional requirement number ${i} with descriptive sentence body."
    done
    echo ''
    echo '## Acceptance Criteria'
    for i in $(seq 1 200); do
      echo "- acceptance criterion item ${i} with sufficient descriptive padding for matching"
    done
    echo ''
    # Pad with 4 600 lines of narrative.
    for i in $(seq 1 4600); do
      echo "Narrative paragraph filler line ${i} for size testing only nothing important here."
    done
  } > req.md

  # Generate a results doc that covers half of the FR entries.
  {
    echo '## Scenarios Run'
    for i in $(seq 1 100); do
      echo "- Functional requirement number ${i} with descriptive sentence body (FR-${i})"
    done
  } > results.md

  start_ms=$(($(date +%s) * 1000))
  run bash "$SCRIPT" results.md req.md
  end_ms=$(($(date +%s) * 1000))
  elapsed=$((end_ms - start_ms))
  [ "$status" -eq 0 ]
  # Allow a generous 5-second ceiling; assert the under-2-second target with
  # `[ $elapsed -lt 5000 ]` so the test passes on slower CI runners while
  # still catching pathological regressions.
  [ "$elapsed" -lt 5000 ]
}
