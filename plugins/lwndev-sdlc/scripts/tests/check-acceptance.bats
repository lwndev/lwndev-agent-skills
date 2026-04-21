#!/usr/bin/env bats
# Bats fixture for check-acceptance.sh (FR-6).
#
# Covers: happy path, already-checked idempotency, fence-awareness,
# criterion-not-found (exit 1), ambiguous-match (exit 2),
# regex-metacharacter literal matching, CRLF tolerance, missing arg (exit 3).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CHECK="${SCRIPT_DIR}/check-acceptance.sh"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/doc.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: flips a matching '- [ ]' line and prints 'checked'" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

- [ ] AC-1: first criterion
- [ ] AC-2: second criterion
EOF
  run bash "$CHECK" "$DOC" "AC-1"
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  grep -q '^- \[x\] AC-1: first criterion$' "$DOC"
  # Non-matching line remains unchecked.
  grep -q '^- \[ \] AC-2: second criterion$' "$DOC"
}

@test "already-checked idempotency: prints 'already checked' and exit 0" {
  cat > "$DOC" <<'EOF'
- [x] AC-1: already done
EOF
  run bash "$CHECK" "$DOC" "AC-1"
  [ "$status" -eq 0 ]
  [ "$output" = "already checked" ]
}

@test "fence-awareness: '- [ ]' inside a fenced block is NOT flipped" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

Some example:

```
- [ ] AC-42: inside a fenced code block
```

- [ ] AC-7: real criterion
EOF
  # AC-42 lives only inside a fenced block → no match outside fences.
  run bash "$CHECK" "$DOC" "AC-42"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: criterion not found"* ]]
  # And the fenced line is unchanged on disk.
  grep -q '^- \[ \] AC-42: inside a fenced code block$' "$DOC"
  # Meanwhile, a real match outside fences works.
  run bash "$CHECK" "$DOC" "AC-7"
  [ "$status" -eq 0 ]
  grep -q '^- \[x\] AC-7: real criterion$' "$DOC"
}

@test "criterion not found: exit 1 with error message" {
  cat > "$DOC" <<'EOF'
- [ ] AC-1: foo
EOF
  run bash "$CHECK" "$DOC" "AC-999"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: criterion not found"* ]]
}

@test "ambiguous match: two '- [ ]' lines match → exit 2" {
  cat > "$DOC" <<'EOF'
- [ ] shared-substring one
- [ ] shared-substring two
EOF
  run bash "$CHECK" "$DOC" "shared-substring"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: ambiguous"* ]]
  [[ "$output" == *"2 lines match"* ]]
  # File is unchanged on ambiguous exit.
  grep -q '^- \[ \] shared-substring one$' "$DOC"
  grep -q '^- \[ \] shared-substring two$' "$DOC"
}

@test "regex-metacharacter literal matching: 'AC-1.2' does NOT match 'AC-142'" {
  cat > "$DOC" <<'EOF'
- [ ] AC-142: the one-forty-second criterion
EOF
  run bash "$CHECK" "$DOC" "AC-1.2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: criterion not found"* ]]
  # File unchanged — the dot was not interpreted as "any char".
  grep -q '^- \[ \] AC-142: the one-forty-second criterion$' "$DOC"
}

@test "CRLF tolerance: file with Windows line endings is handled" {
  # Write CRLF file by hand.
  printf '## Acceptance Criteria\r\n\r\n- [ ] AC-1: crlf line\r\n' > "$DOC"
  run bash "$CHECK" "$DOC" "AC-1"
  [ "$status" -eq 0 ]
  [ "$output" = "checked" ]
  # The checkbox on disk is now flipped (read via grep).
  grep -q -- "- \[x\] AC-1: crlf line" "$DOC"
}

@test "missing arg: exit 3 (usage)" {
  run bash "$CHECK"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
}

@test "missing matcher (one arg only): exit 3" {
  cat > "$DOC" <<'EOF'
- [ ] AC-1
EOF
  run bash "$CHECK" "$DOC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"error:"* ]]
}
