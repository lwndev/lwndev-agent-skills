#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Bats fixture for BUG-018 / RC-1 — `cmd_advance` atomic auto-pause.
#
# Covers:
#   * advance on non-pause-context step: succeeds, no `pausedAt`,
#     no `status` change (regression: pause-context handling must not
#     affect normal advances).
#   * advance on pause-context step: atomic auto-pause. The same
#     mutation that flips the step to `complete` also sets
#     `status="paused"`, `pauseReason=<derived>`, and stamps
#     `pausedAt` as ISO-8601-Z.
#   * advance on a `status: "paused"` workflow: rejected with a clear
#     error; the state file is byte-identical before and after the
#     failed call.
#   * advance lands on a synthetic pause-context step whose derived
#     reason is not in the `cmd_pause` whitelist: rejected with a
#     clear error; state file is byte-identical (no partial mutation).
#   * advance + resume + advance: round-trip works as expected.
#   * derivation table: "Plan approval" -> plan-approval,
#     "PR review" -> pr-review.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Seed a feature workflow state file with currentStep at the given index and
# every prior step marked complete. The feature step sequence has
# pause-context steps at index 3 ("Plan approval") so seeding currentStep=2
# (step 3, fork) and advancing once lands on the pause-context step at
# index 3.
seed_feature_state() {
  local id="$1"
  local current_step="${2:-0}"
  # workflow-state.sh init writes to ./.sdlc/workflows/<id>.json (cwd-relative).
  ( cd "$TMPDIR_TEST" && bash "$WS" init "$id" feature >/dev/null )
  if (( current_step > 0 )); then
    local state_file="${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
    jq --argjson step "$current_step" \
      '.currentStep = $step
       | .steps |= [range(0; $step) as $i | .[$i] | .status = "complete" | .completedAt = "2026-05-17T00:00:00Z"] + .[$step:]' \
      "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  fi
}

# Inject a synthetic step at the end of the steps array whose derived
# pauseReason is NOT in the cmd_pause whitelist (e.g. "Foo bar" -> foo-bar).
inject_unmapped_pause_step() {
  local id="$1"
  local state_file="${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
  jq '.steps += [{"name":"Foo bar","skill":null,"context":"pause","status":"pending","artifact":null,"completedAt":null}]' \
    "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

# ---- Non-pause-context advance: no behavioral regression -------------------

@test "advance on non-pause-context step: no pausedAt, no status change" {
  seed_feature_state FEAT-100 0
  cd "$TMPDIR_TEST"
  # Step 0 is "Document feature requirements" (context: main). Advancing
  # lands on step 1 ("Review requirements", context: fork) — not a pause.
  run --separate-stderr bash "$WS" advance FEAT-100
  [ "$status" -eq 0 ]
  local state
  state=$(cat ".sdlc/workflows/FEAT-100.json")
  [ "$(echo "$state" | jq -r '.status')" = "in-progress" ]
  [ "$(echo "$state" | jq -r '.pauseReason')" = "null" ]
  [ "$(echo "$state" | jq -r '.pausedAt // \"MISSING\"')" = "MISSING" ] || \
    [ "$(echo "$state" | jq -r '.pausedAt')" = "null" ]
  [ "$(echo "$state" | jq -r '.currentStep')" = "1" ]
  [ "$(echo "$state" | jq -r '.steps[0].status')" = "complete" ]
}

# ---- Advance onto pause-context step: atomic auto-pause --------------------

@test "advance onto Plan approval pause-context step: atomic auto-pause to plan-approval" {
  # Feature steps: 0 doc / 1 review-reqs / 2 plan / 3 PAUSE plan-approval / 4 doc-qa
  # Seed currentStep=2 (step 3, create-plan); advance lands on the pause step.
  seed_feature_state FEAT-101 2
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" advance FEAT-101
  [ "$status" -eq 0 ]
  local state
  state=$(cat ".sdlc/workflows/FEAT-101.json")
  # Step 2 marked complete + currentStep bumped to 3.
  [ "$(echo "$state" | jq -r '.steps[2].status')" = "complete" ]
  [ "$(echo "$state" | jq -r '.currentStep')" = "3" ]
  # Workflow status flipped to paused with derived reason.
  [ "$(echo "$state" | jq -r '.status')" = "paused" ]
  [ "$(echo "$state" | jq -r '.pauseReason')" = "plan-approval" ]
  # pausedAt is stamped as ISO-8601-Z.
  local paused_at
  paused_at=$(echo "$state" | jq -r '.pausedAt')
  [[ "$paused_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "advance onto pause-context step: stderr emits [info] auto-paused line" {
  seed_feature_state FEAT-102 2
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" advance FEAT-102
  [ "$status" -eq 0 ]
  echo "stderr=$stderr"
  [[ "$stderr" =~ \[info\]\ auto-paused ]]
  [[ "$stderr" =~ pauseReason=plan-approval ]]
  # BUG-020 / AC7 — the strengthened audit line MUST also carry the load-bearing
  # HALT and surface tokens (case-sensitive) so an orchestrator reading the
  # line in isolation has the reaction protocol inline.
  [[ "$stderr" =~ HALT ]]
  [[ "$stderr" =~ surface ]]
  # The separator between `(pauseReason=<reason>)` and `HALT` MUST be plain
  # ASCII `- ` hyphen-space (not em-dash / en-dash) so future style edits
  # cannot silently break grep-based callers.
  [[ "$stderr" =~ \)\ -\ HALT ]]
  # Negative: no em-dash or en-dash codepoints in the emitted line.
  [[ ! "$stderr" =~ — ]]
  [[ ! "$stderr" =~ – ]]
}

# ---- Reject second advance on a paused workflow ----------------------------

@test "advance on already-paused workflow: rejected, state byte-identical" {
  seed_feature_state FEAT-103 2
  cd "$TMPDIR_TEST"
  # First advance auto-pauses.
  bash "$WS" advance FEAT-103 >/dev/null 2>&1
  local state_file=".sdlc/workflows/FEAT-103.json"
  # Snapshot the paused state.
  local before_hash
  before_hash=$(shasum "$state_file" | awk '{print $1}')
  # Second advance must be rejected with a clear error.
  run --separate-stderr bash "$WS" advance FEAT-103
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ \[error\]\ cannot\ advance:\ workflow\ paused ]]
  [[ "$stderr" =~ pauseReason=plan-approval ]]
  [[ "$stderr" =~ resume\ first ]]
  # State file is byte-identical (no partial mutation).
  local after_hash
  after_hash=$(shasum "$state_file" | awk '{print $1}')
  [ "$before_hash" = "$after_hash" ]
}

# ---- Reject advance landing on a step whose derived reason is unmapped -----

@test "advance lands on step with unmapped derived reason: rejected, state byte-identical" {
  # Init a feature workflow, inject a synthetic step with name "Foo bar" at
  # the end, then seed currentStep to the step right before it.
  ( cd "$TMPDIR_TEST" && bash "$WS" init FEAT-104 feature >/dev/null )
  inject_unmapped_pause_step FEAT-104
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-104.json"
  local total
  total=$(jq -r '.steps | length' "$state_file")
  # Position currentStep at (total - 2) so the next index is the synthetic
  # unmapped pause step. Mark all earlier steps complete so we are
  # operating on a clean pending step.
  jq --argjson n "$((total - 2))" \
    '.currentStep = $n
     | .steps |= [range(0; $n) as $i | .[$i] | .status = "complete" | .completedAt = "2026-05-17T00:00:00Z"] + .[$n:]' \
    "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  local before_hash
  before_hash=$(shasum "$state_file" | awk '{print $1}')
  run --separate-stderr bash "$WS" advance FEAT-104
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ \[error\]\ derived\ pauseReason\ \'foo-bar\'\ is\ not\ in\ cmd_pause\ whitelist ]]
  local after_hash
  after_hash=$(shasum "$state_file" | awk '{print $1}')
  [ "$before_hash" = "$after_hash" ]
}

# ---- Round-trip: advance (auto-pause) -> resume -> advance succeeds --------

@test "round-trip: advance auto-pauses, resume clears it, next advance succeeds" {
  seed_feature_state FEAT-105 2
  cd "$TMPDIR_TEST"
  # 1. advance auto-pauses on Plan approval.
  bash "$WS" advance FEAT-105 >/dev/null 2>&1
  [ "$(jq -r '.status' ".sdlc/workflows/FEAT-105.json")" = "paused" ]
  # 2. resume clears the pause.
  bash "$WS" resume FEAT-105 >/dev/null
  [ "$(jq -r '.status' ".sdlc/workflows/FEAT-105.json")" = "in-progress" ]
  [ "$(jq -r '.pauseReason' ".sdlc/workflows/FEAT-105.json")" = "null" ]
  # 3. The pause step itself is currentStep=3. The "pending" pause step's
  # status was untouched (the advance only mutated the step BEFORE the
  # pause-context step). resume keeps it pending. Now advancing past the
  # pause step (whose context==pause) lands on step 4 (Document QA, main).
  # Since step 4 is NOT a pause-context step, the advance succeeds without
  # auto-pausing.
  run --separate-stderr bash "$WS" advance FEAT-105
  [ "$status" -eq 0 ]
  local state
  state=$(cat ".sdlc/workflows/FEAT-105.json")
  [ "$(echo "$state" | jq -r '.status')" = "in-progress" ]
  [ "$(echo "$state" | jq -r '.currentStep')" = "4" ]
  [ "$(echo "$state" | jq -r '.steps[3].status')" = "complete" ]
}

# ---- Derivation table ------------------------------------------------------

@test "derivation: \"Plan approval\" -> plan-approval (atomic auto-pause)" {
  seed_feature_state FEAT-106 2
  cd "$TMPDIR_TEST"
  bash "$WS" advance FEAT-106 >/dev/null 2>&1
  [ "$(jq -r '.pauseReason' ".sdlc/workflows/FEAT-106.json")" = "plan-approval" ]
}

@test "derivation: \"PR review\" -> pr-review (atomic auto-pause, chore chain)" {
  # Chore steps: 0 doc / 1 review-reqs / 2 doc-qa / 3 execute / 4 PAUSE pr-review / 5 qa / 6 finalize
  cd "$TMPDIR_TEST"
  bash "$WS" init CHORE-100 chore >/dev/null
  local state_file=".sdlc/workflows/CHORE-100.json"
  # Mark steps 0..3 complete; set currentStep=3 (execute-chore). advance
  # lands on step 4 (PR review pause).
  jq '.currentStep = 3
      | .steps[0].status = "complete"
      | .steps[1].status = "complete"
      | .steps[2].status = "complete"' \
    "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  bash "$WS" advance CHORE-100 >/dev/null 2>&1
  [ "$(jq -r '.pauseReason' "$state_file")" = "pr-review" ]
  [ "$(jq -r '.status' "$state_file")" = "paused" ]
}

# ---- Orchestrator-style three-call sequence (AC5) --------------------------

@test "AC5: orchestrator-style advance -> advance -> advance past step 4 leaves step 4 paused and rejects the third call" {
  # Feature steps: indices 0..4 (doc, review-reqs, plan, plan-approval, doc-qa).
  # Step "4" in the AC's 1-indexed phrasing is step index 3 (plan-approval).
  # Sequence: starting at currentStep=1 (review-reqs done? seed it),
  #   advance #1: completes review-reqs (step 1) -> currentStep=2 (plan, fork)
  #   advance #2: completes plan (step 2) -> currentStep=3 (plan-approval, pause) -> AUTO-PAUSE
  #   advance #3: REJECTED.
  seed_feature_state FEAT-107 1
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-107.json"
  # advance #1 (non-pause)
  bash "$WS" advance FEAT-107 >/dev/null 2>&1
  [ "$(jq -r '.status' "$state_file")" = "in-progress" ]
  [ "$(jq -r '.currentStep' "$state_file")" = "2" ]
  # advance #2 (lands on plan-approval pause-context step)
  bash "$WS" advance FEAT-107 >/dev/null 2>&1
  [ "$(jq -r '.status' "$state_file")" = "paused" ]
  [ "$(jq -r '.pauseReason' "$state_file")" = "plan-approval" ]
  # Plan-approval step itself (index 3) is still pending — auto-pause does
  # not mark the pause step "complete"; the user's resume + next advance
  # does that.
  [ "$(jq -r '.steps[3].status' "$state_file")" = "pending" ]
  # advance #3 must be REJECTED.
  run --separate-stderr bash "$WS" advance FEAT-107
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ workflow\ paused ]]
}
