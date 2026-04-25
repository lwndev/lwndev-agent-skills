#!/usr/bin/env bats
# Bats fixture for phase-complexity-budget.sh (FEAT-029 / FR-3).
#
# Covers:
#   * Happy path with --phase 1 on budget-mixed-plan.md → JSON object,
#     tier `haiku`, all four signals reported.
#   * Happy path without --phase → JSON array, four entries in document
#     order, tiers [haiku, sonnet, opus, opus].
#   * Threshold boundaries: steps 3→haiku, 4→sonnet, 7→sonnet, 8→opus;
#     same shape for deliverables (4/5, 9/10) and files (3/4, 8/9).
#   * Heuristic flag matches: low-flag `schema` on a sonnet-base phase →
#     bumps to opus; high-flag `security` on a haiku-base phase → bumps
#     to sonnet.
#   * Heuristic stacking: a phase matching both `schema` and `public api`
#     and a sonnet-base → caps at opus, no overflow.
#   * `overBudget` true when steps independently score opus AND no override
#     clamping (use a phase with 9 steps but only 2 deliverables / 1 file).
#   * `**ComplexityOverride:**` clamps: haiku, sonnet, opus all replace
#     the computed tier; `overBudget` reported as the pre-override value
#     (false when override clamps an over-budget phase down).
#   * Fence-awareness: `**ComplexityOverride:**` inside a fenced block
#     ignored.
#   * Error tests: missing arg → exit 2; malformed --phase abc → exit 2;
#     non-existent file → exit 1; plan with no `### Phase` blocks → exit 1.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/phase-complexity-budget.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  WORK_DIR="$(mktemp -d)"
}

teardown() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}

# Helper: extract a JSON field from a single-object stdout via jq when
# available, otherwise via grep on the canonical printf shape.
json_field() {
  local key="$1"
  local json="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${key}"
  else
    # Best-effort regex fallback (string values).
    printf '%s' "$json" | sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p"
  fi
}

# Build a synthetic plan with N implementation-step lines, M deliverable
# lines (each with a unique backticked path), into "${WORK_DIR}/$1.md".
# Optional 4th arg adds extra body text (e.g., heuristic flag substring).
# Optional 5th arg sets a **ComplexityOverride:** value.
make_plan() {
  local name="$1"
  local steps="$2"
  local delivs="$3"
  local extra_body="${4:-}"
  local override="${5:-}"
  local f="${WORK_DIR}/${name}.md"
  {
    printf '# Plan: %s\n\n' "$name"
    printf '### Phase 1: Test\n\n'
    printf '**Status:** Pending\n'
    if [ -n "$override" ]; then
      printf '**ComplexityOverride:** %s\n' "$override"
    fi
    if [ -n "$extra_body" ]; then
      printf '\n%s\n' "$extra_body"
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
      printf -- '- [ ] `path/file%d.sh`\n' "$i"
      i=$((i + 1))
    done
  } > "$f"
  printf '%s' "$f"
}

# --- happy paths -------------------------------------------------------------

@test "happy --phase 1 on mixed: tier haiku, all signals reported" {
  run bash "$SCRIPT" "${FIXTURES}/budget-mixed-plan.md" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'phase' "$output")" = "1" ]
  [ "$(json_field 'tier' "$output")" = "haiku" ]
  [ "$(json_field 'signals.steps' "$output")" = "3" ]
  [ "$(json_field 'signals.deliverables' "$output")" = "4" ]
  [ "$(json_field 'signals.files' "$output")" = "3" ]
  [ "$(json_field 'overBudget' "$output")" = "false" ]
}

@test "happy no --phase on mixed: array, tiers [haiku, sonnet, opus, opus]" {
  run bash "$SCRIPT" "${FIXTURES}/budget-mixed-plan.md"
  [ "$status" -eq 0 ]
  if command -v jq >/dev/null 2>&1; then
    tiers="$(printf '%s' "$output" | jq -r '.[].tier' | tr '\n' ',')"
    [ "$tiers" = "haiku,sonnet,opus,opus," ]
    n="$(printf '%s' "$output" | jq -r 'length')"
    [ "$n" -eq 4 ]
  else
    # printf fallback: count the four object opens.
    n=$(printf '%s' "$output" | grep -o '"phase":[0-9]' | wc -l | tr -d ' ')
    [ "$n" -eq 4 ]
    echo "$output" | grep -q '"phase":1,"tier":"haiku"'
    echo "$output" | grep -q '"phase":2,"tier":"sonnet"'
    echo "$output" | grep -q '"phase":3,"tier":"opus"'
    echo "$output" | grep -q '"phase":4,"tier":"opus"'
  fi
}

# --- threshold boundaries: steps -------------------------------------------

@test "boundary: steps 3 -> haiku" {
  f="$(make_plan 'steps3' 3 1)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "haiku" ]
}

@test "boundary: steps 4 -> sonnet" {
  f="$(make_plan 'steps4' 4 1)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
}

@test "boundary: steps 7 -> sonnet" {
  f="$(make_plan 'steps7' 7 1)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
}

@test "boundary: steps 8 -> opus" {
  f="$(make_plan 'steps8' 8 1)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
}

# --- threshold boundaries: deliverables -------------------------------------
#
# These tests isolate the deliverables axis by using duplicated backticked
# paths so the files axis stays at 1 (haiku).

# Build a plan with $1 step lines and $2 deliverable lines, all sharing the
# same backticked path so the unique-files count is exactly 1.
make_deliv_plan() {
  local name="$1"
  local delivs="$2"
  local f="${WORK_DIR}/${name}.md"
  {
    printf '# Plan\n\n### Phase 1: Test\n\n**Status:** Pending\n\n'
    printf '#### Implementation Steps\n\n1. Step.\n\n'
    printf '#### Deliverables\n\n'
    local i=1
    while [ "$i" -le "$delivs" ]; do
      printf -- '- [ ] `dup.sh` line %d\n' "$i"
      i=$((i + 1))
    done
  } > "$f"
  printf '%s' "$f"
}

@test "boundary: deliverables 4 -> haiku" {
  f="$(make_deliv_plan 'deliv4' 4)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "haiku" ]
  [ "$(json_field 'signals.deliverables' "$output")" = "4" ]
  [ "$(json_field 'signals.files' "$output")" = "1" ]
}

@test "boundary: deliverables 5 -> sonnet" {
  f="$(make_deliv_plan 'deliv5' 5)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
  [ "$(json_field 'signals.deliverables' "$output")" = "5" ]
  [ "$(json_field 'signals.files' "$output")" = "1" ]
}

@test "boundary: deliverables 9 -> sonnet" {
  # 9 deliverables mean 9 unique files, which would push files axis to opus.
  # We need a plan that has 9 deliverables but fewer than 9 unique files —
  # so reuse the same backticked path across multiple deliverable lines.
  f="${WORK_DIR}/deliv9.md"
  {
    printf '# Plan\n\n### Phase 1: Test\n\n**Status:** Pending\n\n'
    printf '#### Implementation Steps\n\n1. Step.\n\n'
    printf '#### Deliverables\n\n'
    printf -- '- [ ] `dup.sh` line 1\n'
    printf -- '- [ ] `dup.sh` line 2\n'
    printf -- '- [ ] `dup.sh` line 3\n'
    printf -- '- [ ] `dup.sh` line 4\n'
    printf -- '- [ ] `dup.sh` line 5\n'
    printf -- '- [ ] `dup.sh` line 6\n'
    printf -- '- [ ] `dup.sh` line 7\n'
    printf -- '- [ ] `dup.sh` line 8\n'
    printf -- '- [ ] `dup.sh` line 9\n'
  } > "$f"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
  [ "$(json_field 'signals.deliverables' "$output")" = "9" ]
  [ "$(json_field 'signals.files' "$output")" = "1" ]
}

@test "boundary: deliverables 10 -> opus" {
  f="${WORK_DIR}/deliv10.md"
  {
    printf '# Plan\n\n### Phase 1: Test\n\n**Status:** Pending\n\n'
    printf '#### Implementation Steps\n\n1. Step.\n\n'
    printf '#### Deliverables\n\n'
    local i=1
    while [ "$i" -le 10 ]; do
      printf -- '- [ ] `dup.sh` line %d\n' "$i"
      i=$((i + 1))
    done
  } > "$f"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
}

# --- threshold boundaries: files --------------------------------------------

@test "boundary: files 3 -> haiku" {
  f="$(make_plan 'files3' 1 3)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "haiku" ]
  [ "$(json_field 'signals.files' "$output")" = "3" ]
}

@test "boundary: files 4 -> sonnet" {
  f="$(make_plan 'files4' 1 4)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
  [ "$(json_field 'signals.files' "$output")" = "4" ]
}

@test "boundary: files 8 -> sonnet" {
  f="$(make_plan 'files8' 1 8)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
  [ "$(json_field 'signals.files' "$output")" = "8" ]
}

@test "boundary: files 9 -> opus" {
  f="$(make_plan 'files9' 1 9)"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
  [ "$(json_field 'signals.files' "$output")" = "9" ]
}

# --- heuristic flags --------------------------------------------------------

@test "heuristic: low-flag schema on sonnet-base bumps to opus" {
  # 5 steps + 1 file = sonnet base. Add 'schema' substring to body.
  f="$(make_plan 'lowflag' 5 1 'This phase touches the schema layer.')"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
  if command -v jq >/dev/null 2>&1; then
    [ "$(printf '%s' "$output" | jq -r '.signals.flagsLow[0]')" = "schema" ]
  else
    echo "$output" | grep -q '"flagsLow":\["schema"\]'
  fi
}

@test "heuristic: high-flag security on haiku-base bumps to sonnet" {
  # 1 step + 1 file = haiku base. Add 'security' substring.
  f="$(make_plan 'highflag' 1 1 'Security review required.')"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
}

@test "heuristic stacking: schema + public api on sonnet-base caps at opus" {
  f="$(make_plan 'stack' 5 1 'Touches schema and public api boundaries.')"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
  if command -v jq >/dev/null 2>&1; then
    [ "$(printf '%s' "$output" | jq -r '.signals.flagsLow | length')" = "1" ]
    [ "$(printf '%s' "$output" | jq -r '.signals.flagsHigh | length')" = "1" ]
  fi
}

# --- overBudget -------------------------------------------------------------

@test "overBudget true: 9 steps with 2 deliverables and 1 file" {
  # Steps 9 -> opus axis; deliverables 2 -> haiku; files 1 -> haiku.
  # max = opus from steps; no override -> overBudget = true.
  f="${WORK_DIR}/over.md"
  {
    printf '# Plan\n\n### Phase 1: Big\n\n**Status:** Pending\n\n'
    printf '#### Implementation Steps\n\n'
    local i=1
    while [ "$i" -le 9 ]; do
      printf '%d. Step.\n' "$i"
      i=$((i + 1))
    done
    printf '\n#### Deliverables\n\n'
    printf -- '- [ ] `only.sh` first ref\n'
    printf -- '- [ ] `only.sh` second ref\n'
  } > "$f"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
  [ "$(json_field 'overBudget' "$output")" = "true" ]
  [ "$(json_field 'signals.files' "$output")" = "1" ]
}

# --- ComplexityOverride -----------------------------------------------------

@test "override haiku clamps opus down; overBudget false (clamp wins)" {
  run bash "$SCRIPT" "${FIXTURES}/budget-override-plan.md" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "haiku" ]
  [ "$(json_field 'override' "$output")" = "haiku" ]
  [ "$(json_field 'overBudget' "$output")" = "false" ]
}

@test "override sonnet on opus-base clamps down" {
  f="$(make_plan 'osonnet' 9 1 '' 'sonnet')"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "sonnet" ]
  [ "$(json_field 'override' "$output")" = "sonnet" ]
}

@test "override opus on haiku-base bumps up" {
  f="$(make_plan 'oopus' 1 1 '' 'opus')"
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  [ "$(json_field 'tier' "$output")" = "opus" ]
  [ "$(json_field 'override' "$output")" = "opus" ]
  # No signal independently scored opus, so overBudget stays false.
  [ "$(json_field 'overBudget' "$output")" = "false" ]
}

@test "override inside fenced block: ignored" {
  f="${WORK_DIR}/fenced-override.md"
  cat > "$f" <<'EOF'
# Plan

### Phase 1: Fenced Override Demo

**Status:** Pending

Template documentation:

```
**ComplexityOverride:** haiku
```

#### Implementation Steps

1. One.
2. Two.
3. Three.
4. Four.
5. Five.
6. Six.
7. Seven.
8. Eight.
9. Nine.

#### Deliverables

- [ ] `f1.sh`
EOF
  run bash "$SCRIPT" "$f" --phase 1
  [ "$status" -eq 0 ]
  # Override inside fence ignored → real signals win → opus.
  [ "$(json_field 'tier' "$output")" = "opus" ]
  [ "$(json_field 'override' "$output")" = "null" ]
}

# --- error paths -------------------------------------------------------------

@test "missing arg: exit 2 with usage message" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "malformed --phase abc: exit 2" {
  run bash "$SCRIPT" "${FIXTURES}/budget-mixed-plan.md" --phase abc
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'positive integer'
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "${WORK_DIR}/does-not-exist.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q '^error: plan file not found'
}

@test "plan with no Phase blocks: exit 1" {
  cat > "${WORK_DIR}/no-phases.md" <<'EOF'
# Plan

Just prose.
EOF
  run bash "$SCRIPT" "${WORK_DIR}/no-phases.md"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'no `### Phase` blocks'
}
