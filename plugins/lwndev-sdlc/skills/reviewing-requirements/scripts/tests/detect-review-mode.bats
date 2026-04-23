#!/usr/bin/env bats
# Bats fixture for detect-review-mode.sh (FEAT-026 / FR-1).
#
# Uses a PATH-shadowing `gh` stub to cover every precedence branch plus the
# graceful-degradation paths (gh missing, gh unauthenticated, malformed gh
# response). All tests run in a hermetic tmpdir that is made the CWD so
# `qa/test-plans/QA-plan-<ID>.md` resolves against fixture state rather than
# the repo's real layout.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/detect-review-mode.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR"
  : > "$TRACER"
  export TRACER

  TEST_CWD="${FIXTURE_DIR}/work"
  mkdir -p "${TEST_CWD}/qa/test-plans"
  cd "$TEST_CWD"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- gh stub ----------

write_gh_stub() {
  # Behaviors controlled by env vars:
  #   GH_AUTH_RC         — exit code for `gh auth status` (default 0)
  #   GH_PR_LIST_STDOUT  — stdout returned by `gh pr list` (default "[]")
  #   GH_PR_LIST_RC      — exit code for `gh pr list` (default 0)
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:gh:$*" >> "${TRACER}"
case "$1" in
  auth)
    [ "$2" = "status" ] && exit "${GH_AUTH_RC:-0}"
    exit 0
    ;;
  pr)
    if [ "$2" = "list" ]; then
      rc="${GH_PR_LIST_RC:-0}"
      if [ "$rc" -ne 0 ]; then
        exit "$rc"
      fi
      # Default: empty array.
      printf '%s' "${GH_PR_LIST_STDOUT:-[]}"
      exit 0
    fi
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

empty_path_for_no_gh() {
  local dir="${FIXTURE_DIR}/nogh"
  mkdir -p "$dir"
  for bin in bash env awk sed grep tr cut wc mktemp head tail cat printf chmod rm mkdir ls test dirname basename sort jq uniq compgen; do
    if [ -x "/bin/$bin" ]; then
      ln -sf "/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/usr/bin/$bin" ]; then
      ln -sf "/usr/bin/$bin" "$dir/$bin" 2>/dev/null || true
    elif [ -x "/opt/homebrew/bin/$bin" ]; then
      ln -sf "/opt/homebrew/bin/$bin" "$dir/$bin" 2>/dev/null || true
    fi
  done
  printf '%s' "$dir"
}

# =====================================================================
# Arg validation
# =====================================================================

@test "missing ID -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: detect-review-mode.sh"* ]]
}

@test "empty ID (explicit '') -> exit 2" {
  run bash "$SCRIPT" ""
  [ "$status" -eq 2 ]
}

@test "malformed ID FEAT- (no digits) -> exit 2" {
  run bash "$SCRIPT" "FEAT-"
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ID"* ]]
}

@test "lowercase feat-026 -> exit 2" {
  run bash "$SCRIPT" "feat-026"
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed ID"* ]]
}

@test "unknown prefix XYZ-1 -> exit 2" {
  run bash "$SCRIPT" "XYZ-1"
  [ "$status" -eq 2 ]
}

@test "--pr non-numeric -> exit 2 with [warn]" {
  run bash "$SCRIPT" "FEAT-026" --pr abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"[warn] detect-review-mode: --pr value must be numeric"* ]]
}

@test "--pr without value -> exit 2 with [warn]" {
  run bash "$SCRIPT" "FEAT-026" --pr
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pr value must be numeric"* ]]
}

# =====================================================================
# Step 1: --pr flag precedence
# =====================================================================

@test "--pr 231 -> code-review with prNumber=231 (no gh probe)" {
  nogh="$(empty_path_for_no_gh)"
  # Even with gh absent, --pr wins.
  PATH="$nogh" run bash "$SCRIPT" "FEAT-026" --pr 231
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"code-review"'* ]]
  [[ "$output" == *'"prNumber":231'* ]]
}

@test "--pr precedence even when a test plan exists" {
  nogh="$(empty_path_for_no_gh)"
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  PATH="$nogh" run bash "$SCRIPT" "FEAT-026" --pr 999
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"code-review"'* ]]
  [[ "$output" == *'"prNumber":999'* ]]
}

# =====================================================================
# Step 2: open PR via gh
# =====================================================================

@test "gh pr list returns open PR -> code-review with that number" {
  write_gh_stub
  GH_PR_LIST_STDOUT='[{"number":50,"state":"OPEN"}]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-026"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"code-review"'* ]]
  [[ "$output" == *'"prNumber":50'* ]]
}

@test "FEAT- prefix uses branch prefix feat in gh pr list --head" {
  write_gh_stub
  GH_PR_LIST_STDOUT='[{"number":10,"state":"OPEN"}]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-100"
  [ "$status" -eq 0 ]
  grep -F "TRACE:gh:pr list --head feat/FEAT-100-*" "$TRACER"
}

@test "CHORE- prefix uses branch prefix chore in gh pr list --head" {
  write_gh_stub
  GH_PR_LIST_STDOUT='[{"number":11,"state":"OPEN"}]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "CHORE-200"
  [ "$status" -eq 0 ]
  grep -F "TRACE:gh:pr list --head chore/CHORE-200-*" "$TRACER"
}

@test "BUG- prefix uses branch prefix fix in gh pr list --head" {
  write_gh_stub
  GH_PR_LIST_STDOUT='[{"number":12,"state":"OPEN"}]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "BUG-300"
  [ "$status" -eq 0 ]
  grep -F "TRACE:gh:pr list --head fix/BUG-300-*" "$TRACER"
}

@test "gh pr list returns empty array -> falls through" {
  write_gh_stub
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  GH_PR_LIST_STDOUT='[]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-026"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"test-plan"'* ]]
}

@test "gh pr list returns non-empty array missing 'number' field -> [warn] and fall-through" {
  write_gh_stub
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  err_file="${FIXTURE_DIR}/err_malformed"
  out_file="${FIXTURE_DIR}/out_malformed"
  GH_PR_LIST_STDOUT='[{"state":"OPEN"}]' \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" "FEAT-026" 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] detect-review-mode: gh response missing 'number' field; falling through."* ]]
  [[ "$out" == *'"mode":"test-plan"'* ]]
}

@test "gh unauthenticated -> silently skip, no [warn]" {
  write_gh_stub
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  err_file="${FIXTURE_DIR}/err_unauth"
  out_file="${FIXTURE_DIR}/out_unauth"
  GH_AUTH_RC=1 \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" "FEAT-026" 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  # No [warn] should be emitted for the unauth path.
  [[ "$err" != *"[warn]"* ]]
  [[ "$out" == *'"mode":"test-plan"'* ]]
}

@test "gh missing entirely -> silently skip, no [warn], fall-through" {
  nogh="$(empty_path_for_no_gh)"
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  err_file="${FIXTURE_DIR}/err_nogh"
  out_file="${FIXTURE_DIR}/out_nogh"
  PATH="$nogh" bash "$SCRIPT" "FEAT-026" 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" != *"[warn]"* ]]
  [[ "$out" == *'"mode":"test-plan"'* ]]
  [[ "$out" == *"qa/test-plans/QA-plan-FEAT-026.md"* ]]
}

# =====================================================================
# Step 3: test plan present
# =====================================================================

@test "no --pr, no open PR, test plan present -> test-plan" {
  write_gh_stub
  : > "qa/test-plans/QA-plan-FEAT-026.md"
  GH_PR_LIST_STDOUT='[]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-026"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"test-plan"'* ]]
  [[ "$output" == *'"testPlanPath":"qa/test-plans/QA-plan-FEAT-026.md"'* ]]
}

# =====================================================================
# Step 4: fallback to standard
# =====================================================================

@test "no --pr, no open PR, no test plan -> standard" {
  write_gh_stub
  GH_PR_LIST_STDOUT='[]' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "FEAT-026"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"standard"'* ]]
}

@test "no --pr, gh missing, no test plan -> standard" {
  nogh="$(empty_path_for_no_gh)"
  PATH="$nogh" run bash "$SCRIPT" "FEAT-026"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode":"standard"'* ]]
}
