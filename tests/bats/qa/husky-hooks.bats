#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# QA tests for CHORE-037 — husky hook tier split.
# Plan: qa/test-plans/QA-plan-CHORE-037.md
#
# Covers the test-framework-mode scenarios:
#   P0 Inputs    — pre-commit drops heavy commands
#   P0 Inputs    — pre-push exists, executable, contains heavy commands
#   P0 Inputs    — pre-commit retains fast checks
#   P1 Inputs    — pre-push runs commands in order; failure short-circuits later commands
#   P1 X-cutting — pre-push committed with executable bit
#
# Exploratory / manual scenarios (real `git commit` round-trip, --no-verify,
# tag pushes, fresh clone, network-offline npm audit, IDE integration, etc.)
# are not exercised here — they live in the QA results document under exploratory.

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PRE_COMMIT="${REPO_ROOT}/.husky/pre-commit"
  PRE_PUSH="${REPO_ROOT}/.husky/pre-push"
}

# ---------------------------------------------------------------------------
# AC #1 (P0 Inputs): pre-commit must NOT contain any heavy command.
# ---------------------------------------------------------------------------

@test "pre-commit does not invoke 'npm test'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+test' "$PRE_COMMIT"
  [ "$status" -ne 0 ]
}

@test "pre-commit does not invoke 'npm audit'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+audit' "$PRE_COMMIT"
  [ "$status" -ne 0 ]
}

@test "pre-commit does not invoke 'npm run validate'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+run[[:space:]]+validate' "$PRE_COMMIT"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC #2 (P0 Inputs): pre-push exists, executable, contains the heavy commands.
# ---------------------------------------------------------------------------

@test "pre-push file exists" {
  [ -f "$PRE_PUSH" ]
}

@test "pre-push is executable" {
  [ -x "$PRE_PUSH" ]
}

@test "pre-push invokes 'npm test'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+test' "$PRE_PUSH"
  [ "$status" -eq 0 ]
}

@test "pre-push invokes 'npm audit --audit-level=high'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+audit[[:space:]]+--audit-level=high' "$PRE_PUSH"
  [ "$status" -eq 0 ]
}

@test "pre-push invokes 'npm run validate'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+run[[:space:]]+validate' "$PRE_PUSH"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC #3 (P0 Inputs): pre-commit must retain the three fast checks.
# ---------------------------------------------------------------------------

@test "pre-commit invokes 'npx lint-staged'" {
  run grep -E '^[[:space:]]*npx[[:space:]]+lint-staged' "$PRE_COMMIT"
  [ "$status" -eq 0 ]
}

@test "pre-commit invokes 'npm run lint'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+run[[:space:]]+lint([[:space:]]|$)' "$PRE_COMMIT"
  [ "$status" -eq 0 ]
}

@test "pre-commit invokes 'npm run format:check'" {
  run grep -E '^[[:space:]]*npm[[:space:]]+run[[:space:]]+format:check' "$PRE_COMMIT"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# P1 Inputs: pre-push declares commands in deterministic order.
# Order is asserted by static line-number ordering of the three commands.
# ---------------------------------------------------------------------------

@test "pre-push declares 'npm test' before 'npm audit'" {
  test_line=$(grep -nE '^[[:space:]]*npm[[:space:]]+test' "$PRE_PUSH" | head -1 | cut -d: -f1)
  audit_line=$(grep -nE '^[[:space:]]*npm[[:space:]]+audit' "$PRE_PUSH" | head -1 | cut -d: -f1)
  [ -n "$test_line" ]
  [ -n "$audit_line" ]
  [ "$test_line" -lt "$audit_line" ]
}

@test "pre-push declares 'npm audit' before 'npm run validate'" {
  audit_line=$(grep -nE '^[[:space:]]*npm[[:space:]]+audit' "$PRE_PUSH" | head -1 | cut -d: -f1)
  validate_line=$(grep -nE '^[[:space:]]*npm[[:space:]]+run[[:space:]]+validate' "$PRE_PUSH" | head -1 | cut -d: -f1)
  [ -n "$audit_line" ]
  [ -n "$validate_line" ]
  [ "$audit_line" -lt "$validate_line" ]
}

# ---------------------------------------------------------------------------
# P1 Inputs: husky's wrapper runs the hook with `sh -e`, so a failing command
# short-circuits later commands. Verify by stubbing `npm` to fail on `test`
# and recording call order; later commands must not be invoked, and the
# wrapper must propagate the non-zero exit.
# ---------------------------------------------------------------------------

@test "pre-push short-circuits when 'npm test' fails (later commands not invoked)" {
  tmpdir="$(mktemp -d)"
  log="${tmpdir}/calls.log"
  bin="${tmpdir}/bin"
  mkdir -p "$bin"

  # Stub `npm`: log every invocation; exit 1 when the first arg is `test`.
  cat > "${bin}/npm" <<STUB
#!/usr/bin/env sh
echo "\$@" >> "${log}"
case "\$1" in
  test) exit 1 ;;
  *)    exit 0 ;;
esac
STUB
  chmod +x "${bin}/npm"

  # Run pre-push under `sh -e` (the same flag husky's wrapper uses) with the
  # stub PATH first so our `npm` shadows the real one.
  PATH="${bin}:${PATH}" run sh -e "$PRE_PUSH"

  # Hook exited non-zero (test failure propagated)
  [ "$status" -ne 0 ]

  # First call was `test`; subsequent commands (`audit`, `run validate`) MUST
  # NOT appear in the log because `sh -e` halted execution.
  [ -f "$log" ]
  first_call=$(head -1 "$log")
  [[ "$first_call" == "test" ]]

  # No `audit` line and no `run validate` line.
  run grep -E '^audit' "$log"
  [ "$status" -ne 0 ]
  run grep -E '^run validate' "$log"
  [ "$status" -ne 0 ]

  rm -rf "$tmpdir"
}

@test "pre-push runs all three commands in order when each succeeds" {
  tmpdir="$(mktemp -d)"
  log="${tmpdir}/calls.log"
  bin="${tmpdir}/bin"
  mkdir -p "$bin"

  cat > "${bin}/npm" <<STUB
#!/usr/bin/env sh
echo "\$@" >> "${log}"
exit 0
STUB
  chmod +x "${bin}/npm"

  PATH="${bin}:${PATH}" run sh -e "$PRE_PUSH"
  [ "$status" -eq 0 ]

  # Three lines, in expected order.
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 3 ]
  [ "$(sed -n 1p "$log")" = "test" ]
  [ "$(sed -n 2p "$log")" = "audit --audit-level=high" ]
  [ "$(sed -n 3p "$log")" = "run validate" ]

  rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# P1 Cross-cutting: pre-push is committed with the executable bit set so a
# fresh clone receives it ready to run. Use `git ls-files --stage` to read
# the index mode (100755 = executable, 100644 = not).
# ---------------------------------------------------------------------------

@test "pre-push is staged with executable bit (mode 100755)" {
  cd "$REPO_ROOT"
  run git ls-files --stage .husky/pre-push
  [ "$status" -eq 0 ]
  # First field of `ls-files --stage` is the mode.
  mode=$(echo "$output" | awk '{print $1}')
  [ "$mode" = "100755" ]
}

@test "pre-commit is staged with executable bit (mode 100755) — regression check" {
  cd "$REPO_ROOT"
  run git ls-files --stage .husky/pre-commit
  [ "$status" -eq 0 ]
  mode=$(echo "$output" | awk '{print $1}')
  [ "$mode" = "100755" ]
}
