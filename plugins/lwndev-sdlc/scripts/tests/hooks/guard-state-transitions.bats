#!/usr/bin/env bats
# Bats fixture for BUG-014 Hook B — guard-state-transitions.sh.
#
# Covers (AC4, AC5, AC6, AC9 + QA test plan scenarios):
#   * resume <ID> denied without marker; allowed with fresh marker.
#   * resume <ID> denied when marker mtime < pausedAt (stale marker).
#   * resume <ID> denied on missing pausedAt (pre-fix workflow).
#   * resume <ID> denied on missing/corrupt state file.
#   * clear-gate <ID> denied without marker; allowed with marker.
#   * Destructive Bash patterns denied without merge-approval marker.
#   * Destructive Bash matcher uses prefix-glob (catches `gh pr merge --squash`).
#   * Out-of-scope commands (e.g. `ls`, `git status`) allowed.
#   * Missing jq -> deny.
#   * Missing .active -> deny destructive Bash.

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  HOOK="${PLUGIN_ROOT}/scripts/hooks/guard-state-transitions.sh"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  mkdir -p .sdlc/workflows .sdlc/approvals
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: fire the hook with a Bash command and return its stdout.
fire_hook() {
  local command="$1"
  printf '%s' "$command" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$HOOK"
}

# Helper: parse the permissionDecision from the hook output. Echoes "allow"
# when output is empty (default).
decision_of() {
  local output="$1"
  if [[ -z "$output" ]]; then
    echo "allow"
    return
  fi
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null
}

# Helper: write a workflow state file with the given fields.
write_state() {
  local id="$1"
  local pause_reason="$2"
  local paused_at="$3"
  local gate="${4:-null}"
  local state_file=".sdlc/workflows/${id}.json"
  jq -n \
    --arg id "$id" \
    --arg pr "$pause_reason" \
    --arg pa "$paused_at" \
    --arg gate "$gate" \
    '{
      id: $id, type: "bug", status: "paused", currentStep: 0, steps: [],
      pauseReason: ($pr | select(. != "") // null),
      pausedAt:    ($pa | select(. != "") // null),
      gate:        ($gate | select(. != "null") // null)
    }' > "$state_file"
}

# Helper: write an approval marker.
write_marker() {
  local marker_name="$1"
  local id="$2"
  local marker_path=".sdlc/approvals/.approval-${marker_name}-${id}"
  printf 'timestamp: %s\nworkflow_id: %s\nmessage: test\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" > "$marker_path"
  echo "$marker_path"
}

# ------------------------ resume tests ----------------------------------------

@test "resume denied: no marker present" {
  write_state BUG-014 plan-approval "2026-04-26T00:00:00Z"
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve plan-approval BUG-014"
}

@test "resume allowed: fresh marker present (mtime >= pausedAt)" {
  # pausedAt in the past, marker created now (newer).
  write_state BUG-014 plan-approval "2020-01-01T00:00:00Z"
  write_marker plan-approval BUG-014
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "resume denied: stale marker (mtime < pausedAt)" {
  # Marker created first, then pausedAt set in the future.
  marker=$(write_marker plan-approval BUG-014)
  # Force marker mtime to a known past time.
  touch -t 200001010000 "$marker"
  # State pausedAt set to far future.
  write_state BUG-014 plan-approval "2099-12-31T00:00:00Z"
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "stale"
}

@test "resume denied: missing pausedAt (pre-fix workflow)" {
  # State file with pauseReason but NO pausedAt (simulates pre-fix workflow).
  cat > .sdlc/workflows/BUG-014.json <<'JSON'
{"id":"BUG-014","type":"bug","status":"paused","currentStep":0,"steps":[],"pauseReason":"plan-approval","gate":null}
JSON
  write_marker plan-approval BUG-014
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "predates the pausedAt fix"
}

@test "resume denied: missing state file" {
  output=$(fire_hook "bash workflow-state.sh resume BUG-999")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "state file"
}

@test "resume denied: corrupt state JSON" {
  printf '{not valid json' > .sdlc/workflows/BUG-014.json
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "corrupt"
}

@test "resume denied: workflow has no active pauseReason" {
  cat > .sdlc/workflows/BUG-014.json <<'JSON'
{"id":"BUG-014","type":"bug","status":"in-progress","currentStep":0,"steps":[],"pauseReason":null,"gate":null}
JSON
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "no active pauseReason"
}

# ------------------------ clear-gate tests ------------------------------------

@test "clear-gate denied: no marker present" {
  write_state BUG-014 "" "" "findings-decision"
  output=$(fire_hook "bash workflow-state.sh clear-gate BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-014"
}

@test "clear-gate allowed: marker present" {
  write_state BUG-014 "" "" "findings-decision"
  write_marker findings-decision BUG-014
  output=$(fire_hook "bash workflow-state.sh clear-gate BUG-014")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "clear-gate denied: no active gate" {
  write_state BUG-014 plan-approval "2026-04-26T00:00:00Z" "null"
  output=$(fire_hook "bash workflow-state.sh clear-gate BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "no active gate"
}

# ------------------------ destructive Bash tests ------------------------------

@test "gh pr merge denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "gh pr merge 123 --squash")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "merge BUG-014"
}

@test "gh pr merge allowed with merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  write_marker merge-approval BUG-014
  output=$(fire_hook "gh pr merge 123 --squash")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "gh pr merge with no flags is denied (not just gh pr merge --squash)" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "gh pr merge")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "git push --force denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "git push --force origin main")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "git push -f denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "git push -f origin main")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "git reset --hard denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "git reset --hard HEAD~1")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "gh release create denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "gh release create v1.0.0")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "npm publish denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "npm publish")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "git tag -d denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "git tag -d v1.0.0")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "git push origin :refs/tags/v1 denied without merge-approval marker" {
  echo "BUG-014" > .sdlc/workflows/.active
  output=$(fire_hook "git push origin :refs/tags/v1.0.0")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "destructive Bash denied when .active missing" {
  output=$(fire_hook "gh pr merge 1 --squash")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q ".active"
}

@test "destructive Bash denied when .active is empty" {
  : > .sdlc/workflows/.active
  output=$(fire_hook "gh pr merge 1 --squash")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "destructive Bash denied when .active is malformed" {
  echo "not-an-id" > .sdlc/workflows/.active
  output=$(fire_hook "gh pr merge 1 --squash")
  [ "$(decision_of "$output")" = "deny" ]
}

# ------------------------ pass-through tests ----------------------------------

@test "innocuous Bash (ls) is allowed" {
  output=$(fire_hook "ls -la")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "git status is allowed" {
  output=$(fire_hook "git status")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "git push (without --force / -f) is allowed" {
  output=$(fire_hook "git push origin feature/foo")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "workflow-state.sh status (read-only) is allowed" {
  output=$(fire_hook "bash workflow-state.sh status BUG-014")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "workflow-state.sh advance (not in guard set) is allowed" {
  output=$(fire_hook "bash workflow-state.sh advance BUG-014")
  [ "$(decision_of "$output")" = "allow" ]
}

# ------------------------ FEAT-030 reproduction regression --------------------

@test "FEAT-030 gate 2 reproduction: self-resume immediately after pause is denied" {
  # Synthetic scenario: orchestrator paused (so pausedAt set just now), then
  # tries to resume in the same tool turn. No UserPromptSubmit happened in
  # between, so no marker exists.
  write_state BUG-014 plan-approval "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  output=$(fire_hook "bash workflow-state.sh resume BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve plan-approval BUG-014"
}

@test "FEAT-030 gate 1 reproduction: self-clear-gate after set-gate is denied" {
  # Synthetic scenario: orchestrator set findings-decision gate, then tries
  # to clear-gate in the same tool turn. No marker exists.
  write_state BUG-014 "" "" "findings-decision"
  output=$(fire_hook "bash workflow-state.sh clear-gate BUG-014")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-014"
}
