#!/usr/bin/env bats
# QA-BUG-022 — adversarial QA for the detect-re-qa-mode.sh state-cross-check fix.
# SUT: plugins/lwndev-sdlc/skills/executing-qa/scripts/detect-re-qa-mode.sh.
# Adopted from the ephemeral QA run (qa-detect-re-qa-mode.bats) into this
# permanent *.qa.bats sibling next to the peer regression re-qa-mode.bats.
#
# Coverage focuses on adversarial dimensions NOT already exercised by the
# permanent regression at tests/bats/skills/executing-qa/re-qa-mode.bats:
#   Inputs (injection / weird ID, malformed marker)
#   State transitions (sequential initial -> re-qa flip)
#   Dependency failure (malformed state JSON, legacy schema)
#   Environment (outside a git repo)
#   Cross-cutting (idempotency, two-ID isolation on one branch)

setup() {
  # tests/bats/skills/executing-qa is FOUR levels below repo root.
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/executing-qa/scripts" && pwd)"
  SCRIPT="${SCRIPT_DIR}/detect-re-qa-mode.sh"
  WFSTATE="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/orchestrating-workflows/scripts" && pwd)/workflow-state.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

_wf_init() { bash "$WFSTATE" init "$1" bug >/dev/null; }

_wf_set_prior_run() {
  _wf_init "$1"
  bash "$WFSTATE" inc-qa-fix-attempts "$1" >/dev/null
  bash "$WFSTATE" set-qa-verdict "$1" ISSUES-FOUND >/dev/null
}

_commit_qa_file() {
  mkdir -p tests/unit
  echo "// qa test" > "tests/unit/$1"
  git add "tests/unit/$1"
  git commit -q -m "qa: add $1"
}

# --- Inputs: adversarial ID strings -----------------------------------------

@test "QA-BUG-022: shell-injection ID does not execute; valid JSON, mode=initial" {
  _commit_qa_file qa-foo.test.ts
  # An ID that would run a command if interpolated unquoted into a shell call.
  run bash "$SCRIPT" 'FEAT-$(touch PWNED)'
  [ "$status" -eq 0 ]
  [ ! -e PWNED ]                              # injection must NOT have fired
  echo "$output" | jq -e . >/dev/null         # stdout is valid JSON
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "QA-BUG-022: non-existent ID with no state -> exit 0, valid JSON, initial" {
  _commit_qa_file qa-foo.test.ts
  run bash "$SCRIPT" BUG-99999
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "QA-BUG-022: empty/malformed baseline marker keys on state, not marker -> initial" {
  _wf_init FEAT-300          # fresh: qaFixAttempts=0, qaLastVerdict=null
  mkdir -p .sdlc/qa
  printf 'not-a-sha\n\n###\n' > .sdlc/qa/.executing-qa-baseline-FEAT-300
  _commit_qa_file qa-foo.test.ts
  run bash "$SCRIPT" FEAT-300
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# --- State transitions: sequential flip -------------------------------------

@test "QA-BUG-022: same ID flips initial -> re-qa once a prior run is recorded" {
  _wf_init FEAT-301
  _commit_qa_file qa-foo.test.ts

  run bash "$SCRIPT" FEAT-301           # first run: no prior QA history
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null

  bash "$WFSTATE" set-qa-verdict FEAT-301 ISSUES-FOUND >/dev/null
  bash "$WFSTATE" inc-qa-fix-attempts FEAT-301 >/dev/null

  run bash "$SCRIPT" FEAT-301           # second run: prior history now present
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files | length >= 1' >/dev/null
}

# --- Dependency failure: state read fails safe ------------------------------

@test "QA-BUG-022: malformed state JSON fails safe to initial (not re-qa)" {
  mkdir -p .sdlc/workflows
  printf '{ this is not valid json ::: ' > .sdlc/workflows/FEAT-302.json
  _commit_qa_file qa-foo.test.ts
  run bash "$SCRIPT" FEAT-302
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "QA-BUG-022: legacy state file lacking qaFixAttempts/qaLastVerdict -> initial" {
  mkdir -p .sdlc/workflows
  # Pre-FEAT-032 shaped state: no qaFixAttempts / qaLastVerdict fields.
  printf '{"id":"FEAT-303","type":"bug","currentStep":5,"status":"in-progress","steps":[]}\n' \
    > .sdlc/workflows/FEAT-303.json
  _commit_qa_file qa-foo.test.ts
  run bash "$SCRIPT" FEAT-303
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

# --- Environment: no git repo -----------------------------------------------

@test "QA-BUG-022: outside a git repo -> exit 0, files=[], mode=initial" {
  NONGIT="$(mktemp -d)"
  cd "$NONGIT"
  run bash "$SCRIPT" FEAT-304
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
  echo "$output" | jq -e '.files | length == 0' >/dev/null
  rm -rf "$NONGIT"
}

# --- Cross-cutting: idempotency + isolation ---------------------------------

@test "QA-BUG-022: back-to-back invocations are idempotent; marker untouched" {
  _wf_set_prior_run FEAT-305
  mkdir -p .sdlc/qa
  echo "deadbeef" > .sdlc/qa/.executing-qa-baseline-FEAT-305
  _commit_qa_file qa-foo.test.ts
  marker_before="$(md5 -q .sdlc/qa/.executing-qa-baseline-FEAT-305 2>/dev/null || md5sum .sdlc/qa/.executing-qa-baseline-FEAT-305 | cut -d' ' -f1)"

  run bash "$SCRIPT" FEAT-305
  [ "$status" -eq 0 ]
  out1="$output"
  run bash "$SCRIPT" FEAT-305
  [ "$status" -eq 0 ]
  out2="$output"

  [ "$out1" = "$out2" ]                        # identical stdout
  echo "$out1" | jq -e '.mode == "re-qa"' >/dev/null
  marker_after="$(md5 -q .sdlc/qa/.executing-qa-baseline-FEAT-305 2>/dev/null || md5sum .sdlc/qa/.executing-qa-baseline-FEAT-305 | cut -d' ' -f1)"
  [ "$marker_before" = "$marker_after" ]       # detect never writes the marker
}

@test "QA-BUG-022: two IDs on one branch — fresh stays initial, prior resolves re-qa" {
  _wf_init FEAT-306                    # fresh ID
  _wf_set_prior_run FEAT-307          # genuine prior run
  _commit_qa_file qa-shared.test.ts   # one committed qa-* file, branch-wide

  run bash "$SCRIPT" FEAT-306
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null

  run bash "$SCRIPT" FEAT-307
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
}
