#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/create-pr.sh (FEAT-033 Phase 3).
#
# Strategy: PATH-prepend a stub directory containing fake `git` and `gh`
# scripts. The fake `git` honors REAL_GIT for `remote get-url origin` (so the
# real repo metadata flows through) and stubs `rev-parse` / `push`.
#
# Coverage (Phase 3 plan):
#   1. gh stub on PATH, GitHub origin → PR URL on stdout, exit 0.
#   2. gh NOT on PATH (GitHub origin) → [warn] line on stderr, exit 0.
#   3. az stub on PATH, AzDO origin → stub [warn] (not-yet-implemented), exit 0.
#   4. Unrecognized origin (e.g. gitlab) → [info] skip, exit 0.

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

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GIT_PUSH_FAIL
  unset GH_FAIL
  unset GH_NOT_AUTH
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
  # Remove gh from the stub PATH by clobbering it with a non-executable file.
  rm -f "${STUBDIR}/gh"
  # Make sure the test process cannot find `gh` anywhere by setting PATH to
  # contain only STUBDIR (plus the bare minimum for bash).
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$CREATE_PR" feat FEAT-033 "summary"
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

@test "AzDO origin → stub [warn] not-yet-implemented, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run --separate-stderr bash "$CREATE_PR" feat FEAT-033 "summary"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure DevOps PR creation not yet implemented."* ]]
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
