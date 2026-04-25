#!/usr/bin/env bats
# Bats fixture for prepare-fork.sh (FEAT-021 / FR-1, FR-2).
#
# Covers the full unit-test matrix from the requirements doc:
#   * Arg validation (exit 2): missing positionals, unknown flags,
#     non-numeric stepIndex, unknown skill-name, --mode on wrong skill,
#     --phase on wrong skill, both --mode and --phase.
#   * SKILL.md resolution (exit 3): delete the target SKILL.md.
#   * State-file missing (exit 2): no state file at .sdlc/workflows/<ID>.json.
#   * jq missing (exit 4): PATH stripped of jq.
#   * Propagation (exit 1+): stubbed resolve-tier exits non-zero.
#   * Happy path non-locked: reviewing-requirements + --mode standard.
#   * Happy path baseline-locked: finalizing-workflow.
#   * Happy path Edge Case 11: creating-implementation-plans + --cli-model haiku.
#   * Repeated --cli-model-for: two occurrences, both forwarded.
#   * Non-bash caller: /bin/sh -c 'bash prepare-fork.sh ...'.
#   * NFR-1 ordering invariant: Step 4 fails, Step 3 audit entry still present.
#   * --help anywhere in argv: first position, last position, after invalid args.

setup() {
  # Locate the prepare-fork.sh under test and the real workflow-state.sh.
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PREPARE_FORK="${SCRIPT_DIR}/prepare-fork.sh"
  PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  REAL_WORKFLOW_STATE="${PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh"

  # Per-test hermetic dir that becomes CWD; state files live at
  # $PWD/.sdlc/workflows/<ID>.json.
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  mkdir -p .sdlc/workflows

  # Default plugin layout: point CLAUDE_PLUGIN_ROOT at a fake plugin tree that
  # contains real SKILL.md stubs for every allowed skill-name and a real
  # workflow-state.sh (symlinked from the source tree) under
  # skills/orchestrating-workflows/scripts/.
  FAKE_PLUGIN="${TMPDIR_TEST}/plugin"
  mkdir -p "${FAKE_PLUGIN}/skills/orchestrating-workflows/scripts"
  ln -s "$REAL_WORKFLOW_STATE" "${FAKE_PLUGIN}/skills/orchestrating-workflows/scripts/workflow-state.sh"
  for s in reviewing-requirements creating-implementation-plans implementing-plan-phases \
           executing-chores executing-bug-fixes finalizing-workflow pr-creation; do
    mkdir -p "${FAKE_PLUGIN}/skills/${s}"
    printf -- '---\nname: %s\n---\n# %s stub\n' "$s" "$s" > "${FAKE_PLUGIN}/skills/${s}/SKILL.md"
  done
  # FEAT-029 FR-8: workflow-state.sh resolve-tier --phase shells out to
  # phase-complexity-budget.sh under creating-implementation-plans/scripts.
  # Symlink the real script so resolve-tier can find it via CLAUDE_PLUGIN_ROOT.
  REAL_PCB="${PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh"
  mkdir -p "${FAKE_PLUGIN}/skills/creating-implementation-plans/scripts"
  ln -s "$REAL_PCB" "${FAKE_PLUGIN}/skills/creating-implementation-plans/scripts/phase-complexity-budget.sh"

  # Path to the FEAT-029 budget-mixed-plan fixture for FR-8 tests.
  BUDGET_MIXED_PLAN="${PLUGIN_ROOT}/skills/creating-implementation-plans/scripts/tests/fixtures/budget-mixed-plan.md"

  export CLAUDE_PLUGIN_ROOT="$FAKE_PLUGIN"
  export CLAUDE_SKILL_DIR="${FAKE_PLUGIN}/skills/orchestrating-workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- helpers ------------------------------------------------------------------

# Seed a valid .sdlc/workflows/<ID>.json state file for the given ID. Extra
# key/value overrides can be supplied as `jq --arg`-style updates passed via
# a single jq filter string in $2.
seed_state() {
  local id="${1:-FEAT-TEST}"
  local extra_filter="${2:-.}"
  local path=".sdlc/workflows/${id}.json"
  cat > "$path" <<EOF
{
  "id": "${id}",
  "type": "feature",
  "status": "in-progress",
  "currentStep": 0,
  "steps": [
    {"name": "documenting-features", "skill": "documenting-features", "status": "complete"},
    {"name": "reviewing-requirements", "skill": "reviewing-requirements", "status": "pending"}
  ],
  "complexity": "medium",
  "complexityStage": "init",
  "modelOverride": null,
  "modelSelections": [],
  "gate": null
}
EOF
  if [[ "$extra_filter" != "." ]]; then
    jq "$extra_filter" "$path" > "${path}.tmp" && mv "${path}.tmp" "$path"
  fi
}

selections_len() {
  local id="${1:-FEAT-TEST}"
  jq -r '.modelSelections | length' ".sdlc/workflows/${id}.json"
}

# Write a stub workflow-state.sh under a replacement CLAUDE_SKILL_DIR. The
# stub script body is taken from stdin.
write_stub_workflow_state() {
  local stub_root="${1:-$TMPDIR_TEST/stub-plugin}"
  mkdir -p "${stub_root}/skills/orchestrating-workflows/scripts"
  local stub_path="${stub_root}/skills/orchestrating-workflows/scripts/workflow-state.sh"
  cat > "$stub_path"
  chmod +x "$stub_path"
  echo "$stub_root"
}

# --- Arg validation (exit 2) -------------------------------------------------

@test "arg validation: missing positionals → exit 2" {
  run bash "$PREPARE_FORK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"three positional arguments"* ]] \
    || [[ "$output" == *"requires three positional"* ]]
}

@test "arg validation: unknown flag → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --bogus x
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "arg validation: non-numeric stepIndex → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST foo reviewing-requirements
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-negative integer"* ]]
  [[ "$output" == *"'foo'"* ]]
}

@test "arg validation: unknown skill-name → exit 2 and list valid names" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 not-a-skill
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown skill-name"* ]]
  [[ "$output" == *"reviewing-requirements"* ]]
  [[ "$output" == *"pr-creation"* ]]
}

@test "arg validation: --mode on non-reviewing-requirements skill → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 implementing-plan-phases --mode standard
  [ "$status" -eq 2 ]
  [[ "$output" == *"--mode is only valid for reviewing-requirements"* ]]
}

@test "arg validation: --phase on non-implementing-plan-phases skill → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --phase 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"--phase is only valid for implementing-plan-phases"* ]]
}

@test "arg validation: --mode and --phase both set → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard --phase 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# --- SKILL.md resolution (exit 3) --------------------------------------------

@test "SKILL.md missing: exit 3 with resolved path in error" {
  seed_state
  rm -f "${CLAUDE_PLUGIN_ROOT}/skills/reviewing-requirements/SKILL.md"
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard
  [ "$status" -eq 3 ]
  [[ "$output" == *"SKILL.md for 'reviewing-requirements' cannot be read"* ]]
  [[ "$output" == *"reviewing-requirements/SKILL.md"* ]]
}

# --- State-file missing (exit 2) ---------------------------------------------

@test "state-file missing: exit 2 with .sdlc/workflows path in error" {
  # No seed_state call.
  run bash "$PREPARE_FORK" FEAT-NOPE 1 reviewing-requirements --mode standard
  [ "$status" -eq 2 ]
  [[ "$output" == *".sdlc/workflows/FEAT-NOPE.json not found"* ]]
}

# --- jq missing (exit 4) -----------------------------------------------------

@test "jq missing: exit 4 with install hint" {
  seed_state
  # Build an empty bin directory that omits jq. Resolve bash to an absolute
  # path BEFORE clearing PATH so `env` can still exec bash, and the inner
  # bash then sees a PATH where `command -v jq` fails.
  mkdir -p "${TMPDIR_TEST}/empty-bin"
  BASH_ABS="$(command -v bash)"
  run env PATH="${TMPDIR_TEST}/empty-bin" "$BASH_ABS" "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard
  [ "$status" -eq 4 ]
  # Step 0b's message must be distinguishable from Step 3's state-file-read
  # message so a caller can tell the two failure modes apart.
  [[ "$output" == *"jq is not installed or not on PATH"* ]]
  [[ "$output" != *"complexityStage"* ]]
}

# --- Propagation (exit 1+) ---------------------------------------------------

@test "propagation: resolve-tier child failure propagates verbatim" {
  seed_state
  # Write a stub workflow-state.sh whose resolve-tier dispatch exits 1 with a
  # distinctive stderr marker we can assert on.
  stub_root="${TMPDIR_TEST}/stub-plugin"
  write_stub_workflow_state "$stub_root" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  resolve-tier)
    echo "Error: STUB-PROPAGATE-MARKER" >&2
    exit 7
    ;;
  *)
    echo "Error: stub does not implement $1" >&2
    exit 1
    ;;
esac
STUB
  # Also need SKILL.md tree and the valid-skill names under the stub plugin
  # so the script's earlier validation passes before Step 2.
  mkdir -p "${stub_root}/skills/reviewing-requirements"
  printf -- '---\nname: x\n---\n' > "${stub_root}/skills/reviewing-requirements/SKILL.md"
  run env CLAUDE_PLUGIN_ROOT="$stub_root" \
          CLAUDE_SKILL_DIR="${stub_root}/skills/orchestrating-workflows" \
          bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard
  [ "$status" -eq 7 ]
  [[ "$output" == *"STUB-PROPAGATE-MARKER"* ]]
}

# --- Happy path non-locked ---------------------------------------------------

@test "happy path non-locked: reviewing-requirements + --mode standard" {
  seed_state
  before=$(selections_len FEAT-TEST)
  # Capture stdout and stderr separately — bats `run` merges them by default,
  # but the stdout-tier contract has to be verified against stdout alone.
  stdout_file="${TMPDIR_TEST}/stdout.log"
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 2 reviewing-requirements --mode standard \
    > "$stdout_file" 2> "$stderr_file"
  status_code=$?
  [ "$status_code" -eq 0 ]
  # stdout is exactly the tier on a single line.
  tier=$(cat "$stdout_file")
  case "$tier" in
    haiku|sonnet|opus) ;;
    *) echo "unexpected tier on stdout: '$tier'" >&2; false ;;
  esac
  # stdout has no extra lines beyond the tier.
  [ "$(wc -l < "$stdout_file" | tr -d ' ')" -eq 1 ]
  # State-file modelSelections grew by exactly 1.
  after=$(selections_len FEAT-TEST)
  [ "$after" -eq $((before + 1)) ]
  # Inspect the newly appended entry.
  entry=$(jq -c '.modelSelections[-1]' ".sdlc/workflows/FEAT-TEST.json")
  [[ "$entry" == *"\"skill\":\"reviewing-requirements\""* ]]
  [[ "$entry" == *"\"mode\":\"standard\""* ]]
  [[ "$entry" == *"\"phase\":null"* ]]
  [[ "$entry" == *"\"stepIndex\":2"* ]]
  [[ "$entry" == *"\"complexityStage\":\"init\""* ]]
}

@test "happy path non-locked: stderr echo line matches the non-locked format" {
  seed_state
  # Capture stderr separately to isolate the echo line from stdout.
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 2 reviewing-requirements --mode standard 2>"$stderr_file" >/dev/null
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 2 (reviewing-requirements, mode=standard)"* ]]
  [[ "$output" == *"baseline="* ]]
  [[ "$output" == *"wi-complexity=medium"* ]]
  [[ "$output" == *"override=none"* ]]
}

# --- Happy path baseline-locked ----------------------------------------------

@test "happy path baseline-locked: finalizing-workflow → haiku, no wi-complexity/override tokens" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 9 finalizing-workflow 2>"$stderr_file" > "${TMPDIR_TEST}/stdout.log"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "${TMPDIR_TEST}/stdout.log")
  [ "$tier" = "haiku" ]
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 9 (finalizing-workflow) → haiku (baseline=haiku, baseline-locked)"* ]]
  [[ "$output" != *"wi-complexity="* ]]
  [[ "$output" != *"override="* ]]
}

# pr-creation is an inline orchestrator operation with no skills/ directory;
# the SKILL.md readability check must be skipped for this canonical exception.
@test "happy path baseline-locked: pr-creation skips SKILL.md check" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 9 pr-creation 2>"$stderr_file" > "${TMPDIR_TEST}/stdout.log"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "${TMPDIR_TEST}/stdout.log")
  [ "$tier" = "haiku" ]
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 9 (pr-creation) → haiku (baseline=haiku, baseline-locked)"* ]]
  [[ "$output" != *"cannot be read"* ]]
}

# --- Edge Case 9: baseline-locked step + hard override -----------------------
# Per FEAT-021 Edge Case 9, a hard override (--cli-model or --cli-model-for)
# that pushes a baseline-locked step off its baseline flips the echo to the
# non-locked variant. The override surfaces in the `override=` token.
@test "Edge Case 9: finalizing-workflow + --cli-model opus emits non-locked line" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 9 finalizing-workflow --cli-model opus 2>"$stderr_file" > "${TMPDIR_TEST}/stdout.log"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "${TMPDIR_TEST}/stdout.log")
  [ "$tier" = "opus" ]
  run cat "$stderr_file"
  [[ "$output" == *"wi-complexity="* ]]
  [[ "$output" == *"override=cli-model:opus"* ]]
  [[ "$output" != *"baseline-locked"* ]]
}

@test "Edge Case 9: pr-creation + --cli-model opus emits non-locked line" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 9 pr-creation --cli-model opus 2>"$stderr_file" > "${TMPDIR_TEST}/stdout.log"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "${TMPDIR_TEST}/stdout.log")
  [ "$tier" = "opus" ]
  run cat "$stderr_file"
  [[ "$output" == *"wi-complexity="* ]]
  [[ "$output" == *"override=cli-model:opus"* ]]
  [[ "$output" != *"baseline-locked"* ]]
}

# --- Happy path Edge Case 11 -------------------------------------------------

@test "happy path Edge Case 11: creating-implementation-plans + --cli-model haiku emits warning" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 3 creating-implementation-plans --cli-model haiku 2>"$stderr_file" > "${TMPDIR_TEST}/stdout.log"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "${TMPDIR_TEST}/stdout.log")
  [ "$tier" = "haiku" ]
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 3 (creating-implementation-plans) → haiku"* ]]
  [[ "$output" == *"override=cli-model:haiku"* ]]
  [[ "$output" == *"Hard override --model haiku bypassed baseline sonnet for creating-implementation-plans"* ]]
}

# --- Repeated --cli-model-for ------------------------------------------------

@test "repeated --cli-model-for: each occurrence forwarded to resolve-tier" {
  seed_state
  # Stub workflow-state.sh to log every resolve-tier invocation's arguments
  # into a scratch file; return canned output for step-baseline / locked.
  stub_root="${TMPDIR_TEST}/stub-plugin"
  call_log="${TMPDIR_TEST}/resolve-tier.args"
  : > "$call_log"
  write_stub_workflow_state "$stub_root" <<STUB
#!/usr/bin/env bash
case "\$1" in
  resolve-tier)
    shift
    printf '%s\n' "\$@" > "$call_log"
    echo sonnet
    ;;
  record-model-selection)
    # Swallow and succeed.
    exit 0
    ;;
  step-baseline)
    echo sonnet
    ;;
  step-baseline-locked)
    echo false
    ;;
  *)
    echo "unhandled: \$1" >&2
    exit 1
    ;;
esac
STUB
  mkdir -p "${stub_root}/skills/reviewing-requirements"
  printf -- '---\nname: x\n---\n' > "${stub_root}/skills/reviewing-requirements/SKILL.md"
  run env CLAUDE_PLUGIN_ROOT="$stub_root" \
          CLAUDE_SKILL_DIR="${stub_root}/skills/orchestrating-workflows" \
          bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard \
            --cli-model-for reviewing-requirements:opus \
            --cli-model-for creating-implementation-plans:haiku
  [ "$status" -eq 0 ]
  # Confirm both --cli-model-for values landed in the logged args.
  run cat "$call_log"
  [[ "$output" == *"reviewing-requirements:opus"* ]]
  [[ "$output" == *"creating-implementation-plans:haiku"* ]]
  # Both flags should appear — count the --cli-model-for occurrences.
  occurrences=$(grep -c '^--cli-model-for$' "$call_log" || true)
  [ "$occurrences" -eq 2 ]
}

# --- Non-bash caller ---------------------------------------------------------

@test "non-bash caller: invoke from /bin/sh -c 'bash prepare-fork.sh ...'" {
  seed_state
  # Forward the env we need and invoke via /bin/sh to prove the shebang wins.
  run env -i PATH="$PATH" \
            CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" \
            CLAUDE_SKILL_DIR="$CLAUDE_SKILL_DIR" \
            HOME="$HOME" \
        /bin/sh -c "cd '$TMPDIR_TEST' && bash '$PREPARE_FORK' FEAT-TEST 2 reviewing-requirements --mode standard"
  [ "$status" -eq 0 ]
  case "$output" in
    *haiku|*sonnet|*opus) ;;
    *) echo "unexpected output: '$output'" >&2; false ;;
  esac
}

# --- NFR-1 ordering invariant ------------------------------------------------

@test "NFR-1 ordering invariant: Step 4 failure preserves Step 3 audit entry" {
  seed_state
  # Stub workflow-state.sh: resolve-tier and record-model-selection succeed
  # against the REAL state file; step-baseline-locked exits non-zero to force
  # a Step 4 failure AFTER Step 3 has written the audit entry.
  stub_root="${TMPDIR_TEST}/stub-plugin"
  real_wss="$REAL_WORKFLOW_STATE"
  write_stub_workflow_state "$stub_root" <<STUB
#!/usr/bin/env bash
case "\$1" in
  resolve-tier)
    # Forward to the real script so the real tier computation runs.
    exec "$real_wss" "\$@"
    ;;
  record-model-selection)
    # Forward to the real script so the real audit entry is appended.
    exec "$real_wss" "\$@"
    ;;
  step-baseline)
    echo sonnet
    ;;
  step-baseline-locked)
    echo "Error: STUB-STEP4-FAILURE" >&2
    exit 11
    ;;
  *)
    exec "$real_wss" "\$@"
    ;;
esac
STUB
  mkdir -p "${stub_root}/skills/reviewing-requirements"
  printf -- '---\nname: x\n---\n' > "${stub_root}/skills/reviewing-requirements/SKILL.md"
  before=$(selections_len FEAT-TEST)
  run env CLAUDE_PLUGIN_ROOT="$stub_root" \
          CLAUDE_SKILL_DIR="${stub_root}/skills/orchestrating-workflows" \
          bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --mode standard
  # Exit code propagates.
  [ "$status" -eq 11 ]
  [[ "$output" == *"STUB-STEP4-FAILURE"* ]]
  # modelSelections grew by exactly 1 despite the Step 4 failure.
  after=$(selections_len FEAT-TEST)
  [ "$after" -eq $((before + 1)) ]
}

# --- --help anywhere in argv -------------------------------------------------

@test "--help as first arg → exit 0 with usage on stdout" {
  run bash "$PREPARE_FORK" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: prepare-fork.sh"* ]]
}

@test "--help as last arg (after positionals) → exit 0 with usage on stdout" {
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: prepare-fork.sh"* ]]
}

@test "--help after an invalid skill-name → help still wins (exit 0)" {
  run bash "$PREPARE_FORK" FEAT-TEST 1 not-a-skill --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: prepare-fork.sh"* ]]
}

@test "-h short form anywhere → exit 0 with usage" {
  run bash "$PREPARE_FORK" FEAT-TEST -h 1 reviewing-requirements
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: prepare-fork.sh"* ]]
}

# --- FEAT-029 FR-8: --phase / --plan-file forwarding ------------------------

# Per-phase forwarding for implementing-plan-phases on budget-mixed-plan.md
# (phases score [haiku, sonnet, opus, opus]). Phase 1 → haiku, Phase 2 → sonnet,
# Phase 4 → opus. Asserts (a) the resolved tier on stdout matches the per-phase
# tier and (b) the FR-14 echo line on stderr carries the new
# `(workflow=<complexity>, phase=<N>=<tier>, override=<token>)` parenthetical
# suffix. The `override=` token preserves the dacc38e audit-trail invariant.

@test "FR-8: --phase 1 --plan-file resolves implementing-plan-phases to haiku" {
  seed_state
  stdout_file="${TMPDIR_TEST}/stdout.log"
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 6 implementing-plan-phases \
    --phase 1 --plan-file "$BUDGET_MIXED_PLAN" \
    > "$stdout_file" 2> "$stderr_file"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "$stdout_file")
  [ "$tier" = "haiku" ]
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 6 (implementing-plan-phases) → haiku (workflow=medium, phase=1=haiku, override=none)"* ]]
}

@test "FR-8: --phase 2 --plan-file resolves implementing-plan-phases to sonnet" {
  seed_state
  stdout_file="${TMPDIR_TEST}/stdout.log"
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 7 implementing-plan-phases \
    --phase 2 --plan-file "$BUDGET_MIXED_PLAN" \
    > "$stdout_file" 2> "$stderr_file"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "$stdout_file")
  [ "$tier" = "sonnet" ]
  run cat "$stderr_file"
  [[ "$output" == *"phase=2=sonnet, override=none"* ]]
}

@test "FR-8: --phase 4 --plan-file resolves implementing-plan-phases to opus" {
  seed_state
  stdout_file="${TMPDIR_TEST}/stdout.log"
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 9 implementing-plan-phases \
    --phase 4 --plan-file "$BUDGET_MIXED_PLAN" \
    > "$stdout_file" 2> "$stderr_file"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "$stdout_file")
  [ "$tier" = "opus" ]
  run cat "$stderr_file"
  [[ "$output" == *"phase=4=opus, override=none"* ]]
}

# Edge Case 9 + FR-8 interaction: per-phase forking with an active hard
# override MUST surface the override token in the audit-trail line, the
# same invariant dacc38e established for non-per-phase forks.

@test "FR-8 + override: --phase 1 + --cli-model opus pins the per-phase tier and surfaces override token" {
  seed_state
  stdout_file="${TMPDIR_TEST}/stdout.log"
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 6 implementing-plan-phases \
    --phase 1 --plan-file "$BUDGET_MIXED_PLAN" --cli-model opus \
    > "$stdout_file" 2> "$stderr_file"
  status_code=$?
  [ "$status_code" -eq 0 ]
  tier=$(cat "$stdout_file")
  [ "$tier" = "opus" ]
  run cat "$stderr_file"
  [[ "$output" == *"phase=1=opus, override=cli-model:opus"* ]]
}

# Partial-flag rejection: both --phase and --plan-file MUST be supplied
# together. Either alone exits 2 with the documented error.

@test "FR-8: --phase without --plan-file → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 6 implementing-plan-phases --phase 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--phase and --plan-file must be supplied together"* ]]
}

@test "FR-8: --plan-file without --phase → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 6 implementing-plan-phases --plan-file "$BUDGET_MIXED_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--phase and --plan-file must be supplied together"* ]]
}

# --plan-file on a non-implementing-plan-phases skill → exit 2.
@test "FR-8: --plan-file on reviewing-requirements → exit 2" {
  seed_state
  run bash "$PREPARE_FORK" FEAT-TEST 1 reviewing-requirements --plan-file "$BUDGET_MIXED_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--plan-file is only valid for implementing-plan-phases"* ]]
}

# Forks for skills other than implementing-plan-phases must keep using the
# existing FEAT-021 echo format unchanged when --phase/--plan-file are absent.
@test "FR-8: other skills keep the FEAT-021 echo format when --phase absent" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 4 executing-chores 2> "$stderr_file" > /dev/null
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 4 (executing-chores)"* ]]
  [[ "$output" == *"baseline=sonnet"* ]]
  [[ "$output" == *"wi-complexity=medium"* ]]
  [[ "$output" == *"override=none"* ]]
  # Must NOT carry the per-phase suffix.
  [[ "$output" != *"workflow="* ]]
  [[ "$output" != *"phase="* ]]
}

# implementing-plan-phases without --phase keeps the FEAT-021 format too —
# the per-phase echo variant only kicks in when both --phase and --plan-file
# are supplied. Backward compat for callers that haven't been updated yet.
@test "FR-8: implementing-plan-phases without --phase uses FEAT-021 echo format" {
  seed_state
  stderr_file="${TMPDIR_TEST}/stderr.log"
  bash "$PREPARE_FORK" FEAT-TEST 6 implementing-plan-phases 2> "$stderr_file" > /dev/null
  run cat "$stderr_file"
  [[ "$output" == *"[model] step 6 (implementing-plan-phases)"* ]]
  [[ "$output" == *"baseline=haiku"* ]]
  [[ "$output" == *"wi-complexity=medium"* ]]
  [[ "$output" == *"override=none"* ]]
  [[ "$output" != *"workflow="* ]]
}
