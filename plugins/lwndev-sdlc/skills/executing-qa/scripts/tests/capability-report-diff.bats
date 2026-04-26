#!/usr/bin/env bats
# Bats fixture for capability-report-diff.sh (FEAT-030 / FR-3).
#
# Covers the documented contract:
#   * Happy path — no drift (identical capability fields).
#   * Drift in any single comparable field (framework / language /
#     packageManager / testCommand / mode).
#   * Drift in multiple fields.
#   * Both files identical (notes/timestamp differ but ignored).
#   * Exit 2 — missing args, missing files, malformed JSON, plan with no
#     capability block.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/capability-report-diff.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper — write a plan file embedding a capability JSON block.
write_plan() {
  local plan_path="$1"; local cap_json="$2"
  cat > "$plan_path" <<EOF
# Plan FEAT-X

Some narrative paragraph.

## Capability Report

\`\`\`json
${cap_json}
\`\`\`

## Other section
EOF
}

@test "happy path — identical capability fields → drift=false, fields=[]" {
  cap='{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework"}'
  write_plan plan.md "$cap"
  cat > fresh.json <<EOF
{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework","notes":[]}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift == false and (.fields | length == 0)'
}

@test "drift in framework only → drift=true, single field" {
  write_plan plan.md '{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework"}'
  cat > fresh.json <<EOF
{"framework":"jest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework","notes":[]}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift == true and (.fields | length == 1) and .fields[0].field == "framework" and .fields[0].planValue == "vitest" and .fields[0].freshValue == "jest"'
}

@test "drift in mode only → drift=true, single field" {
  write_plan plan.md '{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework"}'
  cat > fresh.json <<EOF
{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"exploratory-only","notes":[]}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift == true and (.fields | length == 1) and .fields[0].field == "mode"'
}

@test "drift in multiple fields → drift=true, fields list mirrors all changes" {
  write_plan plan.md '{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework"}'
  cat > fresh.json <<EOF
{"framework":"jest","language":"javascript","packageManager":"yarn","testCommand":"yarn jest","mode":"test-framework","notes":[]}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift == true and (.fields | length == 4)'
}

@test "notes / timestamp differences are ignored (not comparable fields)" {
  write_plan plan.md '{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework","notes":["plan note"],"timestamp":"2025-01-01T00:00:00Z"}'
  cat > fresh.json <<EOF
{"framework":"vitest","language":"typescript","packageManager":"npm","testCommand":"npm test","mode":"test-framework","notes":["fresh note"],"timestamp":"2026-04-25T00:00:00Z"}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.drift == false'
}

# --- Exit 2 — bad args ------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "one arg → exit 2" {
  run bash "$SCRIPT" plan.md
  [ "$status" -eq 2 ]
}

@test "missing plan file → exit 2" {
  cat > fresh.json <<EOF
{"framework":"vitest","testCommand":"npm test","mode":"test-framework"}
EOF
  run bash "$SCRIPT" no-such-plan.md fresh.json
  [ "$status" -eq 2 ]
  [[ "$output" == *"plan file not found"* ]]
}

@test "missing fresh JSON → exit 2" {
  write_plan plan.md '{"framework":"vitest","testCommand":"npm test","mode":"test-framework"}'
  run bash "$SCRIPT" plan.md no-such-fresh.json
  [ "$status" -eq 2 ]
  [[ "$output" == *"fresh capability JSON not found"* ]]
}

@test "malformed fresh JSON → exit 2" {
  write_plan plan.md '{"framework":"vitest","testCommand":"npm test","mode":"test-framework"}'
  printf 'not json' > fresh.json
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "plan without a capability JSON block → exit 2" {
  cat > plan.md <<EOF
# Plan
No capability block here.
EOF
  cat > fresh.json <<EOF
{"framework":"vitest","testCommand":"npm test","mode":"test-framework"}
EOF
  run bash "$SCRIPT" plan.md fresh.json
  [ "$status" -eq 2 ]
  [[ "$output" == *"no capability report"* ]]
}
