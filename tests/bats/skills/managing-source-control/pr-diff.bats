#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/pr-diff.sh (FEAT-033
# Phase 4). GitHub path emits `gh pr diff`; AzDO path resolves the base
# branch via `az repos pr show` and runs `git diff origin/<base>...HEAD`
# after a pre-fetch (Edge Case 6).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_DIFF="${SCRIPT_DIR}/pr-diff.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-pr-diff.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1

  # Fake `git`: pass through to real git but intercept `fetch` and `diff`
  # for the AzDO path (the stub records calls and emits a fixed diff).
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
REAL_GIT="${REAL_GIT}"
case "\$1" in
  fetch)
    touch "${STUBDIR}/git.fetch.invoked"
    : > "${STUBDIR}/git.fetch.args"
    for a in "\$@"; do
      printf '%s\n' "\$a" >> "${STUBDIR}/git.fetch.args"
    done
    exit 0
    ;;
  diff)
    touch "${STUBDIR}/git.diff.invoked"
    : > "${STUBDIR}/git.diff.args"
    for a in "\$@"; do
      printf '%s\n' "\$a" >> "${STUBDIR}/git.diff.args"
    done
    if [ -n "\${GIT_DIFF_FAIL:-}" ]; then
      echo "git diff stub failure" >&2
      exit 1
    fi
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
case "\$1" in
  auth)
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  pr)
    if [ "\$2" = "diff" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      if [ -n "\${GH_DIFF_FAIL:-}" ]; then
        echo "gh pr diff stub failure" >&2
        exit 1
      fi
      echo "diff --git a/x b/x"
      echo "+stub diff"
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
  echo "refs/heads/main"
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_NOT_AUTH GH_DIFF_FAIL AZ_EXT_MISSING AZ_NOT_AUTH AZ_SHOW_FAIL GIT_DIFF_FAIL SDLC_SCM_BACKEND
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- usage ----------

@test "missing pr-number → exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$PR_DIFF"
  [ "$status" -eq 2 ]
}

# ---------- GitHub path ----------

@test "gh path: calls gh pr diff <N>; emits diff on stdout" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/x b/x"* ]]
  grep -qF -- "42" "${STUBDIR}/gh.args"
}

@test "gh absent → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh not authenticated → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
}

@test "gh pr diff failure → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_DIFF_FAIL=1 run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] gh pr diff failed"* ]]
}

# ---------- Azure DevOps path ----------

@test "az path: pre-fetches origin/<base> and runs git diff origin/<base>...HEAD" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"--- stub git diff output ---"* ]]
  # Verify base ref is queried via az repos pr show.
  grep -qF -- "targetRefName" "${STUBDIR}/az.args"
  # Verify pre-fetch happened.
  [ -f "${STUBDIR}/git.fetch.invoked" ]
  grep -qF -- "main" "${STUBDIR}/git.fetch.args"
  # Verify git diff was called with origin/main...HEAD (base stripped).
  [ -f "${STUBDIR}/git.diff.invoked" ]
  grep -qF -- "origin/main...HEAD" "${STUBDIR}/git.diff.args"
}

@test "az absent → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  rm -f "${STUBDIR}/az"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
}

@test "az devops extension missing → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "az not logged in → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "az repos pr show failure → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_SHOW_FAIL=1 run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az repos pr show failed"* ]]
}

# ---------- Unrecognized ----------

@test "unrecognized origin → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$PR_DIFF" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}
