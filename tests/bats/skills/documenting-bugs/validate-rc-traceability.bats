#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for validate-rc-traceability.sh (CHORE-036 item 1.5).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/documenting-bugs/scripts" && pwd)"
  RC_VALIDATE="${SCRIPT_DIR}/validate-rc-traceability.sh"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

write_doc() {
  # write_doc <name> <heredoc-content-via-stdin>
  cat > "${TMPDIR_TEST}/$1"
}

# ---------- happy path (exit 0) ----------

@test "round-trip satisfied: exit 0 with empty arrays" {
  write_doc "ok.md" <<EOF
# Bug: Foo

## Root Cause(s)

1. RC-1: first cause
2. RC-2: second cause

## Acceptance Criteria

- [ ] criterion alpha (RC-1)
- [ ] criterion beta (RC-2)
- [ ] criterion combined (RC-1, RC-2)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/ok.md"
  [ "$status" -eq 0 ]
  [ "$output" = '{"missingRCs": [], "untaggedACs": []}' ]
}

@test "vacuously empty (no RCs declared, no AC bullets): exit 0" {
  write_doc "empty.md" <<EOF
## Root Cause(s)

(investigation pending)

## Acceptance Criteria

EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/empty.md"
  [ "$status" -eq 0 ]
  [ "$output" = '{"missingRCs": [], "untaggedACs": []}' ]
}

# ---------- exit 1: violations ----------

@test "untagged AC: exit 1 with untaggedACs populated" {
  write_doc "untagged.md" <<EOF
## Root Cause(s)

1. RC-1: foo

## Acceptance Criteria

- [ ] criterion without tag
- [ ] criterion with tag (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/untagged.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"untaggedACs"'* ]]
  [[ "$output" == *'criterion without tag'* ]]
  [[ "$output" == *'"missingRCs": []'* ]]
}

@test "missing RC reference: exit 1 with missingRCs populated" {
  write_doc "missing.md" <<EOF
## Root Cause(s)

1. RC-1: alpha
2. RC-2: beta

## Acceptance Criteria

- [ ] only refers to RC-1 (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/missing.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"missingRCs": ["RC-2"]'* ]]
  [[ "$output" == *'"untaggedACs": []'* ]]
}

@test "RC declared but AC section empty: exit 1 (round-trip violated)" {
  write_doc "rc-no-ac.md" <<EOF
## Root Cause(s)

1. RC-1: only one cause

## Acceptance Criteria

EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/rc-no-ac.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"missingRCs": ["RC-1"]'* ]]
}

@test "AC bullets exist but no RCs declared: exit 1 (untagged ACs)" {
  write_doc "ac-no-rc.md" <<EOF
## Root Cause(s)

(none yet)

## Acceptance Criteria

- [ ] criterion without tag
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/ac-no-rc.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'criterion without tag'* ]]
}

# ---------- HTML-comment exclusion ----------

@test "AC bullets inside HTML comments are excluded" {
  write_doc "comments.md" <<EOF
## Root Cause(s)

1. RC-1: foo

## Acceptance Criteria

<!--
Examples:
- [ ] example bullet without tag
- [ ] another example without tag
-->

- [ ] real criterion (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/comments.md"
  [ "$status" -eq 0 ]
  [ "$output" = '{"missingRCs": [], "untaggedACs": []}' ]
}

@test "RC tokens inside HTML comments do not count as declarations" {
  # If RC-99 only appears in a comment, it must not be considered declared.
  write_doc "rc-comment.md" <<EOF
## Root Cause(s)

<!-- example: 1. RC-99: stale guidance from the template -->
1. RC-1: actual cause

## Acceptance Criteria

- [ ] real criterion (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/rc-comment.md"
  [ "$status" -eq 0 ]
  [ "$output" = '{"missingRCs": [], "untaggedACs": []}' ]
}

# ---------- both violation types together ----------

@test "missing RCs AND untagged ACs together: exit 1, both arrays populated" {
  write_doc "both.md" <<EOF
## Root Cause(s)

1. RC-1: foo
2. RC-2: bar

## Acceptance Criteria

- [ ] tagged criterion (RC-1)
- [ ] untagged criterion
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/both.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"missingRCs": ["RC-2"]'* ]]
  [[ "$output" == *'untagged criterion'* ]]
}

# ---------- exit 2: usage / structural errors ----------

@test "no args: exit 2 with usage error" {
  run bash "$RC_VALIDATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: usage:"* ]]
}

@test "missing file: exit 2" {
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/does-not-exist.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [[ "$output" == *"not readable"* ]]
}

@test "missing Root Cause(s) section: exit 2" {
  write_doc "no-rc.md" <<EOF
## Acceptance Criteria

- [ ] criterion (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/no-rc.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing '## Root Cause(s)' section"* ]]
}

@test "missing Acceptance Criteria section: exit 2" {
  write_doc "no-ac.md" <<EOF
## Root Cause(s)

1. RC-1: foo
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/no-ac.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing '## Acceptance Criteria' section"* ]]
}

# ---------- bullet-shape exclusions ----------

@test "non-checkbox bullets are not counted as ACs" {
  write_doc "bullets.md" <<EOF
## Root Cause(s)

1. RC-1: foo

## Acceptance Criteria

- not a checkbox bullet (no brackets)
* alternative bullet style (no brackets)
- [ ] real criterion (RC-1)
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/bullets.md"
  [ "$status" -eq 0 ]
}

@test "checked-off ([x]) bullets count and are validated" {
  write_doc "checked.md" <<EOF
## Root Cause(s)

1. RC-1: foo

## Acceptance Criteria

- [x] completed criterion without tag
EOF
  run bash "$RC_VALIDATE" "${TMPDIR_TEST}/checked.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"completed criterion without tag"* ]]
}
