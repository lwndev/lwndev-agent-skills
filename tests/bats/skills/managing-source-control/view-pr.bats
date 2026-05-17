#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/view-pr.sh (FEAT-033
# Phases 3 + 4).
#
# Strategy: PATH-prepend stubs for `git` (pass through, with fetch/diff
# interceptors for the AzDO files-reconstruction path), `gh` (emit fixed
# JSON for `pr view`), and `az` (emit native PR object for `pr show`).
#
# Coverage:
#   - GitHub path: success with PR number / no PR number; missing gh; not
#     authenticated; gh pr view failure.
#   - Azure DevOps path: success with normalized JSON shape (FR-5); resolves
#     PR id by branch when no arg; NFR-1 skips (missing az, missing devops
#     extension, missing auth, az repos pr show failure).
#   - Unrecognized origin → [info] skip.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  VIEW_PR="${SCRIPT_DIR}/view-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-view-pr.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  # Fake `git`: pass through but intercept `rev-parse --abbrev-ref HEAD`
  # (deterministic branch name for the az-path branch lookup), `fetch`, and
  # `diff --name-only` (file list reconstruction for the az path).
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT}"
case "\$1" in
  rev-parse)
    if [ "\$2" = "--abbrev-ref" ] && [ "\$3" = "HEAD" ]; then
      echo "feat/FEAT-033-managing-source-control"
      exit 0
    fi
    exec "\$REAL_GIT" "\$@"
    ;;
  fetch)
    exit 0
    ;;
  diff)
    if [ "\$2" = "--name-only" ]; then
      echo "a.txt"
      echo "b.txt"
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
case "\$1" in
  auth)
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  pr)
    if [ "\$2" = "view" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      if [ -n "\${GH_VIEW_FAIL:-}" ]; then
        echo "gh: pr view failed" >&2
        exit 1
      fi
      # Echo a fixed JSON payload representing the union projection.
      cat <<'JSONEOF'
{"number":42,"title":"feat: example PR","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/lwndev/lwndev-marketplace/pull/42","files":[{"path":"a.txt"},{"path":"b.txt"}]}
JSONEOF
      exit 0
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/gh"

  # Fake `az`: stubs `repos pr -h`, `account show`, `repos pr list` (for the
  # branch→id lookup), and `repos pr show` (native PR object).
  cat > "${STUBDIR}/az" <<STUBEOF
#!/usr/bin/env bash
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "-h" ]; then
  if [ -n "\${AZ_EXT_MISSING:-}" ]; then
    echo "extension missing" >&2
    exit 1
  fi
  echo "az repos pr help"
  exit 0
fi
if [ "\$1" = "account" ] && [ "\$2" = "show" ]; then
  if [ -n "\${AZ_NOT_AUTH:-}" ]; then
    echo "not authenticated" >&2
    exit 1
  fi
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "list" ]; then
  if [ -n "\${AZ_LIST_EMPTY:-}" ]; then
    # Simulate jq -r '[0].pullRequestId' projection miss (returns "null").
    echo "null"
    exit 0
  fi
  echo "42"
  exit 0
fi
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "show" ]; then
  touch "${STUBDIR}/az.invoked"
  : > "${STUBDIR}/az.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.args"
  done
  if [ -n "\${AZ_SHOW_FAIL:-}" ]; then
    echo "az repos pr show stub failure" >&2
    exit 1
  fi
  cat <<'JSONEOF'
{"pullRequestId":42,"title":"feat: example AzDO PR","status":"active","mergeStatus":"succeeded","_links":{"web":{"href":"https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/42"}},"targetRefName":"refs/heads/main"}
JSONEOF
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  # Symlink the system binaries the dispatcher needs so the "gh/az NOT on
  # PATH" tests below can use PATH="${STUBDIR}" without losing access to
  # bash, dirname, jq. CI runners have gh/az in /usr/bin which leaks through
  # PATH="${STUBDIR}:/usr/bin:/bin" and defeats the absent-CLI assertion.
  for _tool in bash dirname jq; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
  done

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_VIEW_FAIL
  unset GH_NOT_AUTH
  unset AZ_EXT_MISSING
  unset AZ_NOT_AUTH
  unset AZ_SHOW_FAIL
  unset AZ_LIST_EMPTY
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

@test "gh stub success (GitHub origin, with PR number) → JSON on stdout" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"mergeable":"MERGEABLE"'* ]]
  [[ "$output" == *'"url":"https://github.com/lwndev/lwndev-marketplace/pull/42"'* ]]
  [[ "$output" == *'"files":[{"path":"a.txt"}'* ]]
}

@test "gh stub success (no PR number — infers from branch) → JSON on stdout" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$VIEW_PR"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
}

@test "projection includes union of consumer fields" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  # Verify --json flag carried the union: number,title,state,mergeable,url,files
  grep -qF "number,title,state,mergeable,url,files" "${STUBDIR}/gh.args"
}

@test "gh absent (GitHub origin) → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}" bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh present but not authenticated → [warn] auth line, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
}

@test "gh pr view failure → [warn] graceful skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_VIEW_FAIL=1 run --separate-stderr bash "$VIEW_PR" 99
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] gh pr view failed"* ]]
}

@test "Azure DevOps origin (with PR number) → normalized JSON on stdout (FR-5 transform)" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"title":"feat: example AzDO PR"'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"mergeable":"MERGEABLE"'* ]]
  [[ "$output" == *'"url":"https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/42"'* ]]
  # files reconstructed from `git diff --name-only origin/main...HEAD` stub.
  [[ "$output" == *'"path":"a.txt"'* ]]
  [[ "$output" == *'"path":"b.txt"'* ]]
  # az repos pr show must receive --organization AND --project so the call
  # does not rely on `az devops configure --defaults project=...` being set.
  grep -qF -- "--organization" "${STUBDIR}/az.args"
  grep -qF -- "--project" "${STUBDIR}/az.args"
  grep -qF -- "sdlc-tools" "${STUBDIR}/az.args"
}

@test "Azure DevOps origin (no PR number) → resolves via branch lookup, normalized JSON" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$VIEW_PR"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
  # Show invocation should have happened with --id 42 from the list lookup.
  [ -f "${STUBDIR}/az.invoked" ]
  grep -qF -- "--id" "${STUBDIR}/az.args"
  grep -qF -- "42" "${STUBDIR}/az.args"
}

@test "Azure DevOps origin (no PR number, no open PR) → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_LIST_EMPTY=1 run --separate-stderr bash "$VIEW_PR"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] no open PR for current branch"* ]]
}

@test "Azure DevOps origin: az absent → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  rm -f "${STUBDIR}/az"
  run --separate-stderr env PATH="${STUBDIR}" bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
}

@test "Azure DevOps origin: az devops extension missing → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "Azure DevOps origin: az not logged in → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "Azure DevOps origin: az repos pr show failure → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_SHOW_FAIL=1 run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az repos pr show failed"* ]]
}

@test "unrecognized origin → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}
