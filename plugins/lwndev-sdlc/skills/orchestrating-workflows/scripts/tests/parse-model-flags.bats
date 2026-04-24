#!/usr/bin/env bats
# Bats fixture for parse-model-flags.sh (FEAT-028 / FR-1).
#
# Covers the full unit-test matrix from the plan / requirements doc:
#   * Happy path: each flag individually, all flags together, positional
#     interleaved between flags, empty argv.
#   * Repetition: --model twice (last wins), --model-for same-step twice
#     (last wins).
#   * Error exits (2): --model=<tier> equals-sign form, unknown flag,
#     bad tier on each flag, missing arg for each flag, two positionals.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PARSE="${SCRIPT_DIR}/parse-model-flags.sh"
}

# ---- happy-path tests --------------------------------------------------------

@test "empty argv → all null / empty-string fields, exit 0" {
  run bash "$PARSE"
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":null,"cliModelFor":null,"positional":""}' ]
}

@test "--model sonnet '#186' → cliModel sonnet, positional #186" {
  run bash "$PARSE" --model sonnet '#186'
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":"sonnet","cliComplexity":null,"cliModelFor":null,"positional":"#186"}' ]
}

@test "--complexity high FEAT-028 → cliComplexity opus (label mapping)" {
  run bash "$PARSE" --complexity high FEAT-028
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":"opus","cliModelFor":null,"positional":"FEAT-028"}' ]
}

@test "--complexity medium FEAT-028 → cliComplexity sonnet (label mapping)" {
  run bash "$PARSE" --complexity medium FEAT-028
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":"sonnet","cliModelFor":null,"positional":"FEAT-028"}' ]
}

@test "--complexity low FEAT-028 → cliComplexity haiku (label mapping)" {
  run bash "$PARSE" --complexity low FEAT-028
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":"haiku","cliModelFor":null,"positional":"FEAT-028"}' ]
}

@test "--complexity opus FEAT-028 → cliComplexity opus (bare tier accepted)" {
  run bash "$PARSE" --complexity opus FEAT-028
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":"opus","cliModelFor":null,"positional":"FEAT-028"}' ]
}

@test "--model-for reviewing-requirements:opus '#186' → per-step override" {
  run bash "$PARSE" --model-for reviewing-requirements:opus '#186'
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":null,"cliModelFor":{"reviewing-requirements":"opus"},"positional":"#186"}' ]
}

@test "all three flags together → all four fields populated" {
  run bash "$PARSE" --model sonnet --complexity high --model-for reviewing-requirements:opus '#186'
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":"sonnet","cliComplexity":"opus","cliModelFor":{"reviewing-requirements":"opus"},"positional":"#186"}' ]
}

@test "positional interleaved between flags → positional recovered" {
  run bash "$PARSE" --model opus '#186' --complexity high
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":"opus","cliComplexity":"opus","cliModelFor":null,"positional":"#186"}' ]
}

# ---- repetition tests --------------------------------------------------------

@test "--model repeated → last wins" {
  run bash "$PARSE" --model opus --model sonnet
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":"sonnet","cliComplexity":null,"cliModelFor":null,"positional":""}' ]
}

@test "--model-for same step repeated → last per-step wins" {
  run bash "$PARSE" --model-for reviewing-requirements:opus --model-for reviewing-requirements:sonnet
  [ "$status" -eq 0 ]
  [ "$output" = '{"cliModel":null,"cliComplexity":null,"cliModelFor":{"reviewing-requirements":"sonnet"},"positional":""}' ]
}

@test "--model-for two distinct steps → both entries preserved" {
  run bash "$PARSE" --model-for reviewing-requirements:opus --model-for creating-implementation-plans:sonnet
  [ "$status" -eq 0 ]
  # Accept either key order — the map is unordered by contract.
  case "$output" in
    '{"cliModel":null,"cliComplexity":null,"cliModelFor":{"reviewing-requirements":"opus","creating-implementation-plans":"sonnet"},"positional":""}') : ;;
    '{"cliModel":null,"cliComplexity":null,"cliModelFor":{"creating-implementation-plans":"sonnet","reviewing-requirements":"opus"},"positional":""}') : ;;
    *) echo "unexpected output: $output" >&2; return 1 ;;
  esac
}

# ---- error-exit tests --------------------------------------------------------

@test "--model=sonnet (equals-sign form) → exit 2" {
  run bash "$PARSE" --model=sonnet
  [ "$status" -eq 2 ]
}

@test "--complexity=high (equals-sign form) → exit 2" {
  run bash "$PARSE" --complexity=high
  [ "$status" -eq 2 ]
}

@test "--model-for=reviewing-requirements:opus (equals-sign form) → exit 2" {
  run bash "$PARSE" --model-for=reviewing-requirements:opus
  [ "$status" -eq 2 ]
}

@test "unknown flag --foo bar → exit 2" {
  run bash "$PARSE" --foo bar
  [ "$status" -eq 2 ]
}

@test "--model bad-tier → exit 2" {
  run bash "$PARSE" --model bad-tier
  [ "$status" -eq 2 ]
}

@test "--complexity bad-tier → exit 2" {
  run bash "$PARSE" --complexity bad-tier
  [ "$status" -eq 2 ]
}

@test "--model-for step:bad-tier → exit 2" {
  run bash "$PARSE" --model-for reviewing-requirements:bad-tier
  [ "$status" -eq 2 ]
}

@test "--model-for without colon → exit 2" {
  run bash "$PARSE" --model-for reviewing-requirements
  [ "$status" -eq 2 ]
}

@test "--model-for empty step (:opus) → exit 2" {
  run bash "$PARSE" --model-for :opus
  [ "$status" -eq 2 ]
}

@test "--model with no following argument → exit 2" {
  run bash "$PARSE" --model
  [ "$status" -eq 2 ]
}

@test "--complexity with no following argument → exit 2" {
  run bash "$PARSE" --complexity
  [ "$status" -eq 2 ]
}

@test "--model-for with no following argument → exit 2" {
  run bash "$PARSE" --model-for
  [ "$status" -eq 2 ]
}

@test "two positional tokens → exit 2" {
  run bash "$PARSE" '#186' FEAT-001
  [ "$status" -eq 2 ]
}

@test "flag then two positionals → exit 2" {
  run bash "$PARSE" --model opus '#186' FEAT-001
  [ "$status" -eq 2 ]
}
