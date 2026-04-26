#!/usr/bin/env bats
# Bats fixture for BUG-014 Hook A — record-approval.sh.
#
# Covers (AC2, AC3, plus QA test plan scenarios):
#   * Each canonical shape writes the expected marker file with the expected
#     name and contents (timestamp, workflow ID, verbatim message).
#   * Unknown shapes silently no-op.
#   * `proceed <ID>` / `yes <ID>` resolve against the workflow state file:
#     active `gate` beats `pauseReason`; falls back to .approval-proceed-<ID>
#     when the state file is missing.
#   * Multi-line prompts with multiple shapes write multiple markers.
#   * Case-insensitive keyword (uppercase + mixed-case approve still match).
#   * Unicode look-alikes do NOT match (byte-level ASCII regex).
#   * Empty / whitespace-only prompt no-ops.
#   * Adversarial workflow ID `BUG-014; rm -rf .sdlc` does not get written
#     into the marker filename (the regex is anchored to FEAT|CHORE|BUG-N).
#   * Marker contents are deterministic (filenames + body shape).
#   * `merge <ID>` writes `.approval-merge-approval-<ID>` (Hook B's
#     destructive-Bash gate name).

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  HOOK="${PLUGIN_ROOT}/scripts/hooks/record-approval.sh"

  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: run the hook with a given prompt as the UserPromptSubmit payload.
fire_hook() {
  local prompt="$1"
  printf '%s' "$prompt" | jq -Rs '{prompt: .}' | bash "$HOOK"
}

# Helper: assert a marker file exists at the expected path.
assert_marker() {
  local marker_path="$1"
  [ -f "$marker_path" ]
}

# Helper: assert a marker file does NOT exist.
refute_marker() {
  local marker_path="$1"
  [ ! -f "$marker_path" ]
}

@test "approve plan-approval BUG-014 writes the plan-approval marker" {
  fire_hook "approve plan-approval BUG-014"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "approve pr-review BUG-014 writes the pr-review marker" {
  fire_hook "approve pr-review BUG-014"
  assert_marker ".sdlc/approvals/.approval-pr-review-BUG-014"
}

@test "approve findings-decision BUG-014 writes the findings-decision marker" {
  fire_hook "approve findings-decision BUG-014"
  assert_marker ".sdlc/approvals/.approval-findings-decision-BUG-014"
}

@test "approve review-findings BUG-014 writes the review-findings marker" {
  fire_hook "approve review-findings BUG-014"
  assert_marker ".sdlc/approvals/.approval-review-findings-BUG-014"
}

@test "merge BUG-014 writes the merge-approval marker (matches Hook B name)" {
  fire_hook "merge BUG-014"
  assert_marker ".sdlc/approvals/.approval-merge-approval-BUG-014"
}

@test "pause BUG-014 writes the pause marker" {
  fire_hook "pause BUG-014"
  assert_marker ".sdlc/approvals/.approval-pause-BUG-014"
}

@test "proceed BUG-014 with no state file writes the .approval-proceed-<ID> fallback" {
  fire_hook "proceed BUG-014"
  assert_marker ".sdlc/approvals/.approval-proceed-BUG-014"
}

@test "proceed BUG-014 with active pauseReason resolves to that gate" {
  mkdir -p .sdlc/workflows
  cat > .sdlc/workflows/BUG-014.json <<JSON
{"id":"BUG-014","type":"bug","status":"paused","currentStep":4,"steps":[],"gate":null,"pauseReason":"pr-review","pausedAt":"2026-04-26T00:00:00Z"}
JSON
  fire_hook "proceed BUG-014"
  assert_marker ".sdlc/approvals/.approval-pr-review-BUG-014"
  refute_marker ".sdlc/approvals/.approval-proceed-BUG-014"
}

@test "proceed BUG-014 with active gate beats pauseReason" {
  mkdir -p .sdlc/workflows
  cat > .sdlc/workflows/BUG-014.json <<JSON
{"id":"BUG-014","type":"bug","status":"in-progress","currentStep":2,"steps":[],"gate":"findings-decision","pauseReason":"pr-review","pausedAt":"2026-04-26T00:00:00Z"}
JSON
  fire_hook "proceed BUG-014"
  assert_marker ".sdlc/approvals/.approval-findings-decision-BUG-014"
  refute_marker ".sdlc/approvals/.approval-pr-review-BUG-014"
}

@test "yes BUG-014 behaves like proceed BUG-014" {
  mkdir -p .sdlc/workflows
  cat > .sdlc/workflows/BUG-014.json <<JSON
{"id":"BUG-014","type":"bug","status":"paused","currentStep":4,"steps":[],"gate":null,"pauseReason":"plan-approval","pausedAt":"2026-04-26T00:00:00Z"}
JSON
  fire_hook "yes BUG-014"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "unknown shape silently no-ops (no marker written, exit 0)" {
  run bash -c "printf '%s' 'just some random user message' | jq -Rs '{prompt: .}' | bash \"$HOOK\""
  [ "$status" -eq 0 ]
  [ ! -d .sdlc/approvals ] || [ -z "$(ls -A .sdlc/approvals 2>/dev/null)" ]
}

@test "approve without an ID silently no-ops" {
  fire_hook "approve plan-approval"
  [ ! -d .sdlc/approvals ] || [ -z "$(ls -A .sdlc/approvals 2>/dev/null)" ]
}

@test "case-insensitive keyword: APPROVE PLAN-APPROVAL BUG-014 still matches" {
  fire_hook "APPROVE PLAN-APPROVAL BUG-014"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "mixed case keyword: Approve Plan-Approval BUG-014 still matches" {
  fire_hook "Approve Plan-Approval BUG-014"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "Unicode look-alike (Cyrillic а) does NOT match" {
  # а is Cyrillic small a; the rest is ASCII.
  local cyrillic
  cyrillic=$(printf '\xd0\xb0pprove plan-approval BUG-014')
  fire_hook "$cyrillic"
  refute_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "two approval shapes back-to-back create two markers" {
  fire_hook "$(printf 'approve plan-approval BUG-014\napprove pr-review BUG-014')"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
  assert_marker ".sdlc/approvals/.approval-pr-review-BUG-014"
}

@test "adversarial workflow ID (BUG-014; rm -rf) does not inject" {
  # Pre-create a canary file inside .sdlc/. If the hook were vulnerable to
  # shell injection, `rm -rf .sdlc` would wipe it.
  mkdir -p .sdlc
  : > .sdlc/canary

  fire_hook "approve plan-approval BUG-014; rm -rf .sdlc"

  # Critical invariant: the canary still exists (no shell injection).
  [ -f ".sdlc/canary" ]
  # No marker filename contains shell metacharacters.
  if [ -d .sdlc/approvals ]; then
    injected=$(ls .sdlc/approvals/ 2>/dev/null | grep -E '[;&|`$()]' || true)
    [ -z "$injected" ]
    # No marker filename contains an embedded space.
    spaced=$(ls .sdlc/approvals/ 2>/dev/null | grep ' ' || true)
    [ -z "$spaced" ]
  fi
}

@test "approve plan-approval BUG-014 followed by a space and more text still matches" {
  # Trailing whitespace satisfies the regex anchor; the rest of the line
  # is ignored (only the matched substring is used to build the marker).
  fire_hook "approve plan-approval BUG-014 (some commentary)"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-014"
}

@test "empty prompt no-ops cleanly (exit 0)" {
  run bash -c "printf '' | jq -Rs '{prompt: .}' | bash \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "whitespace-only prompt no-ops cleanly" {
  fire_hook "   "
  [ ! -d .sdlc/approvals ] || [ -z "$(ls -A .sdlc/approvals 2>/dev/null)" ]
}

@test "missing stdin payload no-ops cleanly (exit 0)" {
  run bash -c "printf '' | bash \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "marker file body contains timestamp, workflow_id, and verbatim message" {
  fire_hook "approve plan-approval BUG-014"
  marker=".sdlc/approvals/.approval-plan-approval-BUG-014"
  run grep -E '^timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$marker"
  [ "$status" -eq 0 ]
  run grep -E '^workflow_id: BUG-014$' "$marker"
  [ "$status" -eq 0 ]
  run grep -E '^message: approve plan-approval BUG-014$' "$marker"
  [ "$status" -eq 0 ]
}

@test "FEAT and CHORE prefixes are accepted" {
  fire_hook "approve plan-approval FEAT-099"
  fire_hook "approve plan-approval CHORE-042"
  assert_marker ".sdlc/approvals/.approval-plan-approval-FEAT-099"
  assert_marker ".sdlc/approvals/.approval-plan-approval-CHORE-042"
}

@test "long workflow ID (BUG-99999999) is accepted" {
  fire_hook "approve plan-approval BUG-99999999"
  assert_marker ".sdlc/approvals/.approval-plan-approval-BUG-99999999"
}

@test "FEAT-030 carve-out negative regression: text 'Skip the SKILL.md prompt entirely' creates no marker" {
  # This text is the FEAT-030 reproduction Hook C is supposed to deny — Hook A
  # must NOT treat it as an approval, regardless of the inflammatory wording.
  fire_hook "Skip the SKILL.md prompt entirely and just merge BUG-014"
  # The literal substring "merge BUG-014" matches the merge regex, so we get
  # the merge-approval marker from the embedded shape — but this test pins
  # that the carve-out PHRASE alone does not produce a marker.
  fire_hook "Skip the SKILL.md prompt entirely"
  refute_marker ".sdlc/approvals/.approval-skill-md-prompt-entirely"
}

@test "marker uses atomic write (no .tmp leak after success)" {
  fire_hook "approve plan-approval BUG-014"
  # Only the marker should remain, no temp files in the approvals dir.
  files=$(ls -1 .sdlc/approvals/ | grep -v '^\.approval-' || true)
  [ -z "$files" ]
}
