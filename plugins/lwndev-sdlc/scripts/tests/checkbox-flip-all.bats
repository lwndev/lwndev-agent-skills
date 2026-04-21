#!/usr/bin/env bats
# Bats fixture for checkbox-flip-all.sh (FR-7).
#
# Covers: happy path, idempotency (0 lines), section-not-found (exit 1),
# fence-awareness, section-boundary, missing arg (exit 2).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FLIPALL="${SCRIPT_DIR}/checkbox-flip-all.sh"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/doc.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: flips every '- [ ]' in the named section → 'checked N lines'" {
  cat > "$DOC" <<'EOF'
# Title

## Acceptance Criteria

- [ ] AC-1: first
- [ ] AC-2: second
- [ ] AC-3: third

## Other Section

- [ ] AC-99: should not be flipped
EOF
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 0 ]
  [ "$output" = "checked 3 lines" ]
  grep -q '^- \[x\] AC-1: first$' "$DOC"
  grep -q '^- \[x\] AC-2: second$' "$DOC"
  grep -q '^- \[x\] AC-3: third$' "$DOC"
  # The box in the OTHER section is untouched.
  grep -q '^- \[ \] AC-99: should not be flipped$' "$DOC"
}

@test "idempotency: re-running on an all-checked section prints '0 lines'" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

- [x] AC-1: already done
- [x] AC-2: already done
EOF
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 0 ]
  [ "$output" = "checked 0 lines" ]
}

@test "section not found: exit 1 with 'error: section not found'" {
  cat > "$DOC" <<'EOF'
## Some Other Section

- [ ] AC-1: foo
EOF
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: section not found"* ]]
  # Unchanged on exit 1.
  grep -q '^- \[ \] AC-1: foo$' "$DOC"
}

@test "fence-awareness: '- [ ]' inside a fenced block is NOT flipped" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

- [ ] AC-1: real criterion

Example:

```
- [ ] AC-42: inside fence
```

- [ ] AC-2: another real criterion
EOF
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 0 ]
  [ "$output" = "checked 2 lines" ]
  grep -q '^- \[x\] AC-1: real criterion$' "$DOC"
  grep -q '^- \[x\] AC-2: another real criterion$' "$DOC"
  # Inside-fence line must remain '- [ ]' literally.
  grep -q '^- \[ \] AC-42: inside fence$' "$DOC"
}

@test "section boundary: '- [ ]' after the next '## ' heading is not touched" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

- [ ] inside target section

## Next Section

- [ ] outside target section
EOF
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 0 ]
  [ "$output" = "checked 1 lines" ]
  grep -q '^- \[x\] inside target section$' "$DOC"
  grep -q '^- \[ \] outside target section$' "$DOC"
}

@test "CRLF tolerance: section with Windows line endings still flips" {
  printf '## Acceptance Criteria\r\n\r\n- [ ] AC-1\r\n- [ ] AC-2\r\n' > "$DOC"
  run bash "$FLIPALL" "$DOC" "Acceptance Criteria"
  [ "$status" -eq 0 ]
  [ "$output" = "checked 2 lines" ]
  grep -q -- "- \[x\] AC-1" "$DOC"
  grep -q -- "- \[x\] AC-2" "$DOC"
}

@test "missing arg: exit 2 (usage)" {
  run bash "$FLIPALL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"usage"* ]]
}

@test "missing section arg: exit 2" {
  cat > "$DOC" <<'EOF'
## Acceptance Criteria

- [ ] AC-1
EOF
  run bash "$FLIPALL" "$DOC"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}
