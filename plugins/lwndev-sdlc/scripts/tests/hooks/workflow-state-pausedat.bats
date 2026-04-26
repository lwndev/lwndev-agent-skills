#!/usr/bin/env bats
# Bats fixture for BUG-014 Phase 1 — workflow-state.sh `cmd_pause` writes
# `pausedAt` (ISO-8601) so Hook B can compare an approval marker mtime against
# the most recent pause time.
#
# Covers (AC9):
#   * pause writes a top-level `pausedAt` ISO-8601 string.
#   * resume does NOT clear `pausedAt` (history is preserved for fail-secure).
#   * second pause overwrites `pausedAt` with the new wall-clock time so a
#     stale approval marker from a prior pause cannot satisfy the new pause.
#   * fresh init produces a state file without `pausedAt` (matches AC9 intent
#     that the field appears on first pause; pre-fix workflows therefore fall
#     through Hook B's "infinitely old" branch).

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORKFLOW_STATE="${PLUGIN_ROOT}/skills/orchestrating-workflows/scripts/workflow-state.sh"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  mkdir -p .sdlc/workflows
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: init a workflow and return its state-file path.
init_workflow() {
  local id="$1"
  local type="$2"
  bash "$WORKFLOW_STATE" init "$id" "$type" >/dev/null
  echo ".sdlc/workflows/${id}.json"
}

@test "fresh init does not write pausedAt" {
  file=$(init_workflow FEAT-900 feature)
  run jq -r '.pausedAt // "ABSENT"' "$file"
  [ "$status" -eq 0 ]
  [ "$output" = "ABSENT" ]
}

@test "pause writes pausedAt as an ISO-8601 string" {
  file=$(init_workflow FEAT-901 feature)

  bash "$WORKFLOW_STATE" pause FEAT-901 plan-approval >/dev/null
  run jq -r '.pausedAt' "$file"
  [ "$status" -eq 0 ]
  # ISO-8601 UTC, no fractional seconds (matches now_iso format).
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "pause sets status, pauseReason, and pausedAt atomically" {
  file=$(init_workflow CHORE-014 chore)

  bash "$WORKFLOW_STATE" pause CHORE-014 pr-review >/dev/null
  run jq -r '.status + "|" + .pauseReason + "|" + (.pausedAt | tostring)' "$file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^paused\|pr-review\|[0-9]{4}- ]]
}

@test "resume preserves pausedAt (history retained for fail-secure)" {
  file=$(init_workflow BUG-014 bug)

  bash "$WORKFLOW_STATE" pause BUG-014 plan-approval >/dev/null
  paused_at_before=$(jq -r '.pausedAt' "$file")
  [ -n "$paused_at_before" ]

  bash "$WORKFLOW_STATE" resume BUG-014 >/dev/null
  paused_at_after=$(jq -r '.pausedAt' "$file")
  [ "$paused_at_before" = "$paused_at_after" ]
}

@test "second pause overwrites pausedAt with new wall-clock time" {
  file=$(init_workflow FEAT-902 feature)

  bash "$WORKFLOW_STATE" pause FEAT-902 plan-approval >/dev/null
  first_paused_at=$(jq -r '.pausedAt' "$file")

  # Sleep to guarantee at least a 1-second mtime delta even on coarse-mtime
  # filesystems (the AC explicitly calls out HFS+ / FAT32 / NFS resolution).
  sleep 1
  bash "$WORKFLOW_STATE" resume FEAT-902 >/dev/null
  bash "$WORKFLOW_STATE" pause FEAT-902 plan-approval >/dev/null
  second_paused_at=$(jq -r '.pausedAt' "$file")

  [ "$first_paused_at" != "$second_paused_at" ]
  # ISO-8601 lexicographic ordering matches chronological ordering for UTC
  # timestamps — the second pause must be strictly later.
  [[ "$second_paused_at" > "$first_paused_at" ]]
}

@test "pause with different reason still updates pausedAt" {
  file=$(init_workflow FEAT-903 feature)

  bash "$WORKFLOW_STATE" pause FEAT-903 plan-approval >/dev/null
  first_paused_at=$(jq -r '.pausedAt' "$file")

  sleep 1
  bash "$WORKFLOW_STATE" resume FEAT-903 >/dev/null
  bash "$WORKFLOW_STATE" pause FEAT-903 pr-review >/dev/null
  second_paused_at=$(jq -r '.pausedAt' "$file")
  second_reason=$(jq -r '.pauseReason' "$file")

  [ "$first_paused_at" != "$second_paused_at" ]
  [ "$second_reason" = "pr-review" ]
}
