#!/usr/bin/env bats
# Bats fixture for extract-issue-ref.sh (FEAT-025 / FR-2).
#
# Covers all heading variants, GitHub + Jira link patterns, edge cases
# (empty section, first-match-only, missing section), and error exits.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  EXTRACT="${SCRIPT_DIR}/extract-issue-ref.sh"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Helper: write a doc file with the given body to $TMPDIR_TEST/doc.md.
write_doc() {
  local body="$1"
  printf '%s\n' "$body" > "${TMPDIR_TEST}/doc.md"
}

@test "heading '## GitHub Issue' with [#119](URL) → #119" {
  write_doc '# Feature

## GitHub Issue

- Tracker: [#119](https://github.com/lwndev/lwndev-marketplace/issues/119)

## Other Section
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "#119" ]
}

@test "heading '## Issue' with [#42](URL) → #42" {
  write_doc '## Issue

[#42](https://example.com/42)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "#42" ]
}

@test "heading '## Issue Tracker' with [PROJ-123](URL) → PROJ-123" {
  write_doc '## Issue Tracker

[PROJ-123](https://jira.example.com/browse/PROJ-123)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
}

@test "alphanumeric Jira key [AB2-456](URL) → AB2-456" {
  write_doc '## Issue Tracker

[AB2-456](https://jira.example.com/browse/AB2-456)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "AB2-456" ]
}

@test "multiple links in section → first match only (edge case 11)" {
  write_doc '## GitHub Issue

- [#100](https://example.com/100)
- [#200](https://example.com/200)
- [#300](https://example.com/300)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "#100" ]
}

@test "section present but empty → empty stdout, exit 0" {
  write_doc '# Foo

## GitHub Issue

## Next Section

[#999](https://example.com/999)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "no matching section → empty stdout, exit 0 (edge case 10)" {
  write_doc '# Feature

## Summary

Description only.

## Acceptance Criteria

None.
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "section exists but has unrelated links → empty stdout, exit 0" {
  write_doc '## GitHub Issue

See the [docs](https://example.com/docs) for more information.
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "longer heading '## GitHub Issue URL' does NOT match" {
  write_doc '## GitHub Issue URL

[#55](https://example.com/55)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "content only within section (subsequent ## bounds it)" {
  write_doc '## GitHub Issue

No link here.

## Acceptance Criteria

[#77](https://example.com/77)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "mixed refs in section — first encountered wins (github first)" {
  write_doc '## Issue

- [#11](https://example.com/11)
- [PROJ-22](https://jira.example.com/browse/PROJ-22)
'
  run bash "$EXTRACT" "${TMPDIR_TEST}/doc.md"
  [ "$status" -eq 0 ]
  [ "$output" = "#11" ]
}

@test "missing arg → exit 2" {
  run bash "$EXTRACT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[error]"* ]]
}

@test "file does not exist → exit 1" {
  run bash "$EXTRACT" "${TMPDIR_TEST}/nonexistent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] extract-issue-ref: file not found"* ]]
}
