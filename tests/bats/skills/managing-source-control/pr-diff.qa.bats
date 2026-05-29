#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# BUG-021 regression: az repos pr show (--query targetRefName) must NOT receive
# --project when called from pr-diff.sh.
# Complements pr-diff.bats; uses the same stubbing convention.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_DIFF="${SCRIPT_DIR}/pr-diff.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-pr-diff-qa.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT}"
case "\$1" in
  fetch)
    exit 0
    ;;
  diff)
    echo "--- stub git diff output ---"
    exit 0
    ;;
  *)
    exec "\$REAL_GIT" "\$@"
    ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/git"

  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
exit 0
STUBEOF
  chmod +x "${STUBDIR}/gh"

  # az stub: records argv for pr show invocations; returns a base ref.
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  echo "az repos pr help"
  exit 0
fi
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "show" ]; then
  : > "${STUBDIR}/az.show.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.show.args"
  done
  echo "refs/heads/main"
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

# RC-3: az repos pr show (targetRefName query) must NOT receive --project (BUG-021).
@test "BUG-021 RC-3: az repos pr show (pr-diff base-ref) does not receive --project" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.show.args" ]
  # --project must not appear in the show invocation.
  ! grep -qF -- "--project" "${STUBDIR}/az.show.args"
  # --organization must still be present.
  grep -qF -- "--organization" "${STUBDIR}/az.show.args"
  # Verify the targetRefName query was issued.
  grep -qF -- "targetRefName" "${STUBDIR}/az.show.args"
}
