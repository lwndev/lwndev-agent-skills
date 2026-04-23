#!/usr/bin/env bats
# Bats fixture for verify-all-phases-complete.sh (FEAT-027 / FR-6).
#
# Covers: all-complete success, single non-complete phase failure, mixed-status
# failure, fence-awareness, and every documented error exit.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/verify-all-phases-complete.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/plan.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "all phases ✅ Complete → 'all phases complete', exit 0" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** ✅ Complete
### Phase 3: C
**Status:** ✅ Complete
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  [ "$output" = "all phases complete" ]
}

@test "one Pending phase → JSON incomplete list, exit 1" {
  run bash "$SCRIPT" "${FIXTURES}/minimal-plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"incomplete"'* ]]
  [[ "$output" == *'"phase": 2'* ]] || [[ "$output" == *'"phase":2'* ]]
  [[ "$output" == *'"status": "Pending"'* ]] || [[ "$output" == *'"status":"Pending"'* ]]
}

@test "one 🔄 In Progress phase → incomplete list with in-progress status" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** 🔄 In Progress
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"phase": 2'* ]] || [[ "$output" == *'"phase":2'* ]]
  [[ "$output" == *'"status": "in-progress"'* ]] || [[ "$output" == *'"status":"in-progress"'* ]]
}

@test "mixed phases: Complete + Pending + In Progress → incomplete lists both non-complete" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** Pending
### Phase 3: C
**Status:** 🔄 In Progress
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Pending"* ]]
  [[ "$output" == *"in-progress"* ]]
  # Phase 1 (complete) should not appear.
  phase1_count=$(printf '%s' "$output" | grep -c '"phase": 1' || true)
  phase1_alt=$(printf '%s' "$output" | grep -c '"phase":1' || true)
  [ "$((phase1_count + phase1_alt))" -eq 0 ]
}

@test "fence-awareness: fenced '**Status:**' lines not counted" {
  # Phase 1 of fenced-status-plan.md has a real '**Status:** Pending' outside
  # fences plus a fenced Complete line. Expected: incomplete list contains
  # Phase 1 Pending.
  run bash "$SCRIPT" "${FIXTURES}/fenced-status-plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Pending"* ]]
}

@test "missing arg: exit 2 (usage)" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "non-existent file: exit 1" {
  run bash "$SCRIPT" "/nonexistent/path/plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"unreadable"* ]]
}

@test "no phase blocks: stderr '[error] no phase blocks found', exit 1" {
  cat > "$DOC" <<'EOF'
# Plan with no phase headings.
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] no phase blocks found"* ]]
}
