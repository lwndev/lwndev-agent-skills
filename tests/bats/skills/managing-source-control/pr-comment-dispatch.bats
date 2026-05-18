#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Bats fixture for managing-source-control/scripts/pr-comment.sh — cross-backend
# dispatch invariants (FEAT-034 Phase 2 / FR-6).
#
# Strategy: PATH-prepend a STUBDIR with a pass-through `git` so backend-detect.sh
# can read the origin URL. No `gh` / `az` / `curl` are stubbed — the dispatch
# tests below either land in the null-backend skip path (no CLI invocation) or
# exercise the override semantics inherited from backend-detect.sh.
#
# Coverage:
#   - backend-detect returns null (unrecognized origin) → [info] skip, exit 0.
#   - SDLC_SCM_BACKEND=github against an azdo origin → backend-detect emits
#     [warn] + null, pr-comment.sh inherits the null path → [info] skip, exit 0.
#   - SDLC_SCM_BACKEND=azdo against a github origin → same null pass-through.
#   - Empty origin (no remote configured) → [info] skip, exit 0.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_COMMENT="${SCRIPT_DIR}/pr-comment.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-pr-comment-dispatch.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  ORIG_PATH="$PATH"
  REAL_RM="$(command -v rm)"

  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 \
    || "$REAL_GIT" init --quiet >/dev/null 2>&1
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config user.name "Test"
  "$REAL_GIT" config commit.gpgsign false

  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
exec "${REAL_GIT}" "\$@"
STUBEOF
  chmod +x "${STUBDIR}/git"

  for _tool in bash dirname jq head sed tr cat mktemp cp rm chmod grep awk touch ls printf env; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
  done

  PATH="${STUBDIR}"
  export PATH
  unset SDLC_SCM_BACKEND
}

teardown() {
  cd /
  "$REAL_RM" -rf "$REPO_DIR"
  PATH="$ORIG_PATH"
  export PATH
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- FR-6: null backend skip ----------

@test "unrecognized origin → [info] no recognized backend, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
}

@test "no origin remote configured → [info] skip, exit 0" {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  run --separate-stderr bash "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
}

# ---------- SDLC_SCM_BACKEND override semantics (pass-through to backend-detect) ----------

@test "SDLC_SCM_BACKEND=github against azdo origin → null pass-through" {
  set_origin "https://dev.azure.com/contoso/sdlc-tools/_git/plugin-repo"
  SDLC_SCM_BACKEND=github run --separate-stderr bash "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  # backend-detect emits its own [warn]; pr-comment sees null → [info] skip.
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
}

@test "SDLC_SCM_BACKEND=azdo against github origin → null pass-through" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=azdo run --separate-stderr bash "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
}

@test "SDLC_SCM_BACKEND=unrecognized → null pass-through" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  SDLC_SCM_BACKEND=bitbucket run --separate-stderr bash "$PR_COMMENT" 1 "body"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]] \
    || { >&3 echo "STDERR=$stderr"; false; }
}
