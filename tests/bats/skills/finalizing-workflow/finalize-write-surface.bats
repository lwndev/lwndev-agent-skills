#!/usr/bin/env bats

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# finalize-write-surface.bats — Integration regression for the BUG-024 pre-merge
# write-surface guard wired into finalize.sh.
#
# Unlike finalize.bats (which PATH-shadows `git` with a stub), these tests run
# against a REAL temp git repo so finalize.sh's own `arm-baseline.sh` (rev-parse)
# and `check-write-surface.sh` (git diff) execute for real. Only the subscripts
# (preflight, branch-parse, resolve-doc, idempotent) are stubbed via SKILL_DIR /
# PLUGIN_ROOT overrides. The merge dispatcher is never reached on the block path
# and is therefore not stubbed.
#
# Scenario mirrors the production bug: run 1 arms a clean baseline and is blocked
# at pre-flight; the model then commits an out-of-surface mutation; run 2 reuses
# the original baseline and the pre-merge guard blocks the merge.

setup() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git symbolic-ref HEAD refs/heads/main 2>/dev/null || true

  mkdir -p tests/unit requirements/bugs
  echo "qa content" > tests/unit/qa-BUG-019-advance-pause.test.ts
  echo "req doc" > requirements/bugs/BUG-019-some-bug.md
  git add .
  git commit -q -m "initial"
  # Feature branch the fork finalizes from.
  git checkout -q -b fix/BUG-019-x
  CLEAN_SHA="$(git rev-parse HEAD)"

  # Stub dirs. finalize.sh looks up subscripts under SKILL_DIR and PLUGIN_ROOT.
  SKILL_DIR="${REPO}/skill"
  PLUGIN_ROOT="${REPO}/plugin-root"
  mkdir -p "$SKILL_DIR" "${PLUGIN_ROOT}/scripts"

  # Real guard scripts under the stubbed SKILL_DIR.
  REAL_SCRIPTS="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/finalizing-workflow/scripts" && pwd)"
  cp "${REAL_SCRIPTS}/arm-baseline.sh" "${SKILL_DIR}/arm-baseline.sh"
  cp "${REAL_SCRIPTS}/check-write-surface.sh" "${SKILL_DIR}/check-write-surface.sh"
  FINALIZE="${REAL_SCRIPTS}/finalize.sh"

  export SKILL_DIR PLUGIN_ROOT
}

teardown() {
  if [ -n "${REPO:-}" ] && [ -d "$REPO" ]; then
    rm -rf "$REPO"
  fi
}

write_stub() {
  local path="$1" rc="$2" stdout="${3:-}"
  cat > "$path" <<EOF
#!/usr/bin/env bash
if [ -n '${stdout}' ]; then printf '%s\n' '${stdout}'; fi
exit ${rc}
EOF
  chmod +x "$path"
}

# Preflight passes; bookkeeping short-circuits via idempotent skip so no BK-5
# commit is made — the guard sees only what the test commits.
stub_passthrough() {
  write_stub "${SKILL_DIR}/preflight-checks.sh" 0 '{"status":"ok","prNumber":144,"prTitle":"fix: x","prUrl":"https://github.com/foo/bar/pull/144"}'
  write_stub "${PLUGIN_ROOT}/scripts/branch-id-parse.sh" 0 '{"id":"BUG-019","type":"bug","dir":"requirements/bugs"}'
  write_stub "${PLUGIN_ROOT}/scripts/resolve-requirement-doc.sh" 0 "requirements/bugs/BUG-019-some-bug.md"
  write_stub "${SKILL_DIR}/check-idempotent.sh" 0 ""
}

@test "1. run 2 reuses clean baseline; committed git rm blocks the merge (exit 1)" {
  stub_passthrough
  cd "$REPO"

  # Run 1 armed a clean baseline before the block.
  echo "$CLEAN_SHA" > .git/sdlc-finalize-baseline-BUG-019

  # Model's out-of-surface overreach between runs.
  git rm -q tests/unit/qa-BUG-019-advance-pause.test.ts
  git commit -q -m "chore: remove qa file to dodge preflight"

  run bash "$FINALIZE" "fix/BUG-019-x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"write-surface guard"* ]]
  [[ "$output" == *"tests/unit/qa-BUG-019-advance-pause.test.ts"* ]]

  # Never left the feature branch (no merge/checkout happened).
  [ "$(git rev-parse --abbrev-ref HEAD)" = "fix/BUG-019-x" ]
  # Baseline marker is retained for the post-revert re-run.
  [ -f .git/sdlc-finalize-baseline-BUG-019 ]
  [ "$(cat .git/sdlc-finalize-baseline-BUG-019)" = "$CLEAN_SHA" ]
}

@test "2. clean tree past baseline → guard passes, finalize merges, baseline cleaned up" {
  stub_passthrough
  cd "$REPO"
  echo "$CLEAN_SHA" > .git/sdlc-finalize-baseline-BUG-019

  # Stub the merge dispatcher reached after the guard. CLAUDE_PLUGIN_ROOT points
  # nowhere so finalize.sh falls back to the PLUGIN_ROOT dispatcher path.
  export CLAUDE_PLUGIN_ROOT="${REPO}/noplugin"
  mkdir -p "${PLUGIN_ROOT}/skills/managing-source-control/scripts"
  write_stub "${PLUGIN_ROOT}/skills/managing-source-control/scripts/merge-pr.sh" 0 ""

  # No out-of-surface change past the baseline → guard is clean, merge proceeds.
  # (git fetch/pull fail non-fatally on this origin-less repo — exit 0 either way.)
  run bash "$FINALIZE" "fix/BUG-019-x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged PR #144"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
  # Baseline marker removed on success so the next finalize re-arms.
  [ ! -e .git/sdlc-finalize-baseline-BUG-019 ]
}

# A legitimate post-block fix (QA adoption git mv) made AFTER the persisted
# baseline is flagged by the guard — the capture-if-absent staleness tradeoff.
# The guard must direct the fork to escalate, NOT to self-bypass.
@test "3. legitimate adoption past a stale baseline is flagged; guard says escalate, not bypass" {
  stub_passthrough
  cd "$REPO"
  echo "$CLEAN_SHA" > .git/sdlc-finalize-baseline-BUG-019

  # Operator adopts the orphan qa-* file (the documented correct fix).
  git mv tests/unit/qa-BUG-019-advance-pause.test.ts tests/unit/advance-pause.qa.test.ts
  git commit -q -m "test: adopt qa file"

  run bash "$FINALIZE" "fix/BUG-019-x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"write-surface guard"* ]]
  [[ "$output" == *"stop and report"* ]]
  # Must NOT print a mechanical baseline-deletion bypass command.
  [[ "$output" != *"rm .git/sdlc-finalize"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "fix/BUG-019-x" ]
}

# Documented human recovery: clear the stale baseline, re-run → re-arms fresh at
# the post-fix tip, guard passes, finalize completes.
@test "4. recovery: clearing the stale baseline lets the legitimate re-run proceed" {
  stub_passthrough
  cd "$REPO"
  echo "$CLEAN_SHA" > .git/sdlc-finalize-baseline-BUG-019
  git mv tests/unit/qa-BUG-019-advance-pause.test.ts tests/unit/advance-pause.qa.test.ts
  git commit -q -m "test: adopt qa file"

  export CLAUDE_PLUGIN_ROOT="${REPO}/noplugin"
  mkdir -p "${PLUGIN_ROOT}/skills/managing-source-control/scripts"
  write_stub "${PLUGIN_ROOT}/skills/managing-source-control/scripts/merge-pr.sh" 0 ""

  # Human recovery action: drop the stale baseline so the re-run re-arms fresh.
  rm -f .git/sdlc-finalize-baseline-BUG-019

  run bash "$FINALIZE" "fix/BUG-019-x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged PR #144"* ]]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
}
