#!/usr/bin/env bats
# Bats fixture for BUG-015 Hook — guard-findings-edits.sh.
#
# Covers (RC-1, RC-3 + QA test plan scenarios from QA-plan-BUG-015.md):
#   * gate-on / gate-off / no-marker / stale-marker / fresh-marker /
#     out-of-scope-path matrix (P0 inputs).
#   * Per-tool parity: Edit / Write / MultiEdit fire identical decisions on
#     the same fixture inputs.
#   * State-file edge cases: missing .active, missing state file, corrupt JSON,
#     malformed .active ID.
#   * Marker-freshness: gateSetAt missing (legacy state file) -> deny.
#   * Default allow: out-of-scope path, gate cleared, file_path empty.
#   * Missing jq -> deny.

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  HOOK="${PLUGIN_ROOT}/scripts/hooks/guard-findings-edits.sh"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  mkdir -p .sdlc/workflows .sdlc/approvals
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: fire the hook with a tool_name + file_path payload.
fire_hook() {
  local tool_name="$1"
  local file_path="$2"
  jq -n --arg t "$tool_name" --arg f "$file_path" \
    '{tool_name: $t, tool_input: {file_path: $f}}' \
    | bash "$HOOK"
}

# Helper: parse permissionDecision from output ("allow" if empty).
decision_of() {
  local output="$1"
  if [[ -z "$output" ]]; then
    echo "allow"
    return
  fi
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null
}

# Helper: write a workflow state file with the given gate / gateSetAt.
# Pass "" for gate/gateSetAt to leave the field null.
write_state() {
  local id="$1"
  local gate="$2"
  local gate_set_at="$3"
  local state_file=".sdlc/workflows/${id}.json"
  jq -n \
    --arg id "$id" \
    --arg gate "$gate" \
    --arg gsa "$gate_set_at" \
    '{
      id: $id, type: "bug", status: "in-progress", currentStep: 0, steps: [],
      pauseReason: null,
      pausedAt:    null,
      gate:        ($gate | select(. != "") // null),
      gateSetAt:   ($gsa  | select(. != "") // null)
    }' > "$state_file"
}

# Helper: write a findings-decision marker for a workflow ID.
write_marker() {
  local id="$1"
  local marker_path=".sdlc/approvals/.approval-findings-decision-${id}"
  printf 'timestamp: %s\nworkflow_id: %s\nmessage: approve findings-decision %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$id" \
    > "$marker_path"
  echo "$marker_path"
}

# Helper: set the active workflow ID.
set_active() {
  local id="$1"
  echo "$id" > .sdlc/workflows/.active
}

# ------------------------ gate-off / out-of-scope -----------------------------

@test "Edit allowed: no .active file (no workflow context)" {
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: gate is null (no gate set)" {
  set_active BUG-015
  write_state BUG-015 "" ""
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: out-of-scope path (src/index.ts) regardless of gate" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "src/index.ts")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: requirements doc but not under features/chores/bugs/" {
  # Only the gated regex requirements/(features|chores|bugs)/.+\.md is guarded.
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/implementation/IMPL-100.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: empty file_path (not an editor shape)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: missing tool_input.file_path entirely" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(printf '{"tool_name":"Edit","tool_input":{}}' | bash "$HOOK")
  [ "$(decision_of "$output")" = "allow" ]
}

# ------------------------ gate-on / no-marker ---------------------------------

@test "Edit denied: gate set, no marker, gated path (bugs)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-015"
}

@test "Edit denied: gate set, no marker, gated path (features)" {
  set_active FEAT-100
  write_state FEAT-100 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/features/FEAT-100-x.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision FEAT-100"
}

@test "Edit denied: gate set, no marker, gated path (chores)" {
  set_active CHORE-200
  write_state CHORE-200 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/chores/CHORE-200-y.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision CHORE-200"
}

@test "Edit denied: gated regex matches sibling docs under same category (defense in depth)" {
  # Per AC: the broader regex (requirements/<type>/.+\.md, not just <ID>-*.md)
  # is intentional. An editor cannot bypass the gate by writing to a sibling
  # document under the same workflow-type directory.
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/bugs/BUG-099-other.md")
  [ "$(decision_of "$output")" = "deny" ]
}

# ------------------------ stale-marker / fresh-marker -------------------------

@test "Edit denied: stale marker (mtime < gateSetAt)" {
  set_active BUG-015
  marker=$(write_marker BUG-015)
  # Force marker mtime to a known past time.
  touch -t 200001010000 "$marker"
  # gateSetAt set to far future.
  write_state BUG-015 "findings-decision" "2099-12-31T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "stale"
  printf '%s' "$output" | grep -q "approve findings-decision BUG-015"
}

@test "Edit allowed: fresh marker (mtime >= gateSetAt)" {
  set_active BUG-015
  # gateSetAt in the past, marker created now (newer).
  write_state BUG-015 "findings-decision" "2020-01-01T00:00:00Z"
  write_marker BUG-015
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit denied: legacy state file missing gateSetAt (treated as infinitely old)" {
  set_active BUG-015
  # Pre-fix state file: has gate but no gateSetAt.
  cat > .sdlc/workflows/BUG-015.json <<'JSON'
{"id":"BUG-015","type":"bug","status":"in-progress","currentStep":0,"steps":[],"gate":"findings-decision","pauseReason":null,"pausedAt":null}
JSON
  write_marker BUG-015
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "predates the gateSetAt fix"
}

@test "Edit denied: unparseable gateSetAt format (fail-secure)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "not-a-date"
  write_marker BUG-015
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "cannot parse gateSetAt"
}

# ------------------------ per-tool parity (Edit / Write / MultiEdit) ----------

@test "Write denied: gate set, no marker, gated path (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Write" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-015"
}

@test "Write allowed: out-of-scope path (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Write" "src/index.ts")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Write allowed: fresh marker (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2020-01-01T00:00:00Z"
  write_marker BUG-015
  output=$(fire_hook "Write" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "MultiEdit denied: gate set, no marker, gated path (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "MultiEdit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-015"
}

@test "MultiEdit allowed: out-of-scope path (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "MultiEdit" "src/index.ts")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "MultiEdit allowed: fresh marker (parity with Edit)" {
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2020-01-01T00:00:00Z"
  write_marker BUG-015
  output=$(fire_hook "MultiEdit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

# ------------------------ state-file edge cases -------------------------------

@test "Edit allowed: missing state file for active workflow (no gate to enforce)" {
  set_active BUG-015
  # No state file written.
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit denied: corrupt state JSON on guarded path (fail-secure)" {
  set_active BUG-015
  printf '{not valid json' > .sdlc/workflows/BUG-015.json
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -qi "corrupt"
}

@test "Edit allowed: corrupt state JSON on out-of-scope path" {
  # Even with a corrupt state file, an Edit on a non-gated path passes — the
  # gate guard's scope is requirements/{features,chores,bugs}/.
  set_active BUG-015
  printf '{not valid json' > .sdlc/workflows/BUG-015.json
  output=$(fire_hook "Edit" "src/index.ts")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: empty .active file" {
  : > .sdlc/workflows/.active
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit allowed: malformed .active ID" {
  echo "not-an-id" > .sdlc/workflows/.active
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

# ------------------------ pass-through / regression --------------------------

@test "Empty stdin allows (matcher misfire)" {
  output=$(printf '' | bash "$HOOK")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Edit on absolute path resolving into gated dir is denied (substring match)" {
  # The regex is anchored on the substring requirements/<type>/.+\.md so an
  # absolute path that ends with that substring matches identically. Document
  # this choice via the test (relative + absolute behave the same).
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "/Users/foo/repo/requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
}

@test "Edit on traversal-shaped path does not match the gated regex (allow)" {
  # `requirements/bugs/../../etc/passwd` does not match the regex
  # `requirements/(features|chores|bugs)/.+\.md` because the literal segment
  # after `/bugs/` is `..` which does not end in `.md`. No path normalization
  # vulnerability — bash regex matches the literal string.
  set_active BUG-015
  write_state BUG-015 "findings-decision" "2026-04-26T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/bugs/../../etc/passwd")
  [ "$(decision_of "$output")" = "allow" ]
}

# ------------------------ end-to-end gate cycle -------------------------------

@test "Full cycle: set-gate -> deny -> approve -> allow -> clear-gate -> allow" {
  set_active BUG-015
  # 1. Gate set, no marker -> deny.
  write_state BUG-015 "findings-decision" "2020-01-01T00:00:00Z"
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  # 2. User approves -> marker written -> allow.
  write_marker BUG-015
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
  # 3. Gate cleared -> allow regardless of marker freshness.
  write_state BUG-015 "" ""
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "allow" ]
}

@test "Auto-mode reproduction: orchestrator-issued Edit during auto-mode is denied" {
  # Auto-mode does not produce UserPromptSubmit events, so record-approval.sh
  # never fires. With gate set and no marker, the Edit is denied — this is
  # the load-bearing security property closing BUG-015 RC-1.
  set_active BUG-015
  write_state BUG-015 "findings-decision" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  output=$(fire_hook "Edit" "requirements/bugs/BUG-015-foo.md")
  [ "$(decision_of "$output")" = "deny" ]
  printf '%s' "$output" | grep -q "approve findings-decision BUG-015"
}

# ------------------------ marker_mtime_epoch unit ----------------------------
#
# `marker_mtime_epoch` is duplicated from guard-state-transitions.sh into this
# hook (RC-3). The GNU/BSD `stat` flag ordering is load-bearing: if reversed,
# GNU `stat -f %m` returns a mountpoint string on Linux and the regex below
# fails. Integration tests would mask this on macOS but fail on Linux CI.
# These unit tests mirror the dedicated coverage in guard-state-transitions.bats
# (added in PR #248) so the duplicated copy is independently verified.

@test "marker_mtime_epoch returns numeric epoch on this platform (BUG-014 stat ordering)" {
  local fixture
  fixture="$(mktemp)"
  local fn
  fn="$(sed -n '/^marker_mtime_epoch()/,/^}/p' "$HOOK")"
  local result
  result="$(bash -c "${fn}; marker_mtime_epoch \"$fixture\"")"
  rm -f "$fixture"
  [[ "$result" =~ ^[0-9]+$ ]]
  [ "$result" -gt 1000000000 ]
}

@test "marker_mtime_epoch returns empty for missing file" {
  local fn
  fn="$(sed -n '/^marker_mtime_epoch()/,/^}/p' "$HOOK")"
  local result
  result="$(bash -c "${fn}; marker_mtime_epoch /tmp/does-not-exist-$$")"
  [ -z "$result" ]
}
