#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for BUG-018 / RC-2 — `auto-fixed` removed from
# `record-findings` (review) decision whitelist.
#
# Covers:
#   * record-findings (default --type review) with `auto-fixed`: rejected
#     with a clear error naming the valid set; no findings written.
#   * record-findings --rerun with `auto-fixed`: also rejected (no
#     special-casing of the rerun code path).
#   * Each of the four remaining valid decisions (`advanced`,
#     `auto-advanced`, `user-advanced`, `paused`) still succeeds and
#     persists the matching decision string.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/../../../fixtures/orchestrating-workflows"
  WS="${SCRIPT_DIR}/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

seed_state() {
  local fixture_name="$1"
  local id="$2"
  cp "${FIXTURES_DIR}/sdlc-workflows/${fixture_name}.json" "${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
}

# ---- Rejection: auto-fixed -------------------------------------------------

@test "record-findings auto-fixed (default --type review): rejected, no findings written" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-030.json"
  # Snapshot to assert no findings write.
  local before_hash
  before_hash=$(shasum "$state_file" | awk '{print $1}')
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 1 0 0 auto-fixed "Apply fixes summary."
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ decision\ to\ be\ one\ of:\ advanced,\ auto-advanced,\ user-advanced,\ paused ]]
  # State file is byte-identical (no findings persisted, no partial mutation).
  local after_hash
  after_hash=$(shasum "$state_file" | awk '{print $1}')
  [ "$before_hash" = "$after_hash" ]
}

@test "record-findings --rerun auto-fixed: also rejected (no rerun special-casing)" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  local state_file=".sdlc/workflows/FEAT-030.json"
  local before_hash
  before_hash=$(shasum "$state_file" | awk '{print $1}')
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 1 0 0 auto-fixed "Re-run summary." --rerun
  [ "$status" -ne 0 ]
  [[ "$stderr" =~ decision\ to\ be\ one\ of:\ advanced,\ auto-advanced,\ user-advanced,\ paused ]]
  local after_hash
  after_hash=$(shasum "$state_file" | awk '{print $1}')
  [ "$before_hash" = "$after_hash" ]
}

# ---- The four remaining valid decisions still succeed ----------------------

@test "record-findings advanced: succeeds, persists decision=advanced" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 0 0 0 advanced "No issues found"
  [ "$status" -eq 0 ]
  local decision
  decision=$(echo "$output" | jq -r '.steps[1].findings.decision')
  [ "$decision" = "advanced" ]
}

@test "record-findings auto-advanced: succeeds, persists decision=auto-advanced" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 0 2 1 auto-advanced "2 warnings, 1 info — auto-advanced"
  [ "$status" -eq 0 ]
  local decision
  decision=$(echo "$output" | jq -r '.steps[1].findings.decision')
  [ "$decision" = "auto-advanced" ]
}

@test "record-findings user-advanced: succeeds, persists decision=user-advanced" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 0 1 0 user-advanced "User confirmed"
  [ "$status" -eq 0 ]
  local decision
  decision=$(echo "$output" | jq -r '.steps[1].findings.decision')
  [ "$decision" = "user-advanced" ]
}

@test "record-findings paused: succeeds, persists decision=paused" {
  seed_state "FEAT-030-qa" "FEAT-030"
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" record-findings FEAT-030 1 1 0 0 paused "Errors present — user paused"
  [ "$status" -eq 0 ]
  local decision
  decision=$(echo "$output" | jq -r '.steps[1].findings.decision')
  [ "$decision" = "paused" ]
}

# ---- SKILL.md prose contract (RC-3): the carve-out paragraph -------------

@test "BUG-018 RC-3: orchestrating-workflows SKILL.md carve-outs contains the system reminder phrase and all five gate identifiers" {
  local skill_md
  skill_md="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows" && pwd)/SKILL.md"
  [ -f "$skill_md" ]
  local body
  body=$(cat "$skill_md")
  # AC8 (a): verbatim system reminder phrase must appear.
  echo "$body" | grep -qF "work without stopping for clarifying questions"
  # AC8 (b): all five gate identifiers must appear.
  for gate in "plan-approval" "pr-review" "findings-decision" "review-findings" "merge-approval"; do
    echo "$body" | grep -qF "$gate" || { echo "Missing gate identifier: $gate"; false; }
  done
  # ASCII-only invariant: the new carve-out line that names the system
  # reminder must NOT contain Unicode quote / em-dash characters. Use
  # portable grep -F against each forbidden literal codepoint.
  local carveout_line
  carveout_line=$(grep -F "work without stopping" "$skill_md")
  for bad in $'\xe2\x80\x98' $'\xe2\x80\x99' $'\xe2\x80\x9c' $'\xe2\x80\x9d' $'\xe2\x80\x94'; do
    if echo "$carveout_line" | grep -qF "$bad"; then
      echo "Carve-out line contains forbidden Unicode character"
      false
    fi
  done
}
