#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for BUG-020 / RC-5 — `cmd_set_gate` whitelist extension.
#
# Covers:
#   * `set-gate <ID> merge-approval` on an in-progress workflow succeeds,
#     writes `.gate = "merge-approval"` and a fresh ISO-8601 `.gateSetAt`.
#   * `set-gate <ID> findings-decision` continues to succeed (regression
#     against the pre-existing gate value).
#   * `set-gate <ID> <unknown-value>` rejects with exit 1 and the new error
#     pattern `Expected one of: findings-decision, merge-approval`.
#   * `set-gate <ID> merge-approval` is idempotent — calling twice in
#     succession leaves the gate set and refreshes `gateSetAt`.
#   * `set-gate` on a paused workflow rejects with the existing
#     `Cannot set gate on a paused workflow` error (no regression).

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

init_feature() {
  local id="$1"
  ( cd "$TMPDIR_TEST" && bash "$WS" init "$id" feature >/dev/null )
}

# ---- merge-approval gate succeeds on in-progress workflow ------------------

@test "set-gate merge-approval succeeds; .gate and .gateSetAt are written" {
  init_feature FEAT-200
  cd "$TMPDIR_TEST"
  run bash "$WS" set-gate FEAT-200 merge-approval
  [ "$status" -eq 0 ]
  local state_file=".sdlc/workflows/FEAT-200.json"
  [ "$(jq -r '.gate' "$state_file")" = "merge-approval" ]
  local gate_set_at
  gate_set_at=$(jq -r '.gateSetAt' "$state_file")
  # ISO-8601-Z stamp (matches `now_iso` shape).
  [[ "$gate_set_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ---- findings-decision regression ------------------------------------------

@test "set-gate findings-decision continues to succeed (regression)" {
  init_feature FEAT-201
  cd "$TMPDIR_TEST"
  run bash "$WS" set-gate FEAT-201 findings-decision
  [ "$status" -eq 0 ]
  local state_file=".sdlc/workflows/FEAT-201.json"
  [ "$(jq -r '.gate' "$state_file")" = "findings-decision" ]
  local gate_set_at
  gate_set_at=$(jq -r '.gateSetAt' "$state_file")
  [[ "$gate_set_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ---- invalid gate types rejected with the new error pattern ----------------

@test "set-gate bogus rejects with exit 1 and the multi-value error pattern" {
  init_feature FEAT-202
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-202 bogus
  [ "$status" -eq 1 ]
  [[ "$stderr" =~ Error:\ Invalid\ gate\ type ]]
  [[ "$stderr" =~ Expected\ one\ of:\ findings-decision,\ merge-approval ]]
  # State file is unchanged.
  local state_file=".sdlc/workflows/FEAT-202.json"
  [ "$(jq -r '.gate' "$state_file")" = "null" ]
}

@test "set-gate MERGE-APPROVAL (wrong case) rejects on enum check" {
  init_feature FEAT-203
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-203 MERGE-APPROVAL
  [ "$status" -eq 1 ]
  [[ "$stderr" =~ Expected\ one\ of:\ findings-decision,\ merge-approval ]]
}

@test "set-gate with empty string rejects on enum check" {
  init_feature FEAT-204
  cd "$TMPDIR_TEST"
  run --separate-stderr bash "$WS" set-gate FEAT-204 ""
  [ "$status" -eq 1 ]
  [[ "$stderr" =~ Expected\ one\ of:\ findings-decision,\ merge-approval ]]
}

# ---- idempotence: two successive set-gate merge-approval calls -------------

@test "set-gate merge-approval is idempotent: second call refreshes gateSetAt" {
  init_feature FEAT-205
  cd "$TMPDIR_TEST"
  bash "$WS" set-gate FEAT-205 merge-approval >/dev/null
  local state_file=".sdlc/workflows/FEAT-205.json"
  local first_ts
  first_ts=$(jq -r '.gateSetAt' "$state_file")
  # Ensure the second call gets a different second on the clock.
  sleep 1
  bash "$WS" set-gate FEAT-205 merge-approval >/dev/null
  local second_ts
  second_ts=$(jq -r '.gateSetAt' "$state_file")
  [ "$(jq -r '.gate' "$state_file")" = "merge-approval" ]
  [[ "$second_ts" > "$first_ts" ]]
}

# ---- set-gate rejected on non-in-progress workflows ------------------------

@test "set-gate merge-approval on paused workflow rejects with existing error" {
  init_feature FEAT-206
  cd "$TMPDIR_TEST"
  bash "$WS" pause FEAT-206 plan-approval >/dev/null
  run --separate-stderr bash "$WS" set-gate FEAT-206 merge-approval
  [ "$status" -eq 1 ]
  [[ "$stderr" =~ Cannot\ set\ gate\ on\ a\ paused\ workflow ]]
}
