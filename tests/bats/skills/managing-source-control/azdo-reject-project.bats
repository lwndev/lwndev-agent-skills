#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# BUG-021 adversarial QA: the pre-fix failure mode was `az repos pr show/update`
# rejecting `--project` with `unrecognized arguments: --project`. These tests
# install an `az` stub that HARD-FAILS (exit 2 + that exact stderr) the moment
# `--project` reaches a `show` or `update` invocation, then drive each fixed
# script end-to-end. A script that still passed `--project` would trip the
# oracle and the assertion `[ "$status" -eq 0 ]` would fail.
#
# `--project` is intentionally still ALLOWED on `list`/`create` (retain-site).
# Routing + backend-override dimensions confirm the GitHub path is untouched and
# the env override still selects the corrected argv.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  VIEW_PR="${SCRIPT_DIR}/view-pr.sh"
  MERGE_PR="${SCRIPT_DIR}/merge-pr.sh"
  PR_DIFF="${SCRIPT_DIR}/pr-diff.sh"

  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/qa-bug021.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  # git stub: satisfies branch lookup, fetch, and diff probes used by the three
  # scripts; everything else falls through to the real git.
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT}"
case "\$1" in
  rev-parse)
    if [ "\$2" = "--abbrev-ref" ] && [ "\$3" = "HEAD" ]; then
      echo "fix/BUG-021-test-branch"
      exit 0
    fi
    exec "\$REAL_GIT" "\$@"
    ;;
  fetch) exit 0 ;;
  diff)
    if [ "\$2" = "--name-only" ]; then echo "changed.txt"; exit 0; fi
    echo "--- stub diff ---"; exit 0
    ;;
  *) exec "\$REAL_GIT" "\$@" ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/git"

  # gh stub: GitHub-routing tests assert this is invoked instead of az. Records
  # invocation and returns a valid pr-view JSON shape.
  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
: > "${STUBDIR}/gh.invoked"
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  echo '{"number":42,"title":"t","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/o/r/pull/42","files":[]}'
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/gh"

  # az stub: hard-rejects --project on show/update (the pre-fix failure mode);
  # records argv; allows --project on list/create.
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
: > "${STUBDIR}/az.invoked"
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  echo "az repos pr help"; exit 0
fi
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then exit 0; fi

sub="\$3"
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && { [ "\$sub" = "show" ] || [ "\$sub" = "update" ]; }; then
  : > "${STUBDIR}/az.\${sub}.args"
  for a in "\$@"; do printf '%s\n' "\$a" >> "${STUBDIR}/az.\${sub}.args"; done
  # Adversarial oracle: the fix removed --project from show/update. If it ever
  # reappears, fail exactly as the real az CLI did pre-fix.
  for a in "\$@"; do
    if [ "\$a" = "--project" ]; then
      echo "ERROR: unrecognized arguments: --project" >&2
      exit 2
    fi
  done
  if [ "\$sub" = "update" ]; then
    echo '{"pullRequestId":42,"status":"completed"}'; exit 0
  fi
  # show: branch on query type (pr-diff asks for targetRefName).
  for a in "\$@"; do
    if [ "\$a" = "targetRefName" ]; then echo "refs/heads/main"; exit 0; fi
  done
  cat <<'JSONEOF'
{"pullRequestId":42,"title":"feat: BUG-021","status":"active","mergeStatus":"succeeded","_links":{"web":{"href":"https://dev.azure.com/contoso/myproject/_git/repo/pullrequest/42"}},"targetRefName":"refs/heads/main"}
JSONEOF
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  for _tool in bash dirname jq sed; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    [ -n "$_real" ] && ln -sf "$_real" "${STUBDIR}/${_tool}"
  done

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset SDLC_SCM_BACKEND
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# --- Dependency-failure dimension: pre-fix failure mode must never fire ---

# [P0] view-pr.sh: az show survives the reject-project oracle.
@test "BUG-021 QA: view-pr.sh az show passes when --project is rejected" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.show.args" ]
  ! grep -qF -- "--project" "${STUBDIR}/az.show.args"
  grep -qF -- "--id" "${STUBDIR}/az.show.args"
}

# [P0] merge-pr.sh: az update survives the reject-project oracle.
@test "BUG-021 QA: merge-pr.sh az update passes when --project is rejected" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.update.args" ]
  ! grep -qF -- "--project" "${STUBDIR}/az.update.args"
  grep -qF -- "completed" "${STUBDIR}/az.update.args"
}

# [P0] pr-diff.sh: az show (targetRefName query) survives the reject-project oracle.
@test "BUG-021 QA: pr-diff.sh az show passes when --project is rejected" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.show.args" ]
  ! grep -qF -- "--project" "${STUBDIR}/az.show.args"
  grep -qF -- "targetRefName" "${STUBDIR}/az.show.args"
}

# --- Cross-cutting: GitHub path untouched ---

# [P0] github.com origin routes view-pr to gh; az is never invoked.
@test "BUG-021 QA: github origin routes to gh, never touches az" {
  set_origin "https://github.com/owner/repo.git"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/gh.invoked" ]
  [ ! -f "${STUBDIR}/az.invoked" ]
}

# [P0] github.com origin routes merge-pr to gh; az is never invoked.
@test "BUG-021 QA: github origin routes merge to gh, never touches az" {
  set_origin "https://github.com/owner/repo.git"
  run bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/gh.invoked" ]
  [ ! -f "${STUBDIR}/az.invoked" ]
}

# --- Environment: SDLC_SCM_BACKEND override still selects corrected argv ---

# [P1] SDLC_SCM_BACKEND=azdo forces the az path; show still omits --project.
@test "BUG-021 QA: SDLC_SCM_BACKEND=azdo override keeps --project off az show" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  SDLC_SCM_BACKEND=azdo run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.show.args" ]
  ! grep -qF -- "--project" "${STUBDIR}/az.show.args"
}
