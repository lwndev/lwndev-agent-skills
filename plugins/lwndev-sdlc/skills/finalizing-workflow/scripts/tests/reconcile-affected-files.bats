#!/usr/bin/env bats
# Bats fixture for reconcile-affected-files.sh (FR-6).
# Stubs `gh` via PATH shadowing.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  RECONCILE="${SCRIPT_DIR}/reconcile-affected-files.sh"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/doc.md"
  STUB_DIR="${TMPDIR_TEST}/stubs"
  mkdir -p "$STUB_DIR"
  export PATH="${STUB_DIR}:${PATH}"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: write a gh stub that emits the given paths (newline-separated)
# when invoked as `gh pr view <N> --json files --jq '.files[].path'`.
write_gh_stub() {
  local paths_multiline="$1"
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  printf '%s' '${paths_multiline}'
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

write_gh_fail_stub() {
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: connection refused" >&2
exit 1
EOF
  chmod +x "${STUB_DIR}/gh"
}

write_doc_lf() {
  printf '%s\n' "$@" > "$DOC"
}

is_all_crlf() {
  local path="$1"
  local lf crlf
  lf="$(LC_ALL=C tr -cd '\n' < "$path" | wc -c | tr -d ' ')"
  crlf="$(LC_ALL=C grep -ac $'\r$' "$path" 2>/dev/null || echo 0)"
  [ "$lf" -eq "$crlf" ]
}

@test "no ## Affected Files section → exit 0, stdout '0 0', doc unchanged" {
  write_gh_stub $'a.txt\nb.txt\n'
  write_doc_lf "# Feature" "" "Body with no affected files section."
  before_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "0 0" ]
  after_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  [ "$before_checksum" = "$after_checksum" ]
}

@test "all files match → exit 0, stdout '0 0', doc unchanged" {
  write_gh_stub $'a.txt\nb.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`" \
    "- \`b.txt\`" \
    "" \
    "## Other"
  before_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "0 0" ]
  after_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  [ "$before_checksum" = "$after_checksum" ]
}

@test "2 files in PR missing from doc → exit 0, stdout '2 0', 2 bullets appended" {
  write_gh_stub $'a.txt\nb.txt\nc.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`" \
    "" \
    "## Other"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "2 0" ]
  grep -q '^- `a\.txt`$' "$DOC"
  grep -q '^- `b\.txt`$' "$DOC"
  grep -q '^- `c\.txt`$' "$DOC"
  # Other section tail preserved.
  grep -q '^## Other$' "$DOC"
}

@test "1 file in doc missing from PR → exit 0, stdout '0 1', annotation appended" {
  write_gh_stub $'a.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`" \
    "- \`old.txt\`"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "0 1" ]
  grep -q '^- `old\.txt` (planned but not modified)$' "$DOC"
  grep -q '^- `a\.txt`$' "$DOC"
}

@test "mixed: 1 append + 2 annotate → exit 0, stdout '1 2'" {
  write_gh_stub $'a.txt\nnew.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`" \
    "- \`gone1.txt\`" \
    "- \`gone2.txt\`" \
    "" \
    "## Other"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "1 2" ]
  grep -q '^- `gone1\.txt` (planned but not modified)$' "$DOC"
  grep -q '^- `gone2\.txt` (planned but not modified)$' "$DOC"
  grep -q '^- `new\.txt`$' "$DOC"
  grep -q '^- `a\.txt`$' "$DOC"
}

@test "annotation already present → idempotent → exit 0, stdout '0 0', doc unchanged" {
  write_gh_stub $'a.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`" \
    "- \`old.txt\` (planned but not modified)"
  before_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "0 0" ]
  after_checksum="$(LC_ALL=C md5 -q "$DOC" 2>/dev/null || LC_ALL=C md5sum "$DOC" | awk '{print $1}')"
  [ "$before_checksum" = "$after_checksum" ]
}

@test "fenced example '- \`path\`' bullet is NOT scanned → not annotated, not compared" {
  # PR has only a.txt. Doc has a real bullet for a.txt and a FENCED example
  # bullet for fake.txt. The fenced bullet must be ignored entirely:
  # - Not counted as a doc path (so no annotation).
  # - Fenced content must remain byte-for-byte unchanged.
  write_gh_stub $'a.txt\n'
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "Example of a bullet format:" \
    "" \
    '```' \
    "- \`fake.txt\`" \
    "- \`example.txt\` (planned but not modified)" \
    '```' \
    "" \
    "- \`a.txt\`"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "0 0" ]
  # Fenced example unchanged: fake.txt line still exactly `- `fake.txt``
  # (no annotation).
  grep -q '^- `fake\.txt`$' "$DOC"
  ! grep -q '^- `fake\.txt` (planned but not modified)$' "$DOC"
  # example.txt annotation preserved (it was inside the fence).
  grep -q '^- `example\.txt` (planned but not modified)$' "$DOC"
  # No new bullet appended.
  real_count="$(LC_ALL=C awk '
    BEGIN { in_fence = 0; count = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      stripped = line; sub(/^[ \t]+/, "", stripped)
      if (stripped ~ /^(```|~~~)/) { in_fence = !in_fence; next }
      if (in_fence) next
      if (line ~ /^- `[^`]+`/) count++
    }
    END { print count }
  ' "$DOC")"
  [ "$real_count" -eq 1 ]
}

@test "CRLF doc → line endings preserved through all mutations" {
  write_gh_stub $'a.txt\nnewfile.txt\n'
  printf '# Feature\r\n\r\n## Affected Files\r\n\r\n- `a.txt`\r\n- `gone.txt`\r\n\r\n## Other\r\n' > "$DOC"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 0 ]
  [ "$output" = "1 1" ]
  # All line-endings CRLF.
  run is_all_crlf "$DOC"
  [ "$status" -eq 0 ]
  # Annotated line present with CR terminator.
  LC_ALL=C grep -qF -e $'- `gone.txt` (planned but not modified)\r' "$DOC"
  # New bullet present with CR terminator.
  LC_ALL=C grep -qF -e $'- `newfile.txt`\r' "$DOC"
}

@test "gh stub returns non-zero → exit 1, stderr '[warn] reconcile-affected-files:', no stdout" {
  write_gh_fail_stub
  write_doc_lf \
    "# Feature" \
    "" \
    "## Affected Files" \
    "" \
    "- \`a.txt\`"
  run bash "$RECONCILE" "$DOC" 42
  [ "$status" -eq 1 ]
  # The combined output should contain the [warn] line. `run` merges stdout
  # and stderr by default, so verify via the merged output and confirm there
  # was no "clean" stdout token emitted.
  [[ "$output" == *'[warn] reconcile-affected-files:'* ]]
  # Ensure neither an `N M` counter line nor a `0 0` appears (no stdout).
  run bash -c "bash '$RECONCILE' '$DOC' 42 2>/dev/null"
  [ -z "$output" ]
}

@test "missing arg → exit 2" {
  write_gh_stub ""
  write_doc_lf "# Feature"
  run bash "$RECONCILE" "$DOC"
  [ "$status" -eq 2 ]
}

@test "no args → exit 2 with usage" {
  run bash "$RECONCILE"
  [ "$status" -eq 2 ]
  [[ "$output" == *'[error] reconcile-affected-files: usage:'* ]]
}

@test "non-integer prNumber → exit 2" {
  write_gh_stub ""
  write_doc_lf "# Feature"
  run bash "$RECONCILE" "$DOC" NaN
  [ "$status" -eq 2 ]
}

@test "non-existent doc → exit 2" {
  write_gh_stub ""
  run bash "$RECONCILE" "${TMPDIR_TEST}/nope.md" 42
  [ "$status" -eq 2 ]
  [[ "$output" == *'file not found'* ]]
}
