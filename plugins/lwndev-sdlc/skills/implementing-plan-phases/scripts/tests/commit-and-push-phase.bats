#!/usr/bin/env bats
# Bats fixture for commit-and-push-phase.sh (FEAT-027 / FR-5).
#
# Uses PATH-shadowing stubs for `git` to cover:
#   - canonical commit message across FEAT / CHORE / BUG ID prefixes
#   - first-push vs. subsequent-push (-u origin <branch>) logic
#   - empty-tree, commit-hook-rejection, push-failure error paths
#
# Follows the stub pattern from
# plugins/lwndev-sdlc/skills/reviewing-requirements/scripts/tests/verify-references.bats:
# fixture-local FIXTURE_DIR via mktemp -d, inline PATH on each `run` call,
# parent-shell PATH never mutated.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/commit-and-push-phase.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR"
  : > "$TRACER"
  export TRACER

  TEST_CWD="${FIXTURE_DIR}/work"
  mkdir -p "$TEST_CWD"
  cd "$TEST_CWD"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- git stub ----------

write_git_stub() {
  # GIT_STATUS_STDOUT  — `git status --porcelain=v1` stdout (default one change)
  # GIT_ADD_RC         — exit for `git add -A`         (default 0)
  # GIT_COMMIT_RC      — exit for `git commit`        (default 0)
  # GIT_COMMIT_ERR     — stderr for `git commit`       (printed when RC != 0)
  # GIT_BRANCH_STDOUT  — `git rev-parse --abbrev-ref HEAD` stdout
  #                      (default `feat/FEAT-027-implementing-plan-phases-scripts`)
  # GIT_UPSTREAM_RC    — exit for `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
  #                      (default 1 — no upstream)
  # GIT_PUSH_RC        — exit for `git push`           (default 0)
  # GIT_PUSH_ERR       — stderr for `git push`          (printed when RC != 0)
  cat > "${STUB_DIR}/git" <<'EOF'
#!/usr/bin/env bash
printf 'TRACE:git:%s\n' "$*" >> "${TRACER}"
case "$1" in
  status)
    printf '%s' "${GIT_STATUS_STDOUT- M file.txt}"
    exit 0
    ;;
  add)
    exit "${GIT_ADD_RC:-0}"
    ;;
  commit)
    if [ "${GIT_COMMIT_RC:-0}" -ne 0 ]; then
      printf '%s\n' "${GIT_COMMIT_ERR:-pre-commit hook rejected}" >&2
      exit "${GIT_COMMIT_RC}"
    fi
    # Capture the commit message for assertion (printf to tracer).
    if [ "$2" = "-m" ] && [ -n "${3:-}" ]; then
      printf 'COMMIT-MSG:%s\n' "$3" >> "${TRACER}"
    fi
    exit 0
    ;;
  rev-parse)
    shift
    case "$*" in
      "--abbrev-ref HEAD")
        printf '%s\n' "${GIT_BRANCH_STDOUT:-feat/FEAT-027-implementing-plan-phases-scripts}"
        exit 0
        ;;
      "--abbrev-ref --symbolic-full-name @{u}")
        exit "${GIT_UPSTREAM_RC:-1}"
        ;;
    esac
    exit 0
    ;;
  push)
    if [ "${GIT_PUSH_RC:-0}" -ne 0 ]; then
      printf '%s\n' "${GIT_PUSH_ERR:-! [rejected] main -> main (non-fast-forward)}" >&2
      exit "${GIT_PUSH_RC}"
    fi
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
}

# =====================================================================
# Arg-validation
# =====================================================================

@test "missing all args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: commit-and-push-phase.sh"* ]]
}

@test "missing phase name -> exit 2" {
  run bash "$SCRIPT" "FEAT-027" "1"
  [ "$status" -eq 2 ]
}

@test "malformed FEAT-ID (lowercase) -> exit 2" {
  run bash "$SCRIPT" "feat-027" "1" "scaffold"
  [ "$status" -eq 2 ]
  [[ "$output" == *"^(FEAT|CHORE|BUG)-"* ]]
}

@test "malformed FEAT-ID (wrong prefix) -> exit 2" {
  run bash "$SCRIPT" "FEATURE-001" "1" "scaffold"
  [ "$status" -eq 2 ]
}

@test "non-positive phase-N -> exit 2" {
  run bash "$SCRIPT" "FEAT-027" "0" "scaffold"
  [ "$status" -eq 2 ]
}

@test "non-integer phase-N -> exit 2" {
  run bash "$SCRIPT" "FEAT-027" "abc" "scaffold"
  [ "$status" -eq 2 ]
}

@test "empty phase name -> exit 2" {
  run bash "$SCRIPT" "FEAT-027" "1" ""
  [ "$status" -eq 2 ]
}

@test "whitespace-only phase name -> exit 2" {
  run bash "$SCRIPT" "FEAT-027" "1" "   "
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-empty"* ]]
}

# =====================================================================
# Canonical commit messages (all three prefix flavors)
# =====================================================================

@test "FEAT-027 happy path -> feat( ... ) commit message, pushed <branch>" {
  write_git_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-027" "1" "scripts scaffold"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pushed feat/FEAT-027-implementing-plan-phases-scripts"* ]]
  run cat "${TRACER}"
  [[ "$output" == *"COMMIT-MSG:feat(FEAT-027): complete phase 1 - scripts scaffold"* ]]
}

@test "CHORE-003 happy path -> chore( ... ) commit message" {
  write_git_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "CHORE-003" "2" "update deps"
  [ "$status" -eq 0 ]
  run cat "${TRACER}"
  [[ "$output" == *"COMMIT-MSG:chore(CHORE-003): complete phase 2 - update deps"* ]]
}

@test "BUG-012 happy path -> fix( ... ) commit message" {
  write_git_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "BUG-012" "3" "fix null check"
  [ "$status" -eq 0 ]
  run cat "${TRACER}"
  [[ "$output" == *"COMMIT-MSG:fix(BUG-012): complete phase 3 - fix null check"* ]]
}

# =====================================================================
# Upstream detection
# =====================================================================

@test "no upstream -> git push -u origin <branch>" {
  write_git_stub
  # GIT_UPSTREAM_RC defaults to 1 (no upstream).
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-027" "1" "scaffold"
  [ "$status" -eq 0 ]
  run cat "${TRACER}"
  [[ "$output" == *"TRACE:git:push -u origin feat/FEAT-027-implementing-plan-phases-scripts"* ]]
}

@test "upstream already set -> bare git push" {
  write_git_stub
  GIT_UPSTREAM_RC=0 PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-027" "1" "scaffold"
  [ "$status" -eq 0 ]
  run cat "${TRACER}"
  [[ "$output" == *"TRACE:git:push"* ]]
  [[ "$output" != *"TRACE:git:push -u origin"* ]]
}

# =====================================================================
# Error paths
# =====================================================================

@test "empty git status -> error: no changes to commit, exit 1" {
  write_git_stub
  GIT_STATUS_STDOUT="" PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-027" "1" "scaffold"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: no changes to commit"* ]]
}

@test "git add fails -> stderr [error] git add failed, exit 1" {
  write_git_stub
  err_file="${FIXTURE_DIR}/err"
  GIT_ADD_RC=1 PATH="${STUB_DIR}:${PATH}" \
    bash "$SCRIPT" "FEAT-027" "1" "scaffold" 2>"$err_file" || rc=$?
  rc=${rc:-0}
  err="$(cat "$err_file")"
  [ "$rc" -eq 1 ]
  [[ "$err" == *"[error] git add failed"* ]]
}

@test "git commit fails (hook rejection) -> exit 1, hook stderr surfaced" {
  write_git_stub
  err_file="${FIXTURE_DIR}/err"
  GIT_COMMIT_RC=1 GIT_COMMIT_ERR="husky: commit-msg hook refused" \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" "FEAT-027" "1" "scaffold" 2>"$err_file" || rc=$?
  rc=${rc:-0}
  err="$(cat "$err_file")"
  [ "$rc" -eq 1 ]
  [[ "$err" == *"husky: commit-msg hook refused"* ]]
}

@test "git push fails -> stderr includes [error] push failed, exit 1" {
  write_git_stub
  err_file="${FIXTURE_DIR}/err"
  GIT_PUSH_RC=1 GIT_PUSH_ERR="remote rejected (push protection)" \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" "FEAT-027" "1" "scaffold" 2>"$err_file" || rc=$?
  rc=${rc:-0}
  err="$(cat "$err_file")"
  [ "$rc" -eq 1 ]
  [[ "$err" == *"remote rejected"* ]]
  [[ "$err" == *"[error] push failed; see Push Failure Recovery in SKILL.md"* ]]
}
