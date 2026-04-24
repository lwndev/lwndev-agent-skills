#!/usr/bin/env bats
# Bats fixture for findings-decision.sh (FEAT-028 / FR-3).
#
# Covers:
#   * Decision-Flow three-way branch: advance / auto-advance / prompt-user
#     / pause-errors.
#   * Chain-type + complexity gate matrix: feature, chore, bug × low /
#     medium / high.
#   * Output JSON echoes the state file's `type` and `complexity` fields.
#   * Error cases: missing state file (1), missing arg (2), malformed ID
#     (2), malformed counts JSON (1).
#
# Fixture strategy: each test chdirs into a per-test mktemp dir where a
# fresh `.sdlc/workflows/` is seeded from the static fixtures under
# `tests/fixtures/sdlc-workflows/`. This keeps tests hermetic even if the
# repo grows a real `.sdlc/` dir later.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  FD="${SCRIPT_DIR}/findings-decision.sh"
  TMPDIR_TEST="$(mktemp -d)"
  mkdir -p "${TMPDIR_TEST}/.sdlc/workflows"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Copy a static state file fixture into the sandbox.
seed_state() {
  local id="$1"
  cp "${FIXTURES_DIR}/sdlc-workflows/${id}.json" "${TMPDIR_TEST}/.sdlc/workflows/${id}.json"
}

# Write a synthesized state file with arbitrary type/complexity for matrix
# tests that need combinations beyond the three canned fixtures.
write_state() {
  local id="$1"
  local type="$2"
  local complexity="$3"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/${id}.json" <<EOF
{
  "id": "${id}",
  "type": "${type}",
  "currentStep": 1,
  "status": "in-progress",
  "pauseReason": null,
  "gate": null,
  "steps": [],
  "phases": { "total": 0, "completed": 0 },
  "prNumber": null,
  "branch": null,
  "startedAt": "2026-04-23T00:00:00Z",
  "lastResumedAt": null,
  "complexity": "${complexity}",
  "complexityStage": "init",
  "modelOverride": null,
  "modelSelections": []
}
EOF
}

# Read a field from the output JSON.
get_field() {
  local json="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${key}"
  else
    printf '%s' "$json" | sed -E "s/.*\"${key}\":\"([^\"]+)\".*/\1/"
  fi
}

# ---- zero-findings branch ---------------------------------------------------

@test "zero counts → action advance, reason zero findings, exit 0" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "advance" ]
  [ "$(get_field "$output" reason)" = "zero findings" ]
}

@test "zero counts on chore chain → action advance (zero findings beats chain/complexity gate)" {
  seed_state CHORE-001
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-001 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "advance" ]
}

# ---- errors-present branch --------------------------------------------------

@test "errors > 0 → action pause-errors, exit 0" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":1,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "pause-errors" ]
  [ "$(get_field "$output" reason)" = "errors present" ]
}

@test "errors + warnings both present → pause-errors (errors take precedence)" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":1,"warnings":2,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "pause-errors" ]
}

@test "errors + info both present → pause-errors" {
  seed_state CHORE-001
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-001 2 '{"errors":3,"warnings":0,"info":4}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "pause-errors" ]
}

# ---- warnings/info only: chain × complexity matrix --------------------------

@test "warnings only, feature chain → prompt-user" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":0,"warnings":2,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "prompt-user" ]
  [ "$(get_field "$output" reason)" = "feature chain or high-complexity chore|bug" ]
}

@test "warnings only, chore chain, complexity low → auto-advance" {
  write_state CHORE-002 chore low
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-002 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "auto-advance" ]
  [ "$(get_field "$output" reason)" = "chore|bug chain with complexity <= medium" ]
}

@test "warnings only, chore chain, complexity medium → auto-advance" {
  write_state CHORE-003 chore medium
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-003 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "auto-advance" ]
}

@test "warnings only, chore chain, complexity high → prompt-user" {
  write_state CHORE-004 chore high
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-004 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "prompt-user" ]
}

@test "warnings only, bug chain, complexity low → auto-advance" {
  write_state BUG-002 bug low
  cd "$TMPDIR_TEST"
  run bash "$FD" BUG-002 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "auto-advance" ]
}

@test "warnings only, bug chain, complexity medium → auto-advance" {
  write_state BUG-003 bug medium
  cd "$TMPDIR_TEST"
  run bash "$FD" BUG-003 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "auto-advance" ]
}

@test "warnings only, bug chain, complexity high → prompt-user" {
  write_state BUG-004 bug high
  cd "$TMPDIR_TEST"
  run bash "$FD" BUG-004 1 '{"errors":0,"warnings":1,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "prompt-user" ]
}

@test "info only, feature chain → prompt-user" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":0,"warnings":0,"info":3}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "prompt-user" ]
}

@test "info only, chore chain, complexity low → auto-advance" {
  seed_state CHORE-001
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-001 1 '{"errors":0,"warnings":0,"info":2}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" action)" = "auto-advance" ]
}

# ---- type / complexity echo into output -------------------------------------

@test "output echoes type field from state file (feature)" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "feature" ]
}

@test "output echoes complexity field from state file (high)" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" complexity)" = "high" ]
}

@test "output echoes type=chore, complexity=low for CHORE-001 fixture" {
  seed_state CHORE-001
  cd "$TMPDIR_TEST"
  run bash "$FD" CHORE-001 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "chore" ]
  [ "$(get_field "$output" complexity)" = "low" ]
}

@test "output echoes type=bug, complexity=medium for BUG-001 fixture" {
  seed_state BUG-001
  cd "$TMPDIR_TEST"
  run bash "$FD" BUG-001 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" type)" = "bug" ]
  [ "$(get_field "$output" complexity)" = "medium" ]
}

# ---- error cases ------------------------------------------------------------

@test "missing state file → exit 1" {
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-999 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 1 ]
}

@test "missing <ID> arg → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$FD"
  [ "$status" -eq 2 ]
}

@test "missing <counts-json> arg → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1
  [ "$status" -eq 2 ]
}

@test "malformed counts JSON → exit 1" {
  seed_state FEAT-028
  cd "$TMPDIR_TEST"
  run bash "$FD" FEAT-028 1 'not-json'
  [ "$status" -eq 1 ]
}

@test "malformed <ID> (lowercase feat-028) → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$FD" feat-028 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 2 ]
}

@test "state file missing type field → exit 1" {
  cd "$TMPDIR_TEST"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/FEAT-100.json" <<'EOF'
{"id":"FEAT-100","complexity":"low"}
EOF
  run bash "$FD" FEAT-100 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 1 ]
}

@test "state file missing complexity field → exit 1" {
  cd "$TMPDIR_TEST"
  cat > "${TMPDIR_TEST}/.sdlc/workflows/FEAT-101.json" <<'EOF'
{"id":"FEAT-101","type":"feature"}
EOF
  run bash "$FD" FEAT-101 1 '{"errors":0,"warnings":0,"info":0}'
  [ "$status" -eq 1 ]
}
