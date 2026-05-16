#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/view-pr.sh (FEAT-033 Phase 3).
#
# Strategy: PATH-prepend stubs for `git` (pass through) and `gh` (emit fixed
# JSON for `pr view`).
#
# Coverage (Phase 3 plan):
#   1. gh stub success → GitHub-shape JSON on stdout.
#   2. gh absent (GitHub origin) → [warn] skip, exit 0.
#   3. Azure DevOps stub path → [warn] not-yet-implemented, exit 0.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  VIEW_PR="${SCRIPT_DIR}/view-pr.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-view-pr.XXXXXX")"
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

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_VIEW_FAIL
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
  run --separate-stderr env PATH="${STUBDIR}:/usr/bin:/bin" bash "$VIEW_PR" 42
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

@test "Azure DevOps origin → [warn] not-yet-implemented, exit 0" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] Azure DevOps PR view not yet implemented."* ]]
}

@test "unrecognized origin → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$VIEW_PR" 42
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin."* ]]
}
