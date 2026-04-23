#!/usr/bin/env bats
# Bats fixture for cross-ref-check.sh (FEAT-026 / FR-4).
#
# Covers:
#   * Happy paths: ok / ambiguous / missing classifications.
#   * Shape invariant: all three array keys always present.
#   * Doc with no cross-refs -> all arrays empty.
#   * Entry shape: {category: "crossRefs", ref, detail}.
#   * Error exits (2 on missing arg; 1 on unreadable file).
#
# Each test runs inside a hermetic tmpdir that is made the CWD so the
# `requirements/{features,chores,bugs}/` globs resolve against the fixture
# layout we build, not the real repo.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/cross-ref-check.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  mkdir -p requirements/features requirements/chores requirements/bugs
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "missing arg -> exit 2 with usage to stderr" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'[error] usage: cross-ref-check.sh <doc-path>'* ]]
}

@test "non-existent file -> exit 1 with error to stderr" {
  run bash "$SCRIPT" "${TMPDIR_TEST}/does-not-exist.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'[error] cross-ref-check: cannot read file'* ]]
}

@test "doc with no cross-refs -> all three arrays empty" {
  cat > doc.md <<'EOF'
A requirement document that mentions no cross-references at all.
Just text, `identifiers`, and `scripts/foo.sh`.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[]'* ]]
  [[ "$output" == *'"ambiguous":[]'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "shape invariant: ok/ambiguous/missing keys always present" {
  cat > doc.md <<'EOF'
Only FEAT-999 which does not exist.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":'* ]]
  [[ "$output" == *'"ambiguous":'* ]]
  [[ "$output" == *'"missing":'* ]]
}

@test "FEAT-020 with one matching file -> ok" {
  : > requirements/features/FEAT-020-plugin-shared.md
  cat > doc.md <<'EOF'
Relates to FEAT-020.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[{"category":"crossRefs","ref":"FEAT-020"'* ]]
  [[ "$output" == *'requirements/features/FEAT-020-plugin-shared.md'* ]]
  [[ "$output" == *'"ambiguous":[]'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "CHORE-003 with two matching files -> ambiguous" {
  : > requirements/chores/CHORE-003-first.md
  : > requirements/chores/CHORE-003-second.md
  cat > doc.md <<'EOF'
See CHORE-003.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ambiguous":[{"category":"crossRefs","ref":"CHORE-003"'* ]]
  [[ "$output" == *'multiple matches'* ]]
  [[ "$output" == *'"ok":[]'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "BUG-999 with no matching file -> missing" {
  cat > doc.md <<'EOF'
Tracks BUG-999.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"missing":[{"category":"crossRefs","ref":"BUG-999"'* ]]
  [[ "$output" == *'no file matching requirements/bugs/BUG-999-*.md'* ]]
  [[ "$output" == *'"ok":[]'* ]]
  [[ "$output" == *'"ambiguous":[]'* ]]
}

@test "mixed refs -> classified into the three buckets" {
  : > requirements/features/FEAT-020-foo.md
  : > requirements/chores/CHORE-003-a.md
  : > requirements/chores/CHORE-003-b.md
  cat > doc.md <<'EOF'
Refs: FEAT-020, CHORE-003, BUG-777.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ref":"FEAT-020"'* ]]
  [[ "$output" == *'"ref":"CHORE-003"'* ]]
  [[ "$output" == *'"ref":"BUG-777"'* ]]
  # FEAT-020 under ok; CHORE-003 under ambiguous; BUG-777 under missing.
  # We can verify by scanning the ok/ambiguous/missing slots with jq.
  ok_count=$(printf '%s' "$output" | jq -r '.ok | length')
  amb_count=$(printf '%s' "$output" | jq -r '.ambiguous | length')
  miss_count=$(printf '%s' "$output" | jq -r '.missing | length')
  [ "$ok_count" = "1" ]
  [ "$amb_count" = "1" ]
  [ "$miss_count" = "1" ]
}

@test "entry shape: category=crossRefs, ref, detail" {
  : > requirements/features/FEAT-020-foo.md
  cat > doc.md <<'EOF'
FEAT-020 here.
EOF
  run bash "$SCRIPT" doc.md
  [ "$status" -eq 0 ]
  category=$(printf '%s' "$output" | jq -r '.ok[0].category')
  ref=$(printf '%s' "$output" | jq -r '.ok[0].ref')
  detail=$(printf '%s' "$output" | jq -r '.ok[0].detail')
  [ "$category" = "crossRefs" ]
  [ "$ref" = "FEAT-020" ]
  [[ "$detail" == *"FEAT-020-foo.md"* ]]
}
