#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# Bats fixture for managing-source-control/scripts/az-shape-transform.sh
# (FEAT-033 Phase 4). Verifies the FR-5 transform table: status → state,
# mergeStatus → mergeable, _links.web.href → url, pullRequestId → number,
# plus the list-array shape.

setup() {
  TRANSFORM="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)/az-shape-transform.sh"
}

# ---------- state mapping ----------

@test "state: active → OPEN" {
  run bash "$TRANSFORM" state active
  [ "$status" -eq 0 ]
  [ "$output" = "OPEN" ]
}

@test "state: abandoned → CLOSED" {
  run bash "$TRANSFORM" state abandoned
  [ "$status" -eq 0 ]
  [ "$output" = "CLOSED" ]
}

@test "state: completed → MERGED" {
  run bash "$TRANSFORM" state completed
  [ "$status" -eq 0 ]
  [ "$output" = "MERGED" ]
}

@test "state: unknown value → UNKNOWN" {
  run bash "$TRANSFORM" state weirdvalue
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

# ---------- mergeable mapping ----------

@test "mergeable: succeeded → MERGEABLE" {
  run bash "$TRANSFORM" mergeable succeeded
  [ "$status" -eq 0 ]
  [ "$output" = "MERGEABLE" ]
}

@test "mergeable: conflicts → CONFLICTING" {
  run bash "$TRANSFORM" mergeable conflicts
  [ "$status" -eq 0 ]
  [ "$output" = "CONFLICTING" ]
}

@test "mergeable: queued → UNKNOWN" {
  run bash "$TRANSFORM" mergeable queued
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

@test "mergeable: notSet → UNKNOWN" {
  run bash "$TRANSFORM" mergeable notSet
  [ "$status" -eq 0 ]
  [ "$output" = "UNKNOWN" ]
}

# ---------- show subcommand ----------

@test "show: full PR object → normalized gh-view shape" {
  json='{"pullRequestId":42,"title":"feat: example","status":"active","mergeStatus":"succeeded","_links":{"web":{"href":"https://dev.azure.com/contoso/sdlc/_git/repo/pullrequest/42"}},"targetRefName":"refs/heads/main"}'
  run bash "$TRANSFORM" show "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"title":"feat: example"'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"mergeable":"MERGEABLE"'* ]]
  [[ "$output" == *'"url":"https://dev.azure.com/contoso/sdlc/_git/repo/pullrequest/42"'* ]]
  [[ "$output" == *'"files":[]'* ]]
}

@test "show: completed + conflicts → MERGED + CONFLICTING" {
  json='{"pullRequestId":7,"title":"t","status":"completed","mergeStatus":"conflicts","_links":{"web":{"href":"http://x"}}}'
  run bash "$TRANSFORM" show "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"MERGED"'* ]]
  [[ "$output" == *'"mergeable":"CONFLICTING"'* ]]
}

@test "show: missing _links → empty url" {
  json='{"pullRequestId":1,"title":"t","status":"active","mergeStatus":"succeeded"}'
  run bash "$TRANSFORM" show "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"url":""'* ]]
}

@test "show: reads stdin when arg is '-'" {
  json='{"pullRequestId":99,"title":"stdin","status":"abandoned","mergeStatus":"queued"}'
  run bash -c "printf '%s' '$json' | bash '$TRANSFORM' show -"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":99'* ]]
  [[ "$output" == *'"state":"CLOSED"'* ]]
  [[ "$output" == *'"mergeable":"UNKNOWN"'* ]]
}

# ---------- list subcommand ----------

@test "list: array → [{number,state}, ...]" {
  json='[{"pullRequestId":1,"status":"active"},{"pullRequestId":2,"status":"completed"}]'
  run bash "$TRANSFORM" list "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":1'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"number":2'* ]]
  [[ "$output" == *'"state":"MERGED"'* ]]
}

@test "list: empty array → []" {
  run bash "$TRANSFORM" list "[]"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------- usage / error paths ----------

@test "no subcommand → exit 2" {
  run bash "$TRANSFORM"
  [ "$status" -eq 2 ]
}

@test "unknown subcommand → exit 2" {
  run bash "$TRANSFORM" bogus
  [ "$status" -eq 2 ]
}
