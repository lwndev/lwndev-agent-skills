#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load "${BATS_TEST_DIRNAME%/tests/bats/*}/tests/bats/helpers/git-env"

# BUG-021 regression: az repos pr show must NOT receive --project.
# az repos pr list (branch lookup) MUST still receive --project (RC-4).
# Complements view-pr.bats; uses the same stubbing convention.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  VIEW_PR="${SCRIPT_DIR}/view-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-view-pr-qa.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT}"
case "\$1" in
  rev-parse)
    if [ "\$2" = "--abbrev-ref" ] && [ "\$3" = "HEAD" ]; then
      echo "feat/test-branch"
      exit 0
    fi
    exec "\$REAL_GIT" "\$@"
    ;;
  fetch)
    exit 0
    ;;
  diff)
    if [ "\$2" = "--name-only" ]; then
      echo "changed.txt"
      exit 0
    fi
    exec "\$REAL_GIT" "\$@"
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

  # az stub: records argv for inspection; handles repos pr -h, account show,
  # repos pr list (branch lookup), and repos pr show.
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  echo "az repos pr help"
  exit 0
fi
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "list" ]; then
  # Record argv so tests can assert --project is passed to list.
  : > "${STUBDIR}/az.list.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.list.args"
  done
  echo "42"
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "show" ]; then
  # Record argv so tests can assert --project is NOT passed to show.
  : > "${STUBDIR}/az.show.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.show.args"
  done
  cat <<'JSONEOF'
{"pullRequestId":42,"title":"feat: BUG-021 test PR","status":"active","mergeStatus":"succeeded","_links":{"web":{"href":"https://dev.azure.com/contoso/myproject/_git/repo/pullrequest/42"}},"targetRefName":"refs/heads/main"}
JSONEOF
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

# RC-1: az repos pr show must NOT receive --project (BUG-021).
@test "BUG-021 RC-1: az repos pr show does not receive --project token" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.show.args" ]
  # --project must not appear in the show invocation.
  ! grep -qF -- "--project" "${STUBDIR}/az.show.args"
  # --organization must still be present.
  grep -qF -- "--organization" "${STUBDIR}/az.show.args"
  # --id must be present.
  grep -qF -- "--id" "${STUBDIR}/az.show.args"
}

# RC-1 (b): view-pr.sh emits normalized JSON (not [warn]) on stubbed show success.
@test "BUG-021 RC-1: view-pr.sh emits normalized PR JSON on successful az show" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  # Normalized JSON shape (FR-5 transform) — no [warn] line.
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"mergeable":"MERGEABLE"'* ]]
  [[ "$stderr" != *"[warn] az repos pr show failed"* ]]
}

# RC-4: az repos pr list (branch-lookup path) MUST still receive --project.
@test "BUG-021 RC-4: az repos pr list still receives --project token" {
  set_origin "https://dev.azure.com/contoso/myproject/_git/repo"
  # Call without a PR number to trigger the branch-lookup (list) path.
  run bash "$VIEW_PR"
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.list.args" ]
  grep -qF -- "--project" "${STUBDIR}/az.list.args"
}
