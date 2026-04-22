#!/usr/bin/env bats
# Bats fixture for finalize.sh (Phase 4 composition tests).
#
# Stubs every subscript (preflight-checks.sh, branch-id-parse.sh,
# resolve-requirement-doc.sh, check-idempotent.sh, checkbox-flip-all.sh,
# completion-upsert.sh, reconcile-affected-files.sh) and both `git` and `gh`
# via PATH shadowing + SKILL_DIR / PLUGIN_ROOT env overrides.
#
# Every stub logs its invocation to $TRACER so assertions can check which
# commands ran and in what order.

setup() {
  FIXTURE_DIR="$(mktemp -d)"
  SKILL_DIR="${FIXTURE_DIR}/skill"
  PLUGIN_SCRIPTS_DIR="${FIXTURE_DIR}/plugin-scripts"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$SKILL_DIR" "$PLUGIN_SCRIPTS_DIR" "$STUB_DIR"
  : > "$TRACER"

  # PLUGIN_ROOT is a fake root whose scripts/ dir we populate. The real
  # finalize.sh resolves PLUGIN_ROOT from SKILL_DIR/../../.., but we override
  # both via env so we don't need a matching directory layout.
  PLUGIN_ROOT="${FIXTURE_DIR}/plugin-root"
  mkdir -p "${PLUGIN_ROOT}/scripts"

  # Copy the real finalize.sh so it lives in SKILL_DIR for defaults, but we
  # override SKILL_DIR/PLUGIN_ROOT at invocation time regardless.
  REAL_SKILL_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FINALIZE="${REAL_SKILL_DIR}/finalize.sh"

  # Point subscript PLUGIN_ROOT at stub scripts dir via env.
  # finalize.sh calls ${PLUGIN_ROOT}/scripts/<name>.sh.
  # We put the stub scripts under ${PLUGIN_ROOT}/scripts.
  PLUGIN_SCRIPTS_DIR="${PLUGIN_ROOT}/scripts"
  mkdir -p "$PLUGIN_SCRIPTS_DIR"

  # Put stubs first on PATH; keep the rest of PATH intact so bash/awk/sed/mktemp
  # etc. still resolve.
  export PATH="${STUB_DIR}:${PATH}"
  export SKILL_DIR PLUGIN_ROOT TRACER
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- Stub writers ------------------------------------------------------

# Write a stub subscript (under SKILL_DIR or PLUGIN_SCRIPTS_DIR).
# Usage: write_subscript <dir> <name> <exit-code> [<stdout>] [<stderr>]
write_subscript() {
  local dir="$1" name="$2" rc="$3" stdout="${4:-}" stderr="${5:-}"
  cat > "${dir}/${name}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "TRACE:${name}:\$*" >> "${TRACER}"
if [ -n '${stdout}' ]; then printf '%s\n' '${stdout}'; fi
if [ -n '${stderr}' ]; then printf '%s\n' '${stderr}' >&2; fi
exit ${rc}
EOF
  chmod +x "${dir}/${name}"
}

# Convenience wrappers.
write_preflight() { write_subscript "$SKILL_DIR" "preflight-checks.sh" "$@"; }
write_idempotent() { write_subscript "$SKILL_DIR" "check-idempotent.sh" "$@"; }
write_completion_upsert() { write_subscript "$SKILL_DIR" "completion-upsert.sh" "$@"; }
write_reconcile() { write_subscript "$SKILL_DIR" "reconcile-affected-files.sh" "$@"; }
write_branch_parse() { write_subscript "$PLUGIN_SCRIPTS_DIR" "branch-id-parse.sh" "$@"; }
write_resolve_doc() { write_subscript "$PLUGIN_SCRIPTS_DIR" "resolve-requirement-doc.sh" "$@"; }
write_checkbox_flip() { write_subscript "$PLUGIN_SCRIPTS_DIR" "checkbox-flip-all.sh" "$@"; }

# Write a `git` stub. Tracks every invocation, returns configured exit codes
# for specific subcommands via env vars.
#   GIT_STATUS_PORCELAIN → printed by `git status --porcelain`
#   GIT_CONFIG_NAME / GIT_CONFIG_EMAIL → printed by `git config user.name/email`
#   GIT_PUSH_RC          → exit code for `git push` (default 0)
#   GIT_CHECKOUT_RC      → exit code for `git checkout` (default 0)
#   GIT_FETCH_RC         → exit code for `git fetch` (default 0)
#   GIT_PULL_RC          → exit code for `git pull` (default 0)
write_git_stub() {
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "TRACE:git:\$*" >> "${TRACER}"
case "\$1" in
  status)
    if [ "\$2" = "--porcelain" ]; then
      printf '%s' "\${GIT_STATUS_PORCELAIN:-}"
      exit 0
    fi
    ;;
  add)          exit 0 ;;
  config)
    case "\$2" in
      user.name)  printf '%s' "\${GIT_CONFIG_NAME-Test User}"; exit 0 ;;
      user.email) printf '%s' "\${GIT_CONFIG_EMAIL-test@example.com}"; exit 0 ;;
    esac
    exit 0
    ;;
  commit)       exit 0 ;;
  rev-parse)
    if [ "\$2" = "--short" ] && [ "\$3" = "HEAD" ]; then
      printf '%s' "\${GIT_REV_SHORT-abc1234}"
      exit 0
    fi
    exit 0
    ;;
  push)
    if [ "\${GIT_PUSH_RC:-0}" -ne 0 ]; then
      echo "push failed" >&2
    fi
    exit "\${GIT_PUSH_RC:-0}"
    ;;
  checkout)
    if [ "\${GIT_CHECKOUT_RC:-0}" -ne 0 ]; then
      echo "checkout failed" >&2
    fi
    exit "\${GIT_CHECKOUT_RC:-0}"
    ;;
  fetch)
    if [ "\${GIT_FETCH_RC:-0}" -ne 0 ]; then
      echo "fetch failed" >&2
    fi
    exit "\${GIT_FETCH_RC:-0}"
    ;;
  pull)
    if [ "\${GIT_PULL_RC:-0}" -ne 0 ]; then
      echo "pull failed" >&2
    fi
    exit "\${GIT_PULL_RC:-0}"
    ;;
  revert|reset)
    # Log loudly to tracer for no-rollback assertions.
    printf '%s\n' "TRACE:git-forbidden:\$*" >> "${TRACER}"
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
}

# Write a `gh` stub. GH_MERGE_RC controls `gh pr merge` exit.
write_gh_stub() {
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "TRACE:gh:\$*" >> "${TRACER}"
if [ "\$1" = "pr" ] && [ "\$2" = "merge" ]; then
  if [ "\${GH_MERGE_RC:-0}" -ne 0 ]; then
    echo "merge failed" >&2
  fi
  exit "\${GH_MERGE_RC:-0}"
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

# Default happy-path stub setup for feature branches.
setup_happy_path() {
  write_preflight 0 '{"status":"ok","prNumber":142,"prTitle":"feat: thing","prUrl":"https://github.com/foo/bar/pull/142"}'
  write_branch_parse 0 '{"id":"FEAT-022","type":"feature","dir":"requirements/features"}'
  write_resolve_doc 0 "/tmp/does-not-exist-but-not-touched.md"
  write_idempotent 1 "" "[info] idempotent check failed: acceptance-criteria-unticked"
  write_checkbox_flip 0 "checked 3 lines"
  write_completion_upsert 0 "appended"
  write_reconcile 0 "2 1"
  write_git_stub
  write_gh_stub
}

# ---------- Test cases --------------------------------------------------------

@test "1. missing arg → exit 2 with usage" {
  setup_happy_path
  run bash "$FINALIZE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: finalize.sh <branch-name>"* ]]
}

@test "2. preflight abort → exit 1, stderr propagated, no merge/parse" {
  write_preflight 1 '{"status":"abort","reason":"working directory has uncommitted changes"}' '[error] preflight: working directory has uncommitted changes'
  # Other subscripts shouldn't be invoked.
  write_branch_parse 0 '{"id":"FEAT-022","type":"feature","dir":"requirements/features"}'
  write_gh_stub
  write_git_stub

  run bash "$FINALIZE" "feat/FEAT-022-foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"working directory has uncommitted changes"* ]]

  # Tracer should NOT contain branch-id-parse or gh pr merge.
  run grep -F "TRACE:branch-id-parse.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:gh:pr merge" "$TRACER"
  [ "$status" -ne 0 ]
}

@test "3. unexpected preflight exit → exit 1 with [error] unexpected exit 99" {
  write_preflight 99 "" "garbage"
  write_gh_stub
  write_git_stub

  run bash "$FINALIZE" "feat/FEAT-022-foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] unexpected exit 99 from preflight-checks.sh"* ]]
}

@test "4. release branch → no BK subscripts, merge + checkout + fetch + pull run" {
  write_preflight 0 '{"status":"ok","prNumber":143,"prTitle":"release(lwndev-sdlc): v1.16.0","prUrl":"https://github.com/foo/bar/pull/143"}'
  write_branch_parse 0 '{"id":null,"type":"release","dir":null}'
  # BK stubs exist but should not be called.
  write_resolve_doc 0 "/tmp/shouldnt-be-called.md"
  write_idempotent 0 ""
  write_checkbox_flip 0 "checked 0 lines"
  write_completion_upsert 0 "appended"
  write_reconcile 0 "0 0"
  write_git_stub
  write_gh_stub

  run bash "$FINALIZE" "release/lwndev-sdlc-v1.16.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bookkeeping: skipped (release branch)"* ]]
  [[ "$output" == *"Merged PR #143"* ]]
  [[ "$output" == *"On main, up to date"* ]]

  # Must NOT carry branch-pattern info/warn messages on stderr.
  # (bats `$output` combines stdout+stderr by default.)
  run bash -c "bash '$FINALIZE' 'release/lwndev-sdlc-v1.16.0' 2>/tmp/finalize.err >/dev/null"
  [ "$status" -eq 0 ]
  err_content="$(cat /tmp/finalize.err)"
  [[ "$err_content" != *"does not match workflow ID pattern"* ]]
  rm -f /tmp/finalize.err

  # Tracer: must show gh pr merge, git checkout, git fetch, git pull.
  grep -F "TRACE:gh:pr merge" "$TRACER"
  grep -F "TRACE:git:checkout main" "$TRACER"
  grep -F "TRACE:git:fetch origin" "$TRACER"
  grep -F "TRACE:git:pull" "$TRACER"

  # Must NOT show any bookkeeping subscripts.
  run grep -F "TRACE:resolve-requirement-doc.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:check-idempotent.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:checkbox-flip-all.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:completion-upsert.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:reconcile-affected-files.sh" "$TRACER"
  [ "$status" -ne 0 ]
}

@test "5. unrecognized branch → canonical info, merge runs, no BK subscripts" {
  write_preflight 0 '{"status":"ok","prNumber":144,"prTitle":"adhoc","prUrl":"https://github.com/foo/bar/pull/144"}'
  write_branch_parse 1 "" "error: branch name does not match any work-item pattern"
  write_resolve_doc 0 "/tmp/unused.md"
  write_idempotent 0 ""
  write_git_stub
  write_gh_stub

  run bash -c "bash '$FINALIZE' 'adhoc/cleanup' 2>/tmp/finalize.err"
  [ "$status" -eq 0 ]
  err_content="$(cat /tmp/finalize.err)"
  [[ "$err_content" == *"[info] Branch adhoc/cleanup does not match workflow ID pattern; skipping bookkeeping."* ]]
  rm -f /tmp/finalize.err

  # BK subscripts never called.
  run grep -F "TRACE:resolve-requirement-doc.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:check-idempotent.sh" "$TRACER"
  [ "$status" -ne 0 ]

  # Merge did run.
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "6. idempotent skip → BK-4/BK-5 never invoked, merge runs" {
  write_preflight 0 '{"status":"ok","prNumber":145,"prTitle":"chore(CHORE-040): x","prUrl":"https://github.com/foo/bar/pull/145"}'
  write_branch_parse 0 '{"id":"CHORE-040","type":"chore","dir":"requirements/chores"}'
  write_resolve_doc 0 "/tmp/chore-040.md"
  write_idempotent 0 ""
  # These stubs exist but must NOT be invoked.
  write_checkbox_flip 0 "checked 0 lines"
  write_completion_upsert 0 "upserted"
  write_reconcile 0 "0 0"
  write_git_stub
  write_gh_stub

  run bash "$FINALIZE" "chore/CHORE-040-flake"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bookkeeping: skipped (requirement doc already finalized)"* ]]
  [[ "$output" == *"Merged PR #145"* ]]
  [[ "$output" == *"On main, up to date"* ]]

  # BK-4/5 subscripts NOT called.
  run grep -F "TRACE:checkbox-flip-all.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:completion-upsert.sh" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -F "TRACE:reconcile-affected-files.sh" "$TRACER"
  [ "$status" -ne 0 ]

  # Merge did run.
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "7. happy path full BK → full summary emitted" {
  setup_happy_path
  # Ensure git sees a dirty doc so BK-5 commits.
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  export GIT_REV_SHORT="deadbee"

  run bash "$FINALIZE" "feat/FEAT-022-finalize-sh-subscripts"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Merged PR #142 — feat: thing"* ]]
  [[ "$output" == *"Bookkeeping: ticked 3 acceptance criteria"* ]]
  [[ "$output" == *"wrote Completion section (appended)"* ]]
  [[ "$output" == *"reconciled 2 new + 1 annotated affected files"* ]]
  [[ "$output" == *"Pushed bookkeeping commit as deadbee"* ]]
  [[ "$output" == *"On main, up to date"* ]]

  # All BK subscripts were invoked.
  grep -F "TRACE:check-idempotent.sh" "$TRACER"
  grep -F "TRACE:checkbox-flip-all.sh" "$TRACER"
  grep -F "TRACE:completion-upsert.sh" "$TRACER"
  grep -F "TRACE:reconcile-affected-files.sh" "$TRACER"
  grep -F "TRACE:git:commit" "$TRACER"
  grep -F "TRACE:git:push" "$TRACER"
  grep -F "TRACE:gh:pr merge" "$TRACER"
}

@test "8. reconcile exit 1 non-fatal → BK-5 still runs, finalize exit 0" {
  write_preflight 0 '{"status":"ok","prNumber":146,"prTitle":"feat: x","prUrl":"https://github.com/foo/bar/pull/146"}'
  write_branch_parse 0 '{"id":"FEAT-050","type":"feature","dir":"requirements/features"}'
  write_resolve_doc 0 "/tmp/feat-050.md"
  write_idempotent 1 "" "[info] idempotent check failed: completion-section-missing"
  write_checkbox_flip 0 "checked 2 lines"
  write_completion_upsert 0 "appended"
  write_reconcile 1 "" "[warn] reconcile-affected-files: gh failure — network blip"
  write_git_stub
  write_gh_stub
  export GIT_STATUS_PORCELAIN=" M /tmp/feat-050.md"

  run bash -c "bash '$FINALIZE' 'feat/FEAT-050-x' 2>/tmp/finalize.err"
  [ "$status" -eq 0 ]
  err_content="$(cat /tmp/finalize.err)"
  [[ "$err_content" == *"[warn] reconcile-affected-files: gh failure"* ]]
  rm -f /tmp/finalize.err

  # BK-5 still ran.
  grep -F "TRACE:git:commit" "$TRACER"
  grep -F "TRACE:git:push" "$TRACER"
}

@test "9. BK-5 push failure → exit 1, gh pr merge NEVER called" {
  setup_happy_path
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  export GIT_PUSH_RC=1

  run bash "$FINALIZE" "feat/FEAT-022-thing"
  [ "$status" -eq 1 ]

  # Merge must not have been attempted.
  run grep -F "TRACE:gh:pr merge" "$TRACER"
  [ "$status" -ne 0 ]
}

@test "10. merge failure after BK-5 → exit 1, NO-ROLLBACK asserted" {
  setup_happy_path
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  export GH_MERGE_RC=1

  run bash "$FINALIZE" "feat/FEAT-022-thing"
  [ "$status" -eq 1 ]

  # NO-ROLLBACK: must not call git revert or git reset --hard.
  run grep -F "TRACE:git-forbidden:" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -E "TRACE:git:revert" "$TRACER"
  [ "$status" -ne 0 ]
  run grep -E "TRACE:git:reset --hard" "$TRACER"
  [ "$status" -ne 0 ]
}

@test "11. unexpected subscript exit (completion-upsert returns 42) → error line names the script" {
  write_preflight 0 '{"status":"ok","prNumber":147,"prTitle":"feat: y","prUrl":"https://github.com/foo/bar/pull/147"}'
  write_branch_parse 0 '{"id":"FEAT-060","type":"feature","dir":"requirements/features"}'
  write_resolve_doc 0 "/tmp/feat-060.md"
  write_idempotent 1 "" "[info] idempotent check failed: acceptance-criteria-unticked"
  write_checkbox_flip 0 "checked 1 lines"
  write_completion_upsert 42 "" "weird failure"
  write_reconcile 0 "0 0"
  write_git_stub
  write_gh_stub

  run bash "$FINALIZE" "feat/FEAT-060-y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] unexpected exit 42 from completion-upsert.sh"* ]]
}

@test "12. post-merge fetch/pull failure → exit 0 with [warn]" {
  setup_happy_path
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  export GIT_FETCH_RC=1

  run bash -c "bash '$FINALIZE' 'feat/FEAT-022-z' 2>/tmp/finalize.err"
  [ "$status" -eq 0 ]
  err_content="$(cat /tmp/finalize.err)"
  [[ "$err_content" == *"[warn] git fetch failed:"* ]]
  rm -f /tmp/finalize.err
}

@test "12b. git pull failure → exit 0 with [warn] git pull failed" {
  setup_happy_path
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  export GIT_PULL_RC=1

  run bash -c "bash '$FINALIZE' 'feat/FEAT-022-zz' 2>/tmp/finalize.err"
  [ "$status" -eq 0 ]
  err_content="$(cat /tmp/finalize.err)"
  [[ "$err_content" == *"[warn] git pull failed:"* ]]
  rm -f /tmp/finalize.err
}

@test "13. git identity not configured → BK-5 exit 1, merge not attempted" {
  setup_happy_path
  export GIT_STATUS_PORCELAIN=" M /tmp/doc.md"
  # Unset identity via empty env values.
  export GIT_CONFIG_NAME=""
  export GIT_CONFIG_EMAIL=""

  run bash "$FINALIZE" "feat/FEAT-022-ww"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[error] git identity not configured"* ]]

  # Merge not attempted.
  run grep -F "TRACE:gh:pr merge" "$TRACER"
  [ "$status" -ne 0 ]
}
