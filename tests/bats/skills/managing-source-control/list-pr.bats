#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/list-pr.sh (FEAT-033 Phase 4).
# Verifies GitHub and Azure DevOps paths emit the normalized
# `[{number, state}, ...]` shape (NFR-3) and the NFR-1 skip matrix.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  LIST_PR="${SCRIPT_DIR}/list-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-list-pr.XXXXXX")"
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
    if [ "\$2" = "list" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      if [ -n "\${GH_LIST_FAIL:-}" ]; then
        echo "gh pr list stub failure" >&2
        exit 1
      fi
      echo '[{"number":12,"state":"OPEN"},{"number":13,"state":"OPEN"}]'
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
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "list" ]; then
  touch "${STUBDIR}/az.invoked"
  : > "${STUBDIR}/az.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.args"
  done
  if [ -n "\${AZ_LIST_FAIL:-}" ]; then
    echo "az repos pr list stub failure" >&2
    exit 1
  fi
  # Native az shape: array of PR objects.
  cat <<'JSONEOF'
[{"pullRequestId":42,"status":"active"},{"pullRequestId":43,"status":"completed"}]
JSONEOF
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${STUBDIR}/az"

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_NOT_AUTH GH_LIST_FAIL AZ_EXT_MISSING AZ_NOT_AUTH AZ_LIST_FAIL SDLC_SCM_BACKEND
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

@test "missing --head → exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$LIST_PR"
  [ "$status" -eq 2 ]
}

# ---------- GitHub path ----------

@test "gh stub success (GitHub origin) → JSON array on stdout" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$LIST_PR" --head "feat/FEAT-033"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":12'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  grep -qF -- "--head" "${STUBDIR}/gh.args"
  grep -qF -- "feat/FEAT-033" "${STUBDIR}/gh.args"
  grep -qF -- "number,state" "${STUBDIR}/gh.args"
}

@test "gh absent (GitHub origin) → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh not authenticated → [warn] auth, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
}

@test "gh pr list failure → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_LIST_FAIL=1 run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] gh pr list failed"* ]]
}

# ---------- Azure DevOps path ----------

@test "az stub success (AzDO origin) → normalized JSON shape on stdout" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$LIST_PR" --head "feat/FEAT-033"
  [ "$status" -eq 0 ]
  # Normalized via az-shape-transform: pullRequestId→number, status→state.
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"state":"OPEN"'* ]]
  [[ "$output" == *'"number":43'* ]]
  [[ "$output" == *'"state":"MERGED"'* ]]
  # `--source-branch` carried the bare branch name.
  grep -qF -- "--source-branch" "${STUBDIR}/az.args"
  grep -qF -- "feat/FEAT-033" "${STUBDIR}/az.args"
  # `--status active` filter is applied.
  grep -qF -- "active" "${STUBDIR}/az.args"
}

@test "az absent (AzDO origin) → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  rm -f "${STUBDIR}/az"
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
}

@test "az devops extension missing → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "az not logged in → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "az repos pr list failure → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_LIST_FAIL=1 run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az repos pr list failed"* ]]
}

# ---------- Unrecognized ----------

@test "unrecognized origin → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$LIST_PR" --head x
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}
