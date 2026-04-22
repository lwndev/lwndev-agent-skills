#!/usr/bin/env bats
# Bats fixture for check-idempotent.sh (FR-4).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CHECK="${SCRIPT_DIR}/check-idempotent.sh"
  TMPDIR_TEST="$(mktemp -d)"
  DOC="${TMPDIR_TEST}/doc.md"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Write doc with LF line endings.
write_doc_lf() {
  printf '%s\n' "$@" > "$DOC"
}

@test "all three conditions hold → exit 0, no stdout, no stderr" {
  write_doc_lf \
    "# Feature doc" \
    "" \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "- [x] also done" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Completed:** 2026-04-21" \
    "" \
    "**Pull Request:** [#142](https://github.com/foo/bar/pull/142)"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "acceptance criteria has unticked item → exit 1 with acceptance-criteria-unticked" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "- [ ] still to do" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Pull Request:** [#142](x)"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 1 ]
  [[ "$output" == *'[info] idempotent check failed: acceptance-criteria-unticked'* ]]
}

@test "no Completion section → exit 1 with completion-section-missing" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "" \
    "## Summary" \
    "" \
    "Nothing."
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 1 ]
  [[ "$output" == *'[info] idempotent check failed: completion-section-missing'* ]]
}

@test "PR number mismatch in Completion → exit 1 with pr-line-mismatch" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Pull Request:** [#999](https://github.com/x/y/pull/999)"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 1 ]
  [[ "$output" == *'[info] idempotent check failed: pr-line-mismatch'* ]]
}

@test "PR URL /pull/<prNumber> path matches → exit 0" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Completed\`" \
    "" \
    "**Pull Request:** https://github.com/foo/bar/pull/142"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CRLF-ending doc with all three conditions true → exit 0" {
  # Write each line with explicit CRLF endings.
  printf '## Acceptance Criteria\r\n\r\n- [x] done\r\n\r\n## Completion\r\n\r\n**Status:** `Complete`\r\n\r\n**Pull Request:** [#142](x)\r\n' > "$DOC"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fenced example '## Completion' → not a real section → completion-section-missing" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "" \
    "## Notes" \
    "" \
    "Example block:" \
    "" \
    '```' \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Pull Request:** [#142](x)" \
    '```' \
    "" \
    "End of notes."
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 1 ]
  [[ "$output" == *'[info] idempotent check failed: completion-section-missing'* ]]
}

@test "fenced '- [ ]' inside Acceptance Criteria not counted → exit 0" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "Example of an unchecked item:" \
    "" \
    '```' \
    "- [ ] placeholder example" \
    '```' \
    "" \
    "- [x] real criterion" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Pull Request:** [#142](x)"
  run bash "$CHECK" "$DOC" 142
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing args → exit 2 with usage stderr" {
  run bash "$CHECK"
  [ "$status" -eq 2 ]
  [[ "$output" == *'[error] check-idempotent: usage'* ]]
}

@test "one arg only → exit 2" {
  write_doc_lf "## Acceptance Criteria"
  run bash "$CHECK" "$DOC"
  [ "$status" -eq 2 ]
}

@test "prNumber=NaN → exit 2" {
  write_doc_lf "## Acceptance Criteria"
  run bash "$CHECK" "$DOC" NaN
  [ "$status" -eq 2 ]
}

@test "prNumber=-1 → exit 2" {
  write_doc_lf "## Acceptance Criteria"
  run bash "$CHECK" "$DOC" -1
  [ "$status" -eq 2 ]
}

@test "prNumber=#142 (leading hash) → exit 2" {
  write_doc_lf "## Acceptance Criteria"
  run bash "$CHECK" "$DOC" "#142"
  [ "$status" -eq 2 ]
}

@test "non-existent doc path → exit 2" {
  run bash "$CHECK" "${TMPDIR_TEST}/does-not-exist.md" 142
  [ "$status" -eq 2 ]
  [[ "$output" == *'file not found'* ]]
}

@test "PR number substring must not match (e.g., 14 is prefix of 142) → pr-line-mismatch" {
  write_doc_lf \
    "## Acceptance Criteria" \
    "" \
    "- [x] done" \
    "" \
    "## Completion" \
    "" \
    "**Status:** \`Complete\`" \
    "" \
    "**Pull Request:** [#142](https://github.com/x/y/pull/142)"
  run bash "$CHECK" "$DOC" 14
  [ "$status" -eq 1 ]
  [[ "$output" == *'[info] idempotent check failed: pr-line-mismatch'* ]]
}
