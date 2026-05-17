#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/create-pr.sh (FEAT-033
# Phases 3 + 4).
#
# Strategy: PATH-prepend a stub directory containing fake `git`, `gh`, and
# `az` scripts. The fake `git` honors REAL_GIT for `remote get-url origin`
# (so the real repo metadata flows through) and stubs `rev-parse` / `push`.
#
# Coverage:
#   - GitHub path: success, [warn] skip on missing gh, missing auth, etc.
#   - Azure DevOps path: success, [warn] skip on missing az, missing devops
#     extension, missing auth, az repos pr create failure.
#   - Unrecognized origin (e.g. gitlab) → [info] skip, exit 0.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  CREATE_PR="${SCRIPT_DIR}/create-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-create-pr.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  # Init a real repo (so backend-detect.sh, which calls `git remote get-url
  # origin`, works against this directory). The stubbed `git` below intercepts
  # `push` and `rev-parse` but delegates everything else to real git.
  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 || "$REAL_GIT" init --quiet >/dev/null 2>&1
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config user.name "Test"
  "$REAL_GIT" config commit.gpgsign false

  # Fake `git`: pass through to real git for everything except push and
  # rev-parse --abbrev-ref HEAD (which we stub to return a deterministic
  # branch name).
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
  push)
    if [ -n "\${GIT_PUSH_FAIL:-}" ]; then
      echo "fatal: stub push failure" >&2
      exit 1
    fi
    echo "To origin: pushed (stub)"
    exit 0
    ;;
  *)
    exec "\$REAL_GIT" "\$@"
    ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/git"

  # Fake `gh`: emits a fixed URL on `pr create`; records body via files.
  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
case "\$1" in
  auth)
    # gh auth status → ok unless GH_NOT_AUTH is set
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  pr)
    if [ "\$2" = "create" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      # Capture --body and --title.
      body=""
      title=""
      while [ "\$#" -gt 0 ]; do
        case "\$1" in
          --body)  body="\$2";  shift 2 ;;
          --title) title="\$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      printf '%s' "\$body" > "${STUBDIR}/gh.body"
      printf '%s' "\$title" > "${STUBDIR}/gh.title"
      if [ -n "\${GH_FAIL:-}" ]; then
        echo "gh: stub failure" >&2
        exit 1
      fi
      echo "https://github.com/lwndev/lwndev-marketplace/pull/123"
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

  # Fake `az`: emits the PR URL via --query '_links.web.href' -o tsv.
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
if [ "\$1" = "repos" ] && [ "\$2" = "pr" ] && [ "\$3" = "create" ]; then
  touch "${STUBDIR}/az.invoked"
  : > "${STUBDIR}/az.args"
  for a in "\$@"; do
    printf '%s\n' "\$a" >> "${STUBDIR}/az.args"
  done
  if [ -n "\${AZ_CREATE_FAIL:-}" ]; then
    echo "az repos pr create stub failure" >&2
    exit 1
  fi
  # With --query '_links.web.href' -o tsv, az emits just the URL line.
  echo "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/77"
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
  unset GIT_PUSH_FAIL
  unset GH_FAIL
  unset GH_NOT_AUTH
  unset AZ_EXT_MISSING
  unset AZ_NOT_AUTH
  unset AZ_CREATE_FAIL
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

@test "gh stub on PATH, GitHub origin → PR URL on stdout, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR" feat FEAT-033 "managing source control"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/lwndev/lwndev-marketplace/pull/123"* ]]
  [ -f "${STUBDIR}/gh.invoked" ]
  grep -qF -- "feat(FEAT-033): managing source control" "${STUBDIR}/gh.title"
}

@test "gh stub honors --closes flag in body" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR" feat FEAT-033 "summary" --closes "#120"
  [ "$status" -eq 0 ]
  grep -qF "Closes #120" "${STUBDIR}/gh.body"
}

@test "gh NOT on PATH (GitHub origin) → [warn] line on stderr, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  # Remove the gh stub. PATH is restricted to STUBDIR only (which has
  # symlinks to bash/dirname/jq from setup) so the system gh in /usr/bin
  # cannot leak through on CI runners.
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}" bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh present but not authenticated → [warn] auth line, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "AzDO origin success → PR URL on stdout, az invoked with correct args" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$CREATE_PR" feat FEAT-033 "managing source control"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo/pullrequest/77"* ]]
  [ -f "${STUBDIR}/az.invoked" ]
  grep -qF -- "--source-branch" "${STUBDIR}/az.args"
  grep -qF -- "--target-branch" "${STUBDIR}/az.args"
  grep -qF -- "--title" "${STUBDIR}/az.args"
  grep -qF -- "feat(FEAT-033): managing source control" "${STUBDIR}/az.args"
  grep -qF -- "--organization" "${STUBDIR}/az.args"
  grep -qF -- "https://dev.azure.com/contoso/" "${STUBDIR}/az.args"
  grep -qF -- "--project" "${STUBDIR}/az.args"
  grep -qF -- "sdlc-tools" "${STUBDIR}/az.args"
}

@test "AzDO origin: --issue-ref token rendered in description" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run bash "$CREATE_PR" feat FEAT-033 "summary" --issue-ref "AB#1234"
  [ "$status" -eq 0 ]
  grep -qF -- "AB#1234" "${STUBDIR}/az.args"
}

@test "AzDO origin: az absent → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  rm -f "${STUBDIR}/az"
  run --separate-stderr env PATH="${STUBDIR}" bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI (az) not found on PATH."* ]]
}

@test "AzDO origin: az devops extension missing → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_EXT_MISSING=1 run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az devops extension not available"* ]]
}

@test "AzDO origin: az not logged in → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_NOT_AUTH=1 run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure CLI not authenticated"* ]]
}

@test "AzDO origin: az repos pr create failure → [warn] skip, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  AZ_CREATE_FAIL=1 run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] az repos pr create failed"* ]]
}

@test "unrecognized origin (gitlab) → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}

@test "invalid type → exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR" badtype FEAT-033 "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
}

@test "missing required args → exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR"
  [ "$status" -eq 2 ]
  run bash "$CREATE_PR" feat
  [ "$status" -eq 2 ]
  run bash "$CREATE_PR" feat FEAT-033
  [ "$status" -eq 2 ]
}

@test "--closes empty / bare # → exit 2" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR" feat FEAT-033 "x" --closes ""
  [ "$status" -eq 2 ]
  run bash "$CREATE_PR" feat FEAT-033 "x" --closes "#"
  [ "$status" -eq 2 ]
}

@test "--issue-ref flag is accepted (Phase 3 stub: no observable effect on GitHub body)" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$CREATE_PR" feat FEAT-033 "summary" --issue-ref "AB#1234"
  [ "$status" -eq 0 ]
  [ -f "${STUBDIR}/gh.invoked" ]
}
