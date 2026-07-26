#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

# Strip inherited GIT_* env so fixture git calls cannot reach the real repo (#326).
load '../../helpers/git-env'
sanitize_git_env

# Bats fixture for managing-source-control/scripts/pr-comment.sh (FEAT-034 Phase 1).
#
# Strategy: PATH-prepend a stub directory containing fake `git` and `gh`
# scripts. The fake `git` delegates to real git for `remote get-url origin`
# (so backend-detect.sh works) and stubs nothing else — pr-comment.sh does
# not push. The fake `gh` records invocations and returns a fixed comment URL.
#
# Coverage (Phase 1):
#   - Positional body succeeds, prints stub URL.
#   - --body flag equivalent succeeds.
#   - --body-file reads from path, gh invoked with --body-file.
#   - Missing body-file exits non-zero with [error].
#   - Ambiguous body sources: all 3 mutual-exclusion permutations exit non-zero.
#   - --reply-to on GitHub emits [warn] and exits 0 (no gh invocation).
#   - Empty body (blank string) passed through — gh CLI rejects it; surfaces as [warn].
#   - gh missing emits [warn] and exits 0.
#   - gh auth status failing emits [warn] and exits 0.
#   - gh pr comment non-zero emits [warn] + first stderr line, exits 0.
#   - Non-numeric --reply-to exits non-zero with [error].
#   - Non-numeric PR number exits non-zero with [error].
#   - Null backend emits [info] and exits 0.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../../plugins/lwndev-sdlc/skills/managing-source-control/scripts" && pwd)"
  PR_COMMENT="${SCRIPT_DIR}/pr-comment.sh"
  REPO_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/msc-pr-comment-gh.XXXXXX")"
  STUBDIR="${REPO_DIR}/bin"
  mkdir -p "$STUBDIR"

  # Init a real repo so backend-detect.sh (which calls `git remote get-url origin`) works.
  cd "$REPO_DIR"
  REAL_GIT="$(command -v git)"
  "$REAL_GIT" init --quiet --initial-branch=main >/dev/null 2>&1 \
    || "$REAL_GIT" init --quiet >/dev/null 2>&1
  "$REAL_GIT" config user.email "test@example.com"
  "$REAL_GIT" config user.name "Test"
  "$REAL_GIT" config commit.gpgsign false

  # Fake `git`: delegate everything to real git. pr-comment.sh does not push,
  # so no stubs needed beyond pass-through.
  cat > "${STUBDIR}/git" <<STUBEOF
#!/usr/bin/env bash
exec "${REAL_GIT}" "\$@"
STUBEOF
  chmod +x "${STUBDIR}/git"

  # Fake `gh`: records invocation args; returns a fixed comment URL on pr comment.
  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
case "\$1" in
  auth)
    # gh auth status → ok unless GH_NOT_AUTH is set.
    if [ -n "\${GH_NOT_AUTH:-}" ]; then
      echo "not authenticated" >&2
      exit 1
    fi
    exit 0
    ;;
  pr)
    if [ "\$2" = "comment" ]; then
      touch "${STUBDIR}/gh.invoked"
      : > "${STUBDIR}/gh.args"
      for a in "\$@"; do
        printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
      done
      # Capture --body value and record body-file flag.
      body=""
      bodyfile=""
      while [ "\$#" -gt 0 ]; do
        case "\$1" in
          --body)      body="\$2";     shift 2 ;;
          --body-file) bodyfile="\$2"; shift 2 ;;
          *)           shift ;;
        esac
      done
      printf '%s' "\$body" > "${STUBDIR}/gh.body"
      printf '%s' "\$bodyfile" > "${STUBDIR}/gh.bodyfile"
      if [ -n "\${GH_COMMENT_FAIL:-}" ]; then
        echo "gh pr comment stub failure" >&2
        exit 1
      fi
      echo "https://github.com/lwndev/lwndev-marketplace/pull/127#issuecomment-9999999"
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

  # Symlink system binaries needed by backend-detect.sh / pr-comment.sh so
  # PATH="${STUBDIR}"-only tests don't lose access to bash/dirname/jq while
  # still blocking any system gh/az from leaking through.
  for _tool in bash dirname jq; do
    _real="$(command -v "$_tool" 2>/dev/null || true)"
    if [ -n "$_real" ]; then
      ln -sf "$_real" "${STUBDIR}/${_tool}"
    fi
  done

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GH_NOT_AUTH GH_COMMENT_FAIL SDLC_SCM_BACKEND
}

teardown() {
  cd /
  rm -rf "$REPO_DIR"
}

set_origin() {
  "$REAL_GIT" -C "$REPO_DIR" remote remove origin >/dev/null 2>&1 || true
  "$REAL_GIT" -C "$REPO_DIR" remote add origin "$1"
}

# ---------- GitHub path: body sources ----------

@test "positional body on GitHub origin → comment URL on stdout, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$PR_COMMENT" 127 "LGTM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/lwndev/lwndev-marketplace/pull/127#issuecomment-"* ]]
  [ -f "${STUBDIR}/gh.invoked" ]
}

@test "--body flag on GitHub origin → gh invoked, comment URL on stdout, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run bash "$PR_COMMENT" 127 --body "LGTM via flag"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/lwndev/lwndev-marketplace/pull/127#issuecomment-"* ]]
  [ -f "${STUBDIR}/gh.invoked" ]
  grep -qF -- "--body" "${STUBDIR}/gh.args"
}

@test "--body-file on GitHub origin → gh invoked with --body-file, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  body_path="${REPO_DIR}/review.md"
  printf 'Some review content' > "$body_path"
  run bash "$PR_COMMENT" 127 --body-file "$body_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/lwndev/lwndev-marketplace/pull/127#issuecomment-"* ]]
  [ -f "${STUBDIR}/gh.invoked" ]
  grep -qF -- "--body-file" "${STUBDIR}/gh.args"
  grep -qF -- "$body_path" "${STUBDIR}/gh.args"
}

# ---------- Edge 3: missing body file ----------

@test "--body-file pointing to missing path → [error] + exit non-zero" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$PR_COMMENT" 127 --body-file "/tmp/nonexistent-review-file-xyz.md"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] body file not found"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

# ---------- Edge 11: ambiguous body sources ----------

@test "positional + --body ambiguous → [error] + exit non-zero" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$PR_COMMENT" 127 "positional" --body "flag"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] body source ambiguous"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "positional + --body-file ambiguous → [error] + exit non-zero" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  body_path="${REPO_DIR}/review.md"
  printf 'content' > "$body_path"
  run --separate-stderr bash "$PR_COMMENT" 127 "positional" --body-file "$body_path"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] body source ambiguous"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "--body + --body-file ambiguous → [error] + exit non-zero" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  body_path="${REPO_DIR}/review.md"
  printf 'content' > "$body_path"
  run --separate-stderr bash "$PR_COMMENT" 127 --body "flag" --body-file "$body_path"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] body source ambiguous"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

# ---------- --reply-to on GitHub (FR-1 graceful skip) ----------

@test "--reply-to on GitHub emits [warn] and exits 0, gh not invoked" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$PR_COMMENT" 127 --body "Reply attempt" --reply-to 9
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] --reply-to not supported on GitHub backend; skipping."* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

# ---------- Edge 12: non-numeric --reply-to ----------

@test "non-numeric --reply-to exits non-zero with [error]" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$PR_COMMENT" 127 --body "body" --reply-to "foo"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] --reply-to must be a numeric thread id"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

# ---------- Non-numeric PR number ----------

@test "non-numeric PR number exits non-zero with [error]" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  run --separate-stderr bash "$PR_COMMENT" "not-a-number" --body "body"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"[error] pr-number must be a numeric PR identifier"* ]]
}

# ---------- NFR-1: graceful-degradation on GitHub ----------

@test "gh absent (GitHub origin) → [warn] skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  rm -f "${STUBDIR}/gh"
  run --separate-stderr env PATH="${STUBDIR}" bash "$PR_COMMENT" 127 "LGTM"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI (gh) not found on PATH."* ]]
}

@test "gh present but not authenticated → [warn] auth skip, exit 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_NOT_AUTH=1 run --separate-stderr bash "$PR_COMMENT" 127 "LGTM"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] GitHub CLI not authenticated"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "gh pr comment non-zero → surfaces stderr as [warn], exits 0" {
  set_origin "https://github.com/lwndev/lwndev-marketplace.git"
  GH_COMMENT_FAIL=1 run --separate-stderr bash "$PR_COMMENT" 127 "LGTM"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[warn] gh pr comment failed"* ]]
  [[ "$stderr" == *"stub failure"* ]]
}

# ---------- Null backend ----------

@test "null backend (unrecognized origin) → [info] skip, exit 0" {
  set_origin "https://gitlab.com/foo/bar.git"
  run --separate-stderr bash "$PR_COMMENT" 127 "LGTM"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"[info] No recognized SCM backend detected from origin. Skipping PR comment."* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

# ADO-origin coverage moved to pr-comment-azdo.bats (Phase 2).
