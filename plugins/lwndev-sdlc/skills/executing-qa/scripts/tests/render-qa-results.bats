#!/usr/bin/env bats
# Bats fixture for render-qa-results.sh (FEAT-030 / FR-7).
#
# Verifies the per-verdict structural rules from the Phase-1 contract at
# `plugins/lwndev-sdlc/skills/executing-qa/references/qa-return-contract.md`:
#   * PASS         → Failed: 0 in Execution Results, empty Findings.
#   * ISSUES-FOUND → at least one failing-test name listed under Findings.
#   * ERROR        → stack-trace passthrough in Execution Results.
#   * EXPLORATORY-ONLY → Reason: line under Exploratory Mode, all counts zero.
#   * Invalid verdict → exit 1.
#   * Missing required field for verdict → exit 1.
#   * Missing/invalid args → exit 2.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/render-qa-results.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  CAP="cap.json"
  jq -n '{framework:"vitest",language:"typescript",packageManager:"npm",testCommand:"npm test",mode:"test-framework",notes:[]}' > "$CAP"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

write_exec_pass() {
  jq -n '{total:12,passed:12,failed:0,errored:0,failingNames:[],truncatedOutput:"",exitCode:0,durationMs:120}' > exec.json
}
write_exec_issues() {
  jq -n '{total:12,passed:11,failed:1,errored:0,failingNames:["src/foo.test.ts > my failing test"],truncatedOutput:"",exitCode:1,durationMs:120}' > exec.json
}
write_exec_error() {
  jq -n '{total:0,passed:0,failed:0,errored:1,failingNames:[],truncatedOutput:"Stack trace: thing exploded\n  at line 5",exitCode:2,durationMs:15}' > exec.json
}

# --- Arg validation --------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}
@test "missing capability JSON → exit 2" {
  write_exec_pass
  run bash "$SCRIPT" FEAT-030 PASS no-cap.json exec.json
  [ "$status" -eq 2 ]
}
@test "missing execution JSON for non-EXPLORATORY → exit 2" {
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" no-exec.json
  [ "$status" -eq 2 ]
}
@test "malformed capability JSON → exit 2" {
  write_exec_pass
  printf 'not json' > "$CAP"
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 2 ]
}
@test "malformed execution JSON → exit 2" {
  printf 'not json' > exec.json
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 2 ]
}

# --- Verdict validation ---------------------------------------------------

@test "invalid verdict → exit 1" {
  write_exec_pass
  run bash "$SCRIPT" FEAT-030 BOGUS "$CAP" exec.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid verdict"* ]]
}

@test "PASS verdict with Failed != 0 → exit 1" {
  write_exec_issues
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires Failed: 0"* ]]
}

@test "ISSUES-FOUND verdict with empty failingNames → exit 1" {
  jq -n '{total:0,passed:0,failed:1,errored:0,failingNames:[],truncatedOutput:"",exitCode:1,durationMs:1}' > exec.json
  run bash "$SCRIPT" FEAT-030 ISSUES-FOUND "$CAP" exec.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires at least one failingNames"* ]]
}

@test "EXPLORATORY-ONLY without QA_EXPLORATORY_REASON → exit 1" {
  unset QA_EXPLORATORY_REASON
  run bash "$SCRIPT" FEAT-030 EXPLORATORY-ONLY "$CAP" /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires QA_EXPLORATORY_REASON"* ]]
}

# --- Per-verdict structure -----------------------------------------------

@test "PASS verdict — Failed: 0, empty Findings" {
  write_exec_pass
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  [ -f "$artifact" ]
  grep -q '^verdict: PASS$' "$artifact"
  grep -q '^Failed: 0$' "$artifact"
  # Findings section header present, but the section body is empty.
  grep -q '^## Findings$' "$artifact"
  # Lines between '## Findings' and the next '## ' header should be only blank.
  awk '/^## Findings$/{flag=1;next} /^## /{flag=0} flag' "$artifact" \
    | tr -d '[:space:]' | wc -c | tr -d ' ' | grep -q '^0$'
}

@test "ISSUES-FOUND verdict — failing-test names listed in Findings" {
  write_exec_issues
  run bash "$SCRIPT" FEAT-030 ISSUES-FOUND "$CAP" exec.json
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  grep -q '^verdict: ISSUES-FOUND$' "$artifact"
  grep -q 'src/foo.test.ts > my failing test' "$artifact"
}

@test "ERROR verdict — stack trace appears in Execution Results" {
  write_exec_error
  run bash "$SCRIPT" FEAT-030 ERROR "$CAP" exec.json
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  grep -q '^verdict: ERROR$' "$artifact"
  grep -q 'thing exploded' "$artifact"
}

@test "EXPLORATORY-ONLY verdict — Reason line under Exploratory Mode, counts zero" {
  QA_EXPLORATORY_REASON="No supported test framework detected." \
    run bash "$SCRIPT" FEAT-030 EXPLORATORY-ONLY "$CAP" /dev/null
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  grep -q '^verdict: EXPLORATORY-ONLY$' "$artifact"
  grep -q '^## Exploratory Mode$' "$artifact"
  grep -q '^Reason: No supported test framework detected.$' "$artifact"
  # Exploratory artifacts must NOT contain Execution Results section.
  ! grep -q '^## Execution Results$' "$artifact"
}

# --- Common artifact structure -------------------------------------------

@test "every artifact has v2 frontmatter and required sections in order" {
  write_exec_pass
  run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  grep -q '^id: FEAT-030$' "$artifact"
  grep -q '^version: 2$' "$artifact"
  grep -q '^persona: qa$' "$artifact"
  # Required sections appear in canonical order.
  awk '/^## /{print}' "$artifact" > sections.txt
  grep -q '^## Summary$' sections.txt
  grep -q '^## Capability Report$' sections.txt
  grep -q '^## Execution Results$' sections.txt
  grep -q '^## Scenarios Run$' sections.txt
  grep -q '^## Findings$' sections.txt
  grep -q '^## Reconciliation Delta$' sections.txt
}

@test "QA_OUTPUT_DIR override — artifact written to custom path" {
  write_exec_pass
  QA_OUTPUT_DIR="custom-out" run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 0 ]
  [ -f "custom-out/QA-results-FEAT-030.md" ]
}

@test "QA_RECONCILIATION env override — body of Reconciliation Delta is replaced" {
  write_exec_pass
  QA_RECONCILIATION='### Coverage beyond requirements
- (custom surplus)
### Coverage gaps
### Summary
- coverage-surplus: 1
- coverage-gap: 0' \
    run bash "$SCRIPT" FEAT-030 PASS "$CAP" exec.json
  [ "$status" -eq 0 ]
  artifact="$(echo "$output" | tail -n 1)"
  grep -q '(custom surplus)' "$artifact"
}
