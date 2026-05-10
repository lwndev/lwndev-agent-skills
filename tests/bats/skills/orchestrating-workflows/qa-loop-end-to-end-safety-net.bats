#!/usr/bin/env bats
# End-to-end NFR-4 negative-variant: confirms the FR-9 safety-net trips when
# the adopt phase is skipped. Same fixture as qa-loop-end-to-end.bats; the
# only difference is that this test does NOT call run-adopt-loop.sh, so the
# committed qa-input-validation.test.ts file remains tracked and the FR-9
# safety-net check in preflight-checks.sh blocks merge.
#
# This driver invokes preflight-checks.sh with stubbed gh + npm so the FR-9
# subshell gate is the only failing surface. The git ls-files call against
# the real fixture working tree returns the leaked qa-* file; the verbatim
# error message text is asserted per FR-9.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc" && pwd)"
  ORCH_SCRIPTS="${PLUGIN_DIR}/skills/orchestrating-workflows/scripts"
  ADDR_SCRIPTS="${PLUGIN_DIR}/skills/addressing-qa-findings/scripts"
  EQ_SCRIPTS="${PLUGIN_DIR}/skills/executing-qa/scripts"
  FIN_SCRIPTS="${PLUGIN_DIR}/skills/finalizing-workflow/scripts"

  WS="${ORCH_SCRIPTS}/workflow-state.sh"
  QD="${ORCH_SCRIPTS}/qa-dispatch.sh"
  PRECHECK="${ADDR_SCRIPTS}/check-fix-prechecks.sh"
  COMMIT_ARTIFACT="${EQ_SCRIPTS}/commit-qa-artifact.sh"
  PREFLIGHT="${FIN_SCRIPTS}/preflight-checks.sh"

  FIXTURE_SRC="$(cd "${BATS_TEST_DIRNAME}/../../../fixtures/feat-032-known-buggy" && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  WORKDIR="${TMPDIR_TEST}/repo"
  cp -R "$FIXTURE_SRC" "$WORKDIR"

  # The fixture's .gitignore matches `.sdlc/workflows/`, so the workflow-state
  # seed cannot live there in the source tree (CI would never see it). Stage
  # it from the tracked seed/ directory into the runtime path before git init.
  mkdir -p "${WORKDIR}/.sdlc/workflows"
  mv "${WORKDIR}/seed/FEAT-999-state.json" "${WORKDIR}/.sdlc/workflows/FEAT-999.json"
  rmdir "${WORKDIR}/seed"

  cd "$WORKDIR"
  git init -q
  git config user.email "test@bats"
  git config user.name "Bats Test"
  git add -A
  git commit -q -m "init fixture"

  # Stubs for gh + npm so preflight-checks.sh reaches the FR-9 gate without
  # tripping on the earlier checks. We stub only these two binaries; git is
  # NOT stubbed because we want git ls-files to return the real leaked file.
  STUB_DIR="${TMPDIR_TEST}/stubs"
  mkdir -p "$STUB_DIR"
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '{"number":99,"title":"Test PR","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/foo/bar/pull/99"}\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
  cat > "${STUB_DIR}/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/npm"
  export PATH="${STUB_DIR}:${PATH}"

  # Establish a feature-like branch so preflight branch check passes.
  git checkout -q -b feat/FEAT-999-fixture
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# --- negative variant -------------------------------------------------------

@test "FEAT-032 NFR-4 negative: skipping adopt leaves qa-* file -> safety-net trips with FR-9 verbatim message" {
  cd "$WORKDIR"

  # Drive the loop to the point where adopt would normally run, then SKIP it.
  # Apply the production fix and commit it.
  cat > src/buggy-fn.ts <<'EOF'
export function validateInput(s: string): boolean {
  if (s.trim() === '') return false;
  return true;
}
EOF
  git add src/buggy-fn.ts
  git commit -q -m "fix(FEAT-999): reject whitespace-only input"

  # Increment counter and flip verdict to PASS.
  bash "$WS" inc-qa-fix-attempts FEAT-999 >/dev/null
  bash "$WS" set-qa-verdict FEAT-999 PASS >/dev/null

  # Re-QA artifact-commit lands so the working tree is clean. (Do NOT then
  # call run-adopt-loop.sh; this is the variant where adoption is skipped.)
  printf '\n## Re-QA Results (attempt 1)\n\n**Verdict:** PASS\n' \
    >> qa/test-results/QA-results-FEAT-999.md
  bash "$COMMIT_ARTIFACT" FEAT-999 re-qa 1 >/dev/null

  # Pre-condition: the QA file is still tracked because we skipped adopt.
  leaked="$(git ls-files \
    'tests/unit/qa-*.test.ts' \
    'tests/unit/qa-*.test.js' \
    'tests/bats/qa/qa-*.bats' 2>/dev/null)"
  [ -n "$leaked" ]
  echo "$leaked" | grep -qxF "tests/unit/qa-input-validation.test.ts"

  # Run preflight-checks.sh. The FR-9 safety-net subshell is the last gate
  # and must trip with the verbatim error message naming the leaked file.
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'QA test files were not adopted; the addressing-qa-findings skill did not complete cleanly:'* ]]
  [[ "$output" == *'tests/unit/qa-input-validation.test.ts'* ]]
  [[ "$output" == *'Resolve by running addressing-qa-findings to adoption, or manually adopting/deleting these files.'* ]]
}

# --- positive control: after adoption the safety-net does NOT trip ---------

@test "FEAT-032 NFR-4 positive control: completing adopt leaves no qa-* files -> safety-net passes" {
  cd "$WORKDIR"
  LOOP="${ADDR_SCRIPTS}/run-adopt-loop.sh"

  # Apply fix.
  cat > src/buggy-fn.ts <<'EOF'
export function validateInput(s: string): boolean {
  if (s.trim() === '') return false;
  return true;
}
EOF
  git add src/buggy-fn.ts
  git commit -q -m "fix(FEAT-999): reject whitespace-only input"

  bash "$WS" inc-qa-fix-attempts FEAT-999 >/dev/null
  bash "$WS" set-qa-verdict FEAT-999 PASS >/dev/null
  printf '\n## Re-QA Results (attempt 1)\n\n**Verdict:** PASS\n' \
    >> qa/test-results/QA-results-FEAT-999.md
  bash "$COMMIT_ARTIFACT" FEAT-999 re-qa 1 >/dev/null

  # Run the adopt loop and commit the result.
  run bash "$LOOP"
  [ "$status" -eq 0 ]
  bash "$WS" record-adopted-test FEAT-999 "tests/unit/buggy-fn.qa.test.ts" >/dev/null
  git commit -q -m "qa(adopt): FEAT-999 promote QA tests into regression suite"

  # Now preflight-checks.sh must NOT trip the FR-9 gate.
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" != *'QA test files were not adopted'* ]]
}
