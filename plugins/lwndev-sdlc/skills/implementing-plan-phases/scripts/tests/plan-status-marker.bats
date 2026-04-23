#!/usr/bin/env bats
# Bats fixture for plan-status-marker.sh (FEAT-027 / FR-2).
#
# Covers: canonical state transitions (Pending / in-progress / complete),
# idempotent no-op, per-phase scoping, fence-awareness, and every documented
# error exit.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/plan-status-marker.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/plan.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "transition to in-progress: writes '**Status:** 🔄 In Progress'" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 1 in-progress
  [ "$status" -eq 0 ]
  [ "$output" = "transitioned" ]
  grep -q $'^\\*\\*Status:\\*\\* \xf0\x9f\x94\x84 In Progress$' "$DOC"
}

@test "transition to complete: writes '**Status:** ✅ Complete'" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** 🔄 In Progress
EOF
  run bash "$SCRIPT" "$DOC" 1 complete
  [ "$status" -eq 0 ]
  [ "$output" = "transitioned" ]
  grep -q $'^\\*\\*Status:\\*\\* \xe2\x9c\x85 Complete$' "$DOC"
}

@test "transition to Pending: writes '**Status:** Pending'" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
EOF
  run bash "$SCRIPT" "$DOC" 1 Pending
  [ "$status" -eq 0 ]
  [ "$output" = "transitioned" ]
  grep -q '^\*\*Status:\*\* Pending$' "$DOC"
}

@test "idempotent: already-correct state emits 'already set', file unchanged" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** ✅ Complete
EOF
  before=$(md5 -q "$DOC" 2>/dev/null || md5sum "$DOC" | awk '{print $1}')
  run bash "$SCRIPT" "$DOC" 1 complete
  [ "$status" -eq 0 ]
  [ "$output" = "already set" ]
  after=$(md5 -q "$DOC" 2>/dev/null || md5sum "$DOC" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "per-phase scoping: only the targeted phase's status is modified" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending

### Phase 2: B
**Status:** Pending

### Phase 3: C
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 2 in-progress
  [ "$status" -eq 0 ]
  [ "$output" = "transitioned" ]
  # Phase 1 and 3 stay Pending.
  status_count=$(grep -c '^\*\*Status:\*\* Pending$' "$DOC")
  [ "$status_count" -eq 2 ]
  # Phase 2 is 🔄 In Progress.
  grep -q $'^\\*\\*Status:\\*\\* \xf0\x9f\x94\x84 In Progress$' "$DOC"
}

@test "fence-awareness: '**Status:**' inside fenced block is not modified" {
  cat > "$DOC" <<'EOF'
### Phase 1: A

Example:

```
**Status:** ✅ Complete
```

**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 1 in-progress
  [ "$status" -eq 0 ]
  [ "$output" = "transitioned" ]
  # Fenced line stays Complete.
  grep -q $'^\\*\\*Status:\\*\\* \xe2\x9c\x85 Complete$' "$DOC"
  # Real status (outside fence) flipped to In Progress.
  grep -q $'^\\*\\*Status:\\*\\* \xf0\x9f\x94\x84 In Progress$' "$DOC"
}

@test "missing all args: exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "missing last arg: exit 2" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "non-positive phase number: exit 2" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 0 in-progress
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "non-integer phase number: exit 2" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" abc in-progress
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "unknown state token: exit 2" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 1 done
  [ "$status" -eq 2 ]
  [[ "$output" == *"Pending"* ]] || [[ "$output" == *"state"* ]]
}

@test "non-existent plan file: exit 1" {
  run bash "$SCRIPT" "/nonexistent/path/plan.md" 1 in-progress
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"unreadable"* ]]
}

@test "phase number not in plan: exit 1" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 7 in-progress
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "phase block missing Status line: exit 1" {
  cat > "$DOC" <<'EOF'
### Phase 1: A
No status line.
### Phase 2: B
**Status:** Pending
EOF
  run bash "$SCRIPT" "$DOC" 1 in-progress
  [ "$status" -eq 1 ]
  [[ "$output" == *"no"* ]]
  [[ "$output" == *"Status"* ]]
}
