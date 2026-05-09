#!/usr/bin/env bats
# End-to-end NFR-4 acceptance fixture for FEAT-032 (happy path).
#
# Drives the full `ISSUES-FOUND -> addressing-qa-findings (fix) -> re-QA PASS
# -> addressing-qa-findings (adopt) -> finalize` path against a known-buggy
# fixture under tests/fixtures/feat-032-known-buggy/. The test exercises the
# deterministic glue (qa-dispatch.sh, run-adopt-loop.sh, adopt-qa-test.sh,
# workflow-state.sh QA subcommands, commit-qa-artifact.sh, FR-9 safety-net)
# without booting an actual LLM-driven `executing-qa` invocation, so the
# assertion targets are the load-bearing FR contracts and not skill prose.
#
# Asserts (per the Phase 7 plan):
#   * The orchestrator branches to addressing-qa-findings on ISSUES-FOUND
#     (not directly to finalizing-workflow).
#   * The fix phase commits the production fix; the working tree is clean on
#     re-QA entry per FR-12.
#   * Re-QA returns PASS; the artifact is overwritten in place per FR-12; the
#     artifact commit message contains
#     `re-record QA results after fix attempt 1` per FR-12.
#   * The adopt phase calls adopt-qa-test.sh, prints the new path on stdout,
#     and the adoption commits the moved file.
#   * After adoption, no tracked file matches the FR-9 v1 glob set so the
#     finalize safety-net would NOT trip.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  ORCH_SCRIPTS="${PLUGIN_DIR}/skills/orchestrating-workflows/scripts"
  ADDR_SCRIPTS="${PLUGIN_DIR}/skills/addressing-qa-findings/scripts"
  EQ_SCRIPTS="${PLUGIN_DIR}/skills/executing-qa/scripts"
  FIN_SCRIPTS="${PLUGIN_DIR}/skills/finalizing-workflow/scripts"

  WS="${ORCH_SCRIPTS}/workflow-state.sh"
  QD="${ORCH_SCRIPTS}/qa-dispatch.sh"
  LOOP="${ADDR_SCRIPTS}/run-adopt-loop.sh"
  PRECHECK="${ADDR_SCRIPTS}/check-fix-prechecks.sh"
  DETECT_PHASE="${ADDR_SCRIPTS}/detect-phase.sh"
  COMMIT_ARTIFACT="${EQ_SCRIPTS}/commit-qa-artifact.sh"
  DETECT_REQA="${EQ_SCRIPTS}/detect-re-qa-mode.sh"

  FIXTURE_SRC="$(cd "${BATS_TEST_DIRNAME}/../../../fixtures/feat-032-known-buggy" && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  WORKDIR="${TMPDIR_TEST}/repo"
  cp -R "$FIXTURE_SRC" "$WORKDIR"

  cd "$WORKDIR"
  git init -q
  git config user.email "test@bats"
  git config user.name "Bats Test"
  git add -A
  git commit -q -m "init fixture"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- happy-path end-to-end --------------------------------------------------

@test "FEAT-032 NFR-4: full ISSUES-FOUND -> fix -> re-QA PASS -> adopt -> safety-net clean" {
  cd "$WORKDIR"

  # Step 1 — initial dispatch on ISSUES-FOUND must route to fix-phase
  # (the orchestrator does NOT advance directly to finalize).
  run --separate-stderr bash "$QD" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=fix-phase" ]

  # Step 2 — fix phase preconditions: clean tree + artifact present.
  run --separate-stderr bash "$PRECHECK" FEAT-999
  [ "$status" -eq 0 ]

  # Step 3 — fix phase auto-detects from the FR-4 state triple.
  run --separate-stderr bash "$DETECT_PHASE" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "phase=fix" ]

  # Step 4 — apply the production fix (mirrors what addressing-qa-findings
  # writes via Edit during a real fix-phase run). Then commit it.
  cat > src/buggy-fn.ts <<'EOF'
// FEAT-032 fixture: production fix applied during the fix phase. Trims input
// before the empty-string check so whitespace-only input is rejected.
export function validateInput(s: string): boolean {
  if (s.trim() === '') return false;
  return true;
}
EOF
  git add src/buggy-fn.ts
  git commit -q -m "fix(FEAT-999): reject whitespace-only input"

  # Increment the loop counter to record the fix attempt (orchestrator does
  # this via workflow-state.sh inc-qa-fix-attempts).
  run --separate-stderr bash "$WS" inc-qa-fix-attempts FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]

  # Step 5 — re-QA mode auto-detects (marker present + tracked QA file).
  run --separate-stderr bash "$DETECT_REQA" FEAT-999
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"re-qa"'* ]]
  [[ "$output" == *'tests/unit/qa-input-validation.test.ts'* ]]

  # Step 6 — re-QA result is PASS (the fix made the QA test green). Record
  # the verdict via workflow-state.sh.
  run --separate-stderr bash "$WS" set-qa-verdict FEAT-999 PASS
  [ "$status" -eq 0 ]

  # Step 7 — re-QA artifact-commit per FR-12. Touch the artifact so there is
  # something to stage (a real re-QA run rewrites it via render-qa-results.sh).
  printf '\n## Re-QA Results (attempt 1)\n\n**Verdict:** PASS\n' \
    >> qa/test-results/QA-results-FEAT-999.md
  run --separate-stderr bash "$COMMIT_ARTIFACT" FEAT-999 re-qa 1
  [ "$status" -eq 0 ]

  # Step 7a — verify the FR-12 verbatim commit message landed.
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-999): re-record QA results after fix attempt 1" ]

  # Step 7b — working tree clean post-commit per FR-12.
  [ -z "$(git status --porcelain)" ]

  # Step 8 — dispatch now routes to adopt-phase (PASS, qaFixAttempts > 0,
  # adoptedTests still empty).
  run --separate-stderr bash "$QD" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=adopt-phase" ]

  # Step 9 — detect-phase agrees we are in the adopt phase.
  run --separate-stderr bash "$DETECT_PHASE" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "phase=adopt" ]

  # Step 10 — run the adopt loop. It should print the new path on stdout
  # (FR-4 step 2.2 stream) and exit 0.
  run --separate-stderr bash "$LOOP"
  [ "$status" -eq 0 ]
  [ "$output" = "tests/unit/buggy-fn.qa.test.ts" ]

  # Step 10a — adopted file is on disk; original QA file is gone.
  [ -f "tests/unit/buggy-fn.qa.test.ts" ]
  [ ! -f "tests/unit/qa-input-validation.test.ts" ]

  # Step 10b — record the adoption in workflow-state and commit the move.
  run --separate-stderr bash "$WS" record-adopted-test FEAT-999 "tests/unit/buggy-fn.qa.test.ts"
  [ "$status" -eq 0 ]
  git commit -q -m "qa(adopt): FEAT-999 promote QA tests into regression suite"

  # Step 11 — final dispatch routes to advance (post-adopt PASS).
  run --separate-stderr bash "$QD" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=advance" ]

  # Step 12 — finalize safety-net would NOT trip: no tracked qa-* files match
  # the FR-9 v1 glob set after adoption.
  leaked="$(git ls-files \
    '**/qa-*.test.ts' \
    '**/qa-*.test.js' \
    '**/qa-*.bats' \
    '**/qa-*.py' \
    '**/qa-*.go' 2>/dev/null)"
  [ -z "$leaked" ]

  # Step 12a — adopted-sibling glob (the *.qa.* infix) is NOT matched by the
  # safety-net globs, so the adopted test passes through Edge Case 9.
  found_adopted="$(git ls-files 'tests/unit/buggy-fn.qa.test.ts' 2>/dev/null)"
  [ "$found_adopted" = "tests/unit/buggy-fn.qa.test.ts" ]
}

# --- contract pin: orchestrator does not skip addressing-qa-findings --------

@test "FEAT-032 NFR-4: dispatch never returns advance directly from ISSUES-FOUND" {
  cd "$WORKDIR"
  # The fixture seeds qaLastVerdict=ISSUES-FOUND, qaFixAttempts=0. dispatch
  # MUST route to fix-phase, not advance.
  run --separate-stderr bash "$QD" FEAT-999
  [ "$status" -eq 0 ]
  [ "$output" = "dispatch=fix-phase" ]
  [ "$output" != "dispatch=advance" ]
}

# --- contract pin: artifact commit message templates per FR-12 -------------

@test "FEAT-032 NFR-4: initial-mode artifact commit template lands verbatim" {
  cd "$WORKDIR"
  # Seed an artifact change so commit-qa-artifact has something to stage.
  printf '\nupdated\n' >> qa/test-results/QA-results-FEAT-999.md
  run --separate-stderr bash "$COMMIT_ARTIFACT" FEAT-999 initial
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-999): record QA results" ]
}

@test "FEAT-032 NFR-4: re-qa-mode artifact commit interpolates the attempt number" {
  cd "$WORKDIR"
  printf '\nupdated\n' >> qa/test-results/QA-results-FEAT-999.md
  run --separate-stderr bash "$COMMIT_ARTIFACT" FEAT-999 re-qa 2
  [ "$status" -eq 0 ]
  msg="$(git log -1 --pretty=%s)"
  [ "$msg" = "qa(FEAT-999): re-record QA results after fix attempt 2" ]
}
