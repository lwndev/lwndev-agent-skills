#!/usr/bin/env bats
# FEAT-032 FR-3 — re-QA mode auto-detection (detect-re-qa-mode.sh) + FR-13
# negative invariant (re-QA never deletes QA files).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/executing-qa/scripts" && pwd)"
  SCRIPT="${SCRIPT_DIR}/detect-re-qa-mode.sh"
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

# --- arg validation ---------------------------------------------------------

@test "no args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "empty ID -> exit 2" {
  run bash "$SCRIPT" ""
  [ "$status" -eq 2 ]
}

# --- mode detection ---------------------------------------------------------

@test "no marker, no QA files -> mode=initial" {
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
  echo "$output" | jq -e '.files | length == 0' >/dev/null
}

@test "marker present, no QA files tracked -> mode=initial (skip)" {
  mkdir -p .sdlc/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "no marker, QA files tracked -> mode=initial (skip)" {
  mkdir -p tests/unit
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "marker + tracked QA .test.ts -> mode=re-qa" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files | length == 1' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/unit/qa-foo.test.ts"' >/dev/null
}

@test "marker + tracked QA .test.js -> mode=re-qa" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.js
  git add tests/unit/qa-foo.test.js
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/unit/qa-foo.test.js"' >/dev/null
}

@test "marker + tracked QA .bats under tests/bats/qa/ -> mode=re-qa" {
  mkdir -p .sdlc/qa tests/bats/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "@test 'a' { :; }" > tests/bats/qa/qa-foo.bats
  git add tests/bats/qa/qa-foo.bats
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files[0] == "tests/bats/qa/qa-foo.bats"' >/dev/null
}

@test "marker + UNTRACKED QA file -> mode=initial (FR-3 tracked-files only)" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// untracked" > tests/unit/qa-foo.test.ts
  # don't git add
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "forward-compat .py / .go are NO-OPS in v1 — even with marker, mode=initial" {
  mkdir -p .sdlc/qa tests/python pkg/validate
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "def t(): pass" > tests/python/qa_input.py
  echo "package x" > pkg/validate/qa_input_test.go
  git add tests/python/qa_input.py pkg/validate/qa_input_test.go
  git commit -q -m "qa(FEAT-100): py+go (v1 no-op)"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  # v1 globs only catch .test.ts / .test.js / .bats
  echo "$output" | jq -e '.mode == "initial"' >/dev/null
}

@test "marker + multiple tracked QA files -> mode=re-qa with all files in array" {
  mkdir -p .sdlc/qa tests/unit tests/bats/qa
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// a" > tests/unit/qa-a.test.ts
  echo "// b" > tests/unit/qa-b.test.ts
  echo "@test x { :; }" > tests/bats/qa/qa-c.bats
  git add tests/unit/qa-a.test.ts tests/unit/qa-b.test.ts tests/bats/qa/qa-c.bats
  git commit -q -m "qa(FEAT-100): add"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "re-qa"' >/dev/null
  echo "$output" | jq -e '.files | length == 3' >/dev/null
}

# --- FR-13 negative invariant: detect doesn't delete files ------------------

@test "FR-13: detect-re-qa-mode.sh never deletes QA files" {
  mkdir -p .sdlc/qa tests/unit
  echo "abc123" > .sdlc/qa/.executing-qa-baseline-FEAT-100
  echo "// qa test" > tests/unit/qa-foo.test.ts
  git add tests/unit/qa-foo.test.ts
  git commit -q -m "qa: add"
  before="$(git ls-files tests/unit/ | wc -l | tr -d ' ')"
  run bash "$SCRIPT" FEAT-100
  [ "$status" -eq 0 ]
  after="$(git ls-files tests/unit/ | wc -l | tr -d ' ')"
  [ "$before" -eq "$after" ]
  [ -f tests/unit/qa-foo.test.ts ]
}
