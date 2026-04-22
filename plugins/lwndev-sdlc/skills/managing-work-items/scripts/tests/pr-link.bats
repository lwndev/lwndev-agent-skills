#!/usr/bin/env bats
# Bats fixture for pr-link.sh (FEAT-025 / FR-3).
#
# Exercises the real backend-detect.sh sibling (no stub) since Phase 1
# delivers both scripts together. Covers the three branches and an
# idempotency assertion (pure function: same input → same output).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PR_LINK="${SCRIPT_DIR}/pr-link.sh"
}

@test "github ref #183 → 'Closes #183' + newline" {
  run bash "$PR_LINK" "#183"
  [ "$status" -eq 0 ]
  [ "$output" = "Closes #183" ]
}

@test "github ref #1 → 'Closes #1' + newline" {
  run bash "$PR_LINK" "#1"
  [ "$status" -eq 0 ]
  [ "$output" = "Closes #1" ]
}

@test "jira ref PROJ-123 → 'PROJ-123' + newline (no 'Closes' keyword)" {
  run bash "$PR_LINK" "PROJ-123"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-123" ]
  # Must not contain Closes keyword — Jira does not support GH auto-close.
  [[ "$output" != *"Closes"* ]]
}

@test "alphanumeric jira ref AB2-456 → 'AB2-456'" {
  run bash "$PR_LINK" "AB2-456"
  [ "$status" -eq 0 ]
  [ "$output" = "AB2-456" ]
}

@test "unrecognized ref 'foo' → empty stdout, exit 0" {
  run bash "$PR_LINK" "foo"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "lowercase jira-like 'proj-123' → empty stdout (backend-detect returns null)" {
  run bash "$PR_LINK" "proj-123"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "missing arg → exit 2" {
  run bash "$PR_LINK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"[error]"* ]]
}

@test "idempotency: two calls with the same github input produce identical stdout" {
  run bash "$PR_LINK" "#42"
  first="$output"
  first_status="$status"
  run bash "$PR_LINK" "#42"
  second="$output"
  [ "$first_status" -eq 0 ]
  [ "$status" -eq 0 ]
  [ "$first" = "$second" ]
}

@test "idempotency: two calls with the same jira input produce identical stdout" {
  run bash "$PR_LINK" "PROJ-42"
  first="$output"
  run bash "$PR_LINK" "PROJ-42"
  [ "$output" = "$first" ]
  [ "$status" -eq 0 ]
}

@test "jq-absent fallback path parses backend-detect output correctly" {
  # Build a minimal PATH without jq so pr-link.sh uses the pure-bash
  # fallback branch (mirrors the branch-id-parse.sh test strategy).
  empty_path="$(mktemp -d)"
  for bin in bash env grep sed awk tr cut wc mktemp head tail cat printf chmod rm mkdir ls true false test dirname basename; do
    if [ -x "/bin/$bin" ]; then
      ln -s "/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -s "/usr/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    fi
  done
  PATH="$empty_path" run bash "$PR_LINK" "#99"
  rm -rf "$empty_path"
  [ "$status" -eq 0 ]
  [ "$output" = "Closes #99" ]
}

@test "jq-absent fallback: jira branch" {
  empty_path="$(mktemp -d)"
  for bin in bash env grep sed awk tr cut wc mktemp head tail cat printf chmod rm mkdir ls true false test dirname basename; do
    if [ -x "/bin/$bin" ]; then
      ln -s "/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -s "/usr/bin/$bin" "$empty_path/$bin" 2>/dev/null || true
    fi
  done
  PATH="$empty_path" run bash "$PR_LINK" "PROJ-9"
  rm -rf "$empty_path"
  [ "$status" -eq 0 ]
  [ "$output" = "PROJ-9" ]
}
