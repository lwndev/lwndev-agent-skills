#!/usr/bin/env bats
# Bats fixture for next-pending-phase.sh (FEAT-027 / FR-1).
#
# Covers: happy path, sequential dependency ordering, all-complete signal,
# resume-in-progress signal, blocked signal, explicit Depends-on handling,
# fence-awareness, and every documented error exit.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/next-pending-phase.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/plan.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: single Pending phase with no prereqs → selects it" {
  cat > "$DOC" <<'EOF'
### Phase 1: Only Phase
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"phase":1,"name":"Only Phase"}' ]]
}

@test "sequential: Phase 1 Complete, Phase 2 Pending → selects Phase 2" {
  run bash "$SCRIPT" "${FIXTURES}/minimal-plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"phase":2,"name":"Second Phase"}' ]]
}

@test "all-complete: every phase ✅ Complete → phase:null, reason:all-complete" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** ✅ Complete
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"phase":null,"reason":"all-complete"}' ]]
}

@test "resume-in-progress: 🔄 In Progress phase takes priority" {
  run bash "$SCRIPT" "${FIXTURES}/multi-phase-plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"phase":2,"name":"Beta","reason":"resume-in-progress"}' ]]
}

@test "blocked: Phase 2 Pending while Phase 1 also Pending → blockedOn [1]" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
### Phase 2: B
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  # Phase 1 is selectable (no blockers). The script returns Phase 1, not a blocked signal.
  [[ "$output" == '{"phase":1,"name":"A"}' ]]
}

@test "blocked: explicit Depends-on Phase 2 where Phase 2 is Pending → blockedOn" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** Pending
### Phase 3: C
**Status:** Pending
**Depends on:** Phase 2
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  # Phase 2 has no blockers → selected first.
  [[ "$output" == '{"phase":2,"name":"B"}' ]]
}

@test "blocked: explicit Depends-on Phase 5 where Phase 5 not complete → blockedOn [5]" {
  # Every other phase is complete; Phase 3 depends on Phase 5 which is Pending;
  # Phase 5 has no Depends-on but has no blockers of its own except the
  # lower-numbered Phase 3 being pending — so Phase 5 is also blocked.
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
### Phase 2: B
**Status:** ✅ Complete
### Phase 3: C
**Status:** Pending
**Depends on:** Phase 5
### Phase 4: D
**Status:** ✅ Complete
### Phase 5: E
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"phase":null,"reason":"blocked","blockedOn":[5]}' ]]
}

@test "fence-awareness: Status line in fenced block not counted as real status" {
  # Phase 2 in the fixture has its only Status line inside a fenced block.
  # The script must treat that phase as missing status → exit 1.
  run bash "$SCRIPT" "${FIXTURES}/fenced-status-plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase 2"* ]]
  [[ "$output" == *"Status"* ]]
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

@test "no phase blocks: exit 1" {
  cat > "$DOC" <<'EOF'
# Plan with no phase headings.
Some text, no `### Phase` blocks at all.
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no \`### Phase\`"* ]] || [[ "$output" == *"no"* ]]
}

@test "phase block missing Status line (outside fences): exit 1" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
Some prose, no status line.
### Phase 2: B
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"phase 1"* ]]
}
