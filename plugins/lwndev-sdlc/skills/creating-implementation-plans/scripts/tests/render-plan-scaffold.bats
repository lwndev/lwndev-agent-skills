#!/usr/bin/env bats
# Bats fixture for render-plan-scaffold.sh (FEAT-029 / FR-1).
#
# Covers:
#   * Happy-path single feature: rendered title, one summary row, one phase
#     block per FR, **Status:** Pending lines.
#   * Happy-path multi-feature (FEAT-XXX,FEAT-YYY): two summary rows, four
#     phase blocks (two per source feature in document order), title taken
#     from the primary feature's name.
#   * Whitespace tolerance: `FEAT-XXX, FEAT-YYY` parses identically to the
#     no-space form.
#   * --enforce-phase-budget: gate passes on the rendered placeholder
#     plan and Phase 3 removed the Phase 1 placeholder warn line, so
#     stderr MUST NOT contain that warn line; exit 0.
#   * Error paths: missing arg → exit 2; malformed FEAT-IDs → exit 2;
#     target file already exists → exit 2; resolver failure → exit 1 with
#     resolver stderr surfaced.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/render-plan-scaffold.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  REAL_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  REAL_RESOLVER="${REAL_PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh"
  REAL_TEMPLATE="${REAL_PLUGIN_ROOT}/skills/creating-implementation-plans/assets/implementation-plan.md"

  # Per-test hermetic working directory. The resolver globs
  # `requirements/features/<ID>-*.md` relative to $PWD, so we mirror that
  # layout under the temp dir and `cd` into it before invoking the script.
  FIXTURE_DIR="$(mktemp -d)"
  cd "$FIXTURE_DIR"
  mkdir -p requirements/features

  # Drop the three fixture feature docs into the synthetic requirements
  # tree under their canonical FEAT-NNN-<slug>.md filenames.
  cp "${FIXTURES}/feat-fixture-single.md" requirements/features/FEAT-901-single-fixture.md
  cp "${FIXTURES}/feat-fixture-multi-a.md" requirements/features/FEAT-902-multi-fixture-a.md
  cp "${FIXTURES}/feat-fixture-multi-b.md" requirements/features/FEAT-903-multi-fixture-b.md

  # Build a fake plugin root containing the real resolver and template,
  # without polluting the live skill tree.
  FAKE_PLUGIN="${FIXTURE_DIR}/plugin"
  mkdir -p "${FAKE_PLUGIN}/scripts" \
           "${FAKE_PLUGIN}/skills/creating-implementation-plans/assets"
  ln -s "$REAL_RESOLVER" "${FAKE_PLUGIN}/scripts/resolve-requirement-doc.sh"
  ln -s "$REAL_TEMPLATE" "${FAKE_PLUGIN}/skills/creating-implementation-plans/assets/implementation-plan.md"
  export CLAUDE_PLUGIN_ROOT="$FAKE_PLUGIN"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# --- happy paths -------------------------------------------------------------

@test "single feature: stdout is absolute target path; rendered file matches contract" {
  run bash "$SCRIPT" "FEAT-901"
  [ "$status" -eq 0 ]
  # stdout: absolute path to rendered plan
  target="$output"
  [[ "$target" = /* ]]
  [ "$(basename "$target")" = "FEAT-901-single-fixture.md" ]
  [ -f "$target" ]
  # title
  grep -q '^# Implementation Plan: Single Feature Fixture$' "$target"
  # one summary row
  summary_rows=$(grep -c '^| FEAT-' "$target")
  [ "$summary_rows" -eq 1 ]
  # three phase blocks (one per FR)
  phase_blocks=$(grep -c '^### Phase ' "$target")
  [ "$phase_blocks" -eq 3 ]
  # Status: Pending lines on every phase
  status_lines=$(grep -c '^\*\*Status:\*\* Pending$' "$target")
  [ "$status_lines" -eq 3 ]
}

@test "multi feature: two rows, four phases, primary name in title" {
  run bash "$SCRIPT" "FEAT-902,FEAT-903"
  [ "$status" -eq 0 ]
  target="$output"
  [[ "$target" = /* ]]
  [ "$(basename "$target")" = "FEAT-902-multi-fixture-a.md" ]
  [ -f "$target" ]
  grep -q '^# Implementation Plan: Multi-Feature Fixture A (Primary)$' "$target"
  summary_rows=$(grep -c '^| FEAT-' "$target")
  [ "$summary_rows" -eq 2 ]
  phase_blocks=$(grep -c '^### Phase ' "$target")
  [ "$phase_blocks" -eq 4 ]
  # Document order: phases 1+2 reference FEAT-902, phases 3+4 reference FEAT-903.
  awk '/^### Phase /{p=$0} /^\*\*Feature:\*\*/{print p" -> "$0}' "$target" > order.txt
  grep -q '^### Phase 1: .* -> .*FEAT-902' order.txt
  grep -q '^### Phase 2: .* -> .*FEAT-902' order.txt
  grep -q '^### Phase 3: .* -> .*FEAT-903' order.txt
  grep -q '^### Phase 4: .* -> .*FEAT-903' order.txt
}

@test "whitespace tolerance: 'FEAT-XXX, FEAT-YYY' parses identically" {
  run bash "$SCRIPT" "FEAT-902, FEAT-903"
  [ "$status" -eq 0 ]
  [ "$(basename "$output")" = "FEAT-902-multi-fixture-a.md" ]
  phase_blocks=$(grep -c '^### Phase ' "$output")
  [ "$phase_blocks" -eq 4 ]
}

@test "--enforce-phase-budget: gate passes on rendered placeholder plan, no Phase 1 placeholder warn" {
  # Phase 3 wires --enforce-phase-budget to validate-phase-sizes.sh. A
  # freshly-rendered scaffold has placeholder phase blocks with `[TBD]`
  # implementation steps and a single `[ ] [TBD]` deliverable per phase —
  # all signals score `haiku`, so the gate must pass. The script resolves
  # validate-phase-sizes.sh as a sibling of itself (script_dir), so it
  # picks up the real validator from the live skill tree without any
  # symlink bookkeeping.
  stderr_file="${FIXTURE_DIR}/stderr.txt"
  bash "$SCRIPT" "FEAT-901" --enforce-phase-budget >/dev/null 2>"$stderr_file"
  rc=$?
  [ "$rc" -eq 0 ]
  # The Phase 1 placeholder line MUST NOT appear (Phase 3 removed it).
  ! grep -q '^\[warn\] --enforce-phase-budget will activate once validate-phase-sizes.sh ships' "$stderr_file"
}

# --- error paths -------------------------------------------------------------

@test "missing arg: exit 2 with usage message" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: usage:'
}

@test "malformed FEAT-IDs (lowercase): exit 2" {
  run bash "$SCRIPT" "feat-029"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: malformed FEAT-IDs'
}

@test "malformed FEAT-IDs (no number): exit 2" {
  run bash "$SCRIPT" "FEAT-"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: malformed FEAT-IDs'
}

@test "malformed FEAT-IDs (empty element after split): exit 2" {
  run bash "$SCRIPT" "FEAT-901,,FEAT-902"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: malformed FEAT-IDs'
}

@test "target file already exists: exit 2" {
  mkdir -p requirements/implementation
  : > requirements/implementation/FEAT-901-single-fixture.md
  run bash "$SCRIPT" "FEAT-901"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^error: target file already exists'
}

@test "resolver failure: exit 1 with resolver stderr surfaced" {
  # FEAT-999 has no fixture; resolver should report 'no file matches'.
  run bash "$SCRIPT" "FEAT-999"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'no file matches FEAT-999'
}
