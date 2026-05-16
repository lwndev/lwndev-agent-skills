#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/merge-pr.sh (FEAT-033
# Phase 4). PATH-prepends stubs for `git`, `gh`, and `az` to drive both
# backend paths plus the NFR-1 graceful-skip matrix.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  MERGE_PR="${SCRIPT_DIR}/merge-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-merge-pr.XXXXXX")"
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
case "\$1" in
  auth)
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  pr)
    if [ "\$2" = "merge" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      if [ -n "\${GH_MERGE_FAIL:-}" ]; then
        echo "gh pr merge stub failure" >&2
        exit 1
      fi
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
# Args: \$1=topic; for repos pr → \$2=pr, \$3=verb, then flags.
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
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "update" ]; then
  touch "${STUBDIR}/az.invoked"
  : > "${STUBDIR}/az.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.args"
  done
  if [ -n "\${AZ_UPDATE_FAIL:-}" ]; then
    echo "az repos pr update stub failure" >&2
    exit 1
  fi
  echo '{"pullRequestId":42,"status":"completed"}'
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_MERGE_FAIL GH_NOT_AUTH AZ_EXT_MISSING AZ_NOT_AUTH AZ_UPDATE_FAIL SDLC_SCM_BACKEND
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- GitHub path ----------

@test "gh stub success (GitHub origin, with PR number) → exit 0, gh invoked" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/gh.invoked" ]
  grep -qF -- "--merge" "${STUBDIR}/gh.args"
  grep -qF -- "--delete-branch" "${STUBDIR}/gh.args"
}

@test "gh stub success (no PR number — infers from branch) → exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$MERGE_PR"
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/gh.invoked" ]
}

@test "gh absent (GitHub origin) → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh present but not authenticated → [warn] auth, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
}

@test "gh pr merge failure → [warn] graceful skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_MERGE_FAIL=1 run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] gh pr merge failed"* ]]
}

# ---------- Azure DevOps path ----------

@test "az stub success (AzDO origin) → exit 0, az invoked" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/az.invoked" ]
  grep -qF -- "completed" "${STUBDIR}/az.args"
  grep -qF -- "--delete-source-branch" "${STUBDIR}/az.args"
  grep -qF -- "--squash" "${STUBDIR}/az.args"
}

@test "az absent (AzDO origin) → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  rm -f "${STUBDIR}/az"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
}

@test "az devops extension missing → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "az not logged in → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "az repos pr update failure → [warn] graceful skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_UPDATE_FAIL=1 run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az repos pr update failed"* ]]
}

@test "AzDO origin without pr number → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run --separate-stderr bash "$MERGE_PR"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure DevOps merge requires --id"* ]]
}

# ---------- Unrecognized ----------

@test "unrecognized origin → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$MERGE_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}
