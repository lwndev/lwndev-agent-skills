#!/usr/bin/env bats
# Bats fixture for split-phase-suggest.sh (FEAT-029 / FR-4).
#
# Covers:
#   * Happy path (4-step phase) → 2-way split, JSON has 2 suggestion
#     entries with non-overlapping `steps` arrays summing to all 4 indices.
#   * Happy path (8-step phase) → 3-way split, 3 suggestion entries,
#     balanced within ±1 step.
#   * 1-step phase → `{"original":N,"suggestions":[]}`, exit 0.
#   * Step-ordering preservation: every suggestion's `steps` array is
#     monotonically increasing; concatenated in order, equals
#     [1,2,...,N].
#   * `Depends on Step 4` annotation: split boundary on a 6-step phase
#     must not place Step 5 in a chunk that terminates before Step 4 is
#     included.
#   * Impossible (forward-pointing) `Depends on Step <N>` annotation
#     where N is the step's own position or later: exits 1 with a
#     `[error] ... impossible dependency ...` diagnostic instead of
#     silently producing a malformed split.
#   * Error tests: missing args → exit 2; non-existent file → exit 1;
#     phase block missing → exit 1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/split-phase-suggest.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

# Build a synthetic plan with N implementation steps in "${WORK_DIR}/$1.md".
# Each step text is `Step <i>.` plus optional inline-annotation overrides
# supplied via STEP_<i>_TEXT env vars.
make_plan() {
  local name="$1"
  local steps="$2"
  local f="${WORK_DIR}/${name}.md"
  {
    printf '# Plan: %s\n\n' "$name"
    printf '### Phase 1: Test\n\n'
    printf '**Status:** Pending\n\n'
    printf '#### Implementation Steps\n\n'
    local i=1
    while [ "$i" -le "$steps" ]; do
      local var="STEP_${i}_TEXT"
      local text="${!var:-Step ${i}.}"
      printf '%d. %s\n' "$i" "$text"
      i=$((i + 1))
    done
    printf '\n#### Deliverables\n\n'
    printf -- '- [ ] `path/file.sh`\n'
  } > "$f"
  printf '%s' "$f"
}

# Helper: extract the `steps` array of suggestion index $1 from JSON $2.
# Returns the array as a comma-separated list of integers (no brackets).
suggestion_steps() {
  local idx="$1"
  local json="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".suggestions[${idx}].steps | join(\",\")"
  else
    # Fallback: best-effort sed over the canonical printf shape.
    printf '%s' "$json" | sed -n "s/.*\"steps\":\\[\\([^]]*\\)\\].*/\\1/p" | sed -n "$((idx + 1))p"
  fi
}

suggestion_count() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.suggestions | length'
  else
    printf '%s' "$json" | grep -o '"name":' | wc -l | tr -d ' '
  fi
}

original_count() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.original'
  else
    printf '%s' "$json" | sed -n 's/.*"original":\([0-9][0-9]*\).*/\1/p'
  fi
}

# --- happy paths -------------------------------------------------------------

@test "4-step phase: 2-way split with non-overlapping steps summing to [1..4]" {
  f="$(make_plan 'four' 4)"
  run bash "$SCRIPT" "$f" 1
  [ "$status" -eq 0 ]
  [ "$(suggestion_count "$output")" = "2" ]
  [ "$(original_count "$output")" = "4" ]
  s0="$(suggestion_steps 0 "$output")"
  s1="$(suggestion_steps 1 "$output")"
  combined="${s0},${s1}"
  [ "$combined" = "1,2,3,4" ]
}

@test "8-step phase: 3-way split, 3 entries balanced ±1" {
  f="$(make_plan 'eight' 8)"
  run bash "$SCRIPT" "$f" 1
  [ "$status" -eq 0 ]
  [ "$(suggestion_count "$output")" = "3" ]
  [ "$(original_count "$output")" = "8" ]
  s0="$(suggestion_steps 0 "$output")"
  s1="$(suggestion_steps 1 "$output")"
  s2="$(suggestion_steps 2 "$output")"
  # Concatenated must equal 1..8.
  [ "${s0},${s1},${s2}" = "1,2,3,4,5,6,7,8" ]
  # Balance check: chunk sizes within ±1.
  c0=$(printf '%s' "$s0" | tr ',' '\n' | wc -l | tr -d ' ')
  c1=$(printf '%s' "$s1" | tr ',' '\n' | wc -l | tr -d ' ')
  c2=$(printf '%s' "$s2" | tr ',' '\n' | wc -l | tr -d ' ')
  # 8/3 = 2 base, 2 extra → sizes 3,3,2 (extra distributed to first chunks).
  hi=$c0; [ $c1 -gt $hi ] && hi=$c1; [ $c2 -gt $hi ] && hi=$c2
  lo=$c0; [ $c1 -lt $lo ] && lo=$c1; [ $c2 -lt $lo ] && lo=$c2
  diff=$((hi - lo))
  [ "$diff" -le 1 ]
}

@test "1-step phase: empty suggestions array, exit 0" {
  run bash "$SCRIPT" "${FIXTURES}/split-tiny-plan.md" 1
  [ "$status" -eq 0 ]
  [ "$(suggestion_count "$output")" = "0" ]
  [ "$(original_count "$output")" = "1" ]
}

@test "step ordering: monotonic per suggestion, concatenation equals [1..N]" {
  f="$(make_plan 'six' 6)"
  run bash "$SCRIPT" "$f" 1
  [ "$status" -eq 0 ]
  count="$(suggestion_count "$output")"
  combined=""
  i=0
  while [ "$i" -lt "$count" ]; do
    s="$(suggestion_steps "$i" "$output")"
    # Monotonic check.
    prev=0
    IFS=',' read -ra arr <<< "$s"
    for n in "${arr[@]}"; do
      [ "$n" -gt "$prev" ]
      prev=$n
    done
    if [ -z "$combined" ]; then
      combined="$s"
    else
      combined="${combined},${s}"
    fi
    i=$((i + 1))
  done
  [ "$combined" = "1,2,3,4,5,6" ]
}

@test "Depends on Step 4 on a 6-step phase keeps step 5 (and any later constraint) intact" {
  # 6 steps, 2-way split; default boundary would be after step 3. Step 5
  # carries `Depends on Step 4` so the constraint forces step 4 to live in
  # the same chunk as step 5 — i.e., the boundary must shift to ≥ step 5.
  STEP_5_TEXT="Wire integration test (Depends on Step 4)." \
    f="$(make_plan 'sixdep' 6)"
  run bash "$SCRIPT" "$f" 1
  [ "$status" -eq 0 ]
  [ "$(suggestion_count "$output")" = "2" ]
  s0="$(suggestion_steps 0 "$output")"
  s1="$(suggestion_steps 1 "$output")"
  # Reconstruct full ordering.
  [ "${s0},${s1}" = "1,2,3,4,5,6" ]
  # Constraint: step 5 declares `Depends on Step 4`. Because chunks are
  # contiguous, the rule "no chunk may terminate before its prerequisite
  # is included" reduces to "step 4 and step 5 must live in the same
  # chunk". Find which chunk owns step 5 and assert step 4 is in the same
  # chunk.
  has_step() {
    local needle="$1"
    local list="$2"
    IFS=',' read -ra a <<< "$list"
    for n in "${a[@]}"; do
      [ "$n" = "$needle" ] && return 0
    done
    return 1
  }
  if has_step 5 "$s0"; then
    has_step 4 "$s0"
  else
    has_step 4 "$s1"
    has_step 5 "$s1"
  fi
}

# --- impossible dependency annotations --------------------------------------

@test "impossible forward-pointing dep (Step 1 depends on Step 7 in a 7-step phase): exit 1 with diagnostic" {
  # QA-plan-FEAT-029.md flags this as P0: the constraint loop cannot
  # satisfy a forward-pointing dependency, so the script must surface the
  # bad annotation as an error rather than silently produce a malformed
  # split.
  STEP_1_TEXT="Initialize subsystem (Depends on Step 7)." \
    f="$(make_plan 'forward-dep' 7)"
  stderr_file="${WORK_DIR}/forward-dep-stderr.txt"
  rc=0
  bash "$SCRIPT" "$f" 1 >/dev/null 2>"$stderr_file" || rc=$?
  [ "$rc" -eq 1 ]
  grep -q '^\[error\] split-phase-suggest: phase has impossible dependency' "$stderr_file"
  grep -q 'step 1' "$stderr_file"
  grep -q 'Step 7' "$stderr_file"
}

@test "self-referential dep (Step 3 depends on Step 3): exit 1 with diagnostic" {
  # A step depending on itself is also unsatisfiable; same path as the
  # forward-pointing case.
  STEP_3_TEXT="Self-referential (Depends on Step 3)." \
    f="$(make_plan 'self-dep' 5)"
  stderr_file="${WORK_DIR}/self-dep-stderr.txt"
  rc=0
  bash "$SCRIPT" "$f" 1 >/dev/null 2>"$stderr_file" || rc=$?
  [ "$rc" -eq 1 ]
  grep -q '^\[error\] split-phase-suggest: phase has impossible dependency' "$stderr_file"
  grep -q 'step 3' "$stderr_file"
}

# --- error paths -------------------------------------------------------------

@test "missing args: exit 2 with usage message" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "missing phase arg: exit 2" {
  run bash "$SCRIPT" "${FIXTURES}/split-tiny-plan.md"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "${WORK_DIR}/does-not-exist.md" 1
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: plan file not found'
}

@test "phase block missing in plan: exit 1" {
  run bash "$SCRIPT" "${FIXTURES}/split-tiny-plan.md" 99
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "phase 99 not found"
}
