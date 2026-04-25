#!/usr/bin/env bats
# Bats fixture for validate-phase-sizes.sh (FEAT-029 / FR-5).
#
# Covers:
#   * Happy path on a plan with all phases at/under budget → stdout `ok`,
#     exit 0.
#   * One over-budget phase (no override) → exit 1, stderr contains the
#     documented `[warn] phase <N>: over budget — ...` line for that
#     phase only.
#   * Override clamps an over-budget phase → that phase passes the gate;
#     stdout `ok` if no other failures.
#   * Multiple over-budget phases → stderr lists each on its own line,
#     exit 1.
#   * Missing arg → exit 2; non-existent file → exit 1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/validate-phase-sizes.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

write_phase() {
  # write_phase <file> <phase-N> <name> <steps> <delivs> [override]
  local f="$1"
  local n="$2"
  local name="$3"
  local steps="$4"
  local delivs="$5"
  local override="${6:-}"
  {
    printf '\n### Phase %d: %s\n\n' "$n" "$name"
    printf '**Status:** Pending\n'
    if [ -n "$override" ]; then
      printf '**ComplexityOverride:** %s\n' "$override"
    fi
    printf '\n#### Implementation Steps\n\n'
    local i=1
    while [ "$i" -le "$steps" ]; do
      printf '%d. Step %d.\n' "$i" "$i"
      i=$((i + 1))
    done
    printf '\n#### Deliverables\n\n'
    i=1
    while [ "$i" -le "$delivs" ]; do
      printf -- '- [ ] `phase%d-file%d.sh`\n' "$n" "$i"
      i=$((i + 1))
    done
  } >> "$f"
}

# --- happy path -------------------------------------------------------------

@test "all phases under budget: stdout ok, exit 0" {
  f="${WORK_DIR}/under.md"
  printf '# Plan\n' > "$f"
  write_phase "$f" 1 "Small One" 3 3
  write_phase "$f" 2 "Small Two" 2 2
  run bash "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

# --- failing paths ----------------------------------------------------------

@test "single over-budget phase (steps): exit 1, stderr names that phase only" {
  f="${WORK_DIR}/over1.md"
  printf '# Plan\n' > "$f"
  write_phase "$f" 1 "Small" 3 3
  write_phase "$f" 2 "Big" 9 2  # 9 steps -> opus, 2 delivs -> haiku
  # Capture stdout and stderr separately to validate the contract: stdout
  # MUST be empty on failure, stderr MUST list the offender.
  stdout_file="${WORK_DIR}/stdout.txt"
  stderr_file="${WORK_DIR}/stderr.txt"
  rc=0
  bash "$SCRIPT" "$f" >"$stdout_file" 2>"$stderr_file" || rc=$?
  [ "$rc" -eq 1 ]
  [ ! -s "$stdout_file" ]
  grep -q '^\[warn\] phase 2: over budget' "$stderr_file"
  grep -q 'steps=9 exceeds opus threshold' "$stderr_file"
  ! grep -q '^\[warn\] phase 1:' "$stderr_file"
}

@test "override clamps over-budget phase: stdout ok, exit 0" {
  f="${WORK_DIR}/clamped.md"
  printf '# Plan\n' > "$f"
  write_phase "$f" 1 "Small" 2 2
  write_phase "$f" 2 "BigClamped" 9 2 "haiku"
  run bash "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "multiple over-budget phases: stderr lists each on its own line, exit 1" {
  f="${WORK_DIR}/multi.md"
  printf '# Plan\n' > "$f"
  write_phase "$f" 1 "BigA" 9 2
  write_phase "$f" 2 "Small" 1 1
  write_phase "$f" 3 "BigB" 8 2
  run bash "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  stderr_file="${WORK_DIR}/multi-stderr.txt"
  bash "$SCRIPT" "$f" >/dev/null 2>"$stderr_file" || true
  grep -q '^\[warn\] phase 1:' "$stderr_file"
  grep -q '^\[warn\] phase 3:' "$stderr_file"
  ! grep -q '^\[warn\] phase 2:' "$stderr_file"
  count=$(grep -c '^\[warn\] phase ' "$stderr_file")
  [ "$count" -eq 2 ]
}

# --- error paths ------------------------------------------------------------

@test "missing arg: exit 2 with usage message" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "${WORK_DIR}/nope.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: plan file not found'
}
