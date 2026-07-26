#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# BUG-021 regression: az repos pr update must NOT receive --project.
# Complements merge-pr.bats; uses the same stubbing convention.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  MERGE_PR="${SCRIPT_DIR}/merge-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-merge-pr-qa.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
exec "${REAL_GIT}" "\$@"
STUBEOF
  chmod +x "${STUBDIR}/git"

  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
exit 0
STUBEOF
  chmod +x "${STUBDIR}/gh"

  # az stub: records argv for pr update invocations.
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  echo "az repos pr help"
  exit 0
fi
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "update" ]; then
  : > "${STUBDIR}/az.update.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.update.args"
  done
  echo '{"pullRequestId":42,"status":"completed"}'
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  for _tool in bash dirname jq; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
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

# RC-2: az repos pr update must NOT receive --project (BUG-021).
@test "BUG-021 RC-2: az repos pr update does not receive --project token" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.update.args" ]
  # --project must not appear in the update invocation.
  ! grep -qF -- "--project" "${STUBDIR}/az.update.args"
  # --organization must still be present.
  grep -qF -- "--organization" "${STUBDIR}/az.update.args"
  # --status completed must be present.
  grep -qF -- "completed" "${STUBDIR}/az.update.args"
}
