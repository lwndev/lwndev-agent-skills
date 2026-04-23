#!/usr/bin/env bats
# Bats fixture for extract-references.sh (FEAT-026 / FR-2).
#
# Covers:
#   * Four reference categories (filePaths, identifiers, crossRefs, ghRefs).
#   * Shape invariant: all four array keys always present.
#   * De-duplication with first-occurrence ordering.
#   * Origin-URL normalization to #<N>; non-origin URLs kept verbatim.
#   * Identifier false-positive filtering (true/false/null/single-letter/keywords).
#   * Error exits (2 on missing arg; 1 on unreadable file).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/extract-references.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  TMPDIR_TEST="$(mktemp -d)"

  # We run the sample fixture inside a disposable git repo whose `origin` is
  # set to lwndev/lwndev-marketplace so the URL-normalization path is exercised.
  REPO_DIR="${TMPDIR_TEST}/repo"
  mkdir -p "$REPO_DIR"
  (
    cd "$REPO_DIR"
    git init -q
    git remote add origin https://github.com/lwndev/lwndev-marketplace.git
  )
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Run the script with the cwd inside the fake repo so origin detection works.
run_in_repo() {
  (cd "$REPO_DIR" && bash "$SCRIPT" "$@")
}

@test "missing arg -> exit 2 with usage to stderr" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'[error] usage: extract-references.sh <doc-path>'* ]]
}

@test "non-existent file -> exit 1 with error to stderr" {
  run bash "$SCRIPT" "${TMPDIR_TEST}/does-not-exist.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'[error] extract-references: cannot read file'* ]]
}

@test "empty doc -> exit 0 with all four arrays empty" {
  : > "${TMPDIR_TEST}/empty.md"
  run bash "$SCRIPT" "${TMPDIR_TEST}/empty.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"filePaths":[]'* ]]
  [[ "$output" == *'"identifiers":[]'* ]]
  [[ "$output" == *'"crossRefs":[]'* ]]
  [[ "$output" == *'"ghRefs":[]'* ]]
}

@test "shape invariant: all four keys always present even with some populated" {
  cat > "${TMPDIR_TEST}/only-cross.md" <<'EOF'
Only references: FEAT-020.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/only-cross.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"filePaths":[]'* ]]
  [[ "$output" == *'"identifiers":[]'* ]]
  [[ "$output" == *'"crossRefs":["FEAT-020"]'* ]]
  [[ "$output" == *'"ghRefs":[]'* ]]
}

@test "filePaths: backticked path captured" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
See `scripts/foo.sh` for details.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"filePaths":["scripts/foo.sh"]'* ]]
}

@test "filePaths: bare path captured" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Also plugins/lwndev-sdlc/SKILL.md mentioned bare.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"filePaths":["plugins/lwndev-sdlc/SKILL.md"]'* ]]
}

@test "filePaths: all supported extensions match" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Files: a.md, b.ts, c.tsx, d.js, e.jsx, f.json, g.sh, h.bats, i.yaml, j.yml, k.toml.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  for ext in a.md b.ts c.tsx d.js e.jsx f.json g.sh h.bats i.yaml j.yml k.toml; do
    [[ "$output" == *"\"${ext}\""* ]]
  done
}

@test "identifiers: backticked programming tokens captured" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Calls `getSourcePlugins` and `MyClass` and `my_func_1`.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'getSourcePlugins'* ]]
  [[ "$output" == *'MyClass'* ]]
  [[ "$output" == *'my_func_1'* ]]
}

@test "identifiers: false positives filtered (true/false/null/single/keywords)" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Skip: `true`, `false`, `null`, `x`, `const`, `return`, `function`, `class`.
Keep: `realIdent`.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'realIdent'* ]]
  # Each filtered token must not appear inside the identifiers array slot.
  # Use a coarse check: the identifiers array should contain only `realIdent`.
  [[ "$output" == *'"identifiers":["realIdent"]'* ]]
}

@test "crossRefs: FEAT-/CHORE-/BUG- all captured" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Relates to FEAT-020, CHORE-003, and BUG-001.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"crossRefs":["FEAT-020","CHORE-003","BUG-001"]'* ]]
}

@test "ghRefs: bare #N captured" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Issue #184 is open.
EOF
  run_in_repo "${TMPDIR_TEST}/a.md"
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Issue #184 is open.
EOF
  result=$(cd "$REPO_DIR" && bash "$SCRIPT" "${TMPDIR_TEST}/a.md")
  [[ "$result" == *'"ghRefs":["#184"]'* ]]
}

@test "ghRefs: origin URL normalized to #N" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
See https://github.com/lwndev/lwndev-marketplace/issues/184 for details.
EOF
  result=$(cd "$REPO_DIR" && bash "$SCRIPT" "${TMPDIR_TEST}/a.md")
  [[ "$result" == *'"ghRefs":["#184"]'* ]]
}

@test "ghRefs: non-origin URL kept as full URL" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
External: https://github.com/other-owner/other-repo/pull/5.
EOF
  result=$(cd "$REPO_DIR" && bash "$SCRIPT" "${TMPDIR_TEST}/a.md")
  [[ "$result" == *'"https://github.com/other-owner/other-repo/pull/5"'* ]]
}

@test "ghRefs: origin URL and bare #N de-duplicate to a single #N" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
Issue #184 and also https://github.com/lwndev/lwndev-marketplace/issues/184 again.
EOF
  result=$(cd "$REPO_DIR" && bash "$SCRIPT" "${TMPDIR_TEST}/a.md")
  # `#184` must appear exactly once.
  count=$(printf '%s' "$result" | grep -o '#184' | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "de-duplication: repeated path/identifier/crossRef appears once" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
See `scripts/foo.sh` and again `scripts/foo.sh`.
Ident `getSourcePlugins` then `getSourcePlugins`.
Cross FEAT-020 and again FEAT-020.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  # Each token appears exactly once in stdout.
  for token in "scripts/foo.sh" "getSourcePlugins" "FEAT-020"; do
    count=$(printf '%s' "$output" | grep -o "$token" | wc -l | tr -d ' ')
    [ "$count" = "1" ]
  done
}

@test "first-occurrence order preserved in crossRefs" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
BUG-001 comes first, then CHORE-003, then FEAT-020.
Later mentions: FEAT-020, BUG-001.
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"crossRefs":["BUG-001","CHORE-003","FEAT-020"]'* ]]
}

@test "combined fixture: all four categories populated" {
  result=$(cd "$REPO_DIR" && bash "$SCRIPT" "${FIXTURES}/sample-req-doc.md")
  # File paths (backticked + bare)
  [[ "$result" == *'scripts/foo.sh'* ]]
  [[ "$result" == *'plugins/lwndev-sdlc/SKILL.md'* ]]
  # Identifier
  [[ "$result" == *'getSourcePlugins'* ]]
  [[ "$result" == *'MyClass'* ]]
  # Cross-refs
  [[ "$result" == *'FEAT-020'* ]]
  [[ "$result" == *'CHORE-003'* ]]
  [[ "$result" == *'BUG-001'* ]]
  # GH refs
  [[ "$result" == *'#184'* ]]
  [[ "$result" == *'https://github.com/other-owner/other-repo/pull/5'* ]]
}

@test "markdown heading hash is not captured as #N" {
  cat > "${TMPDIR_TEST}/a.md" <<'EOF'
# Title with numbers 123
## 456 section
EOF
  run bash "$SCRIPT" "${TMPDIR_TEST}/a.md"
  [ "$status" -eq 0 ]
  # ghRefs should be empty — the `#` here is a heading marker, separated from
  # the digits by whitespace.
  [[ "$output" == *'"ghRefs":[]'* ]]
}
