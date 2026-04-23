#!/usr/bin/env bats
# Bats fixture for pr-diff-vs-plan.sh (FEAT-026 / FR-6).
#
# Covers every drift class (deleted / renamed / signature-changed /
# content-changed), the graceful-skip path (gh missing, gh pr diff failure),
# exit codes 0/1/2, and the edge cases enumerated in the FEAT-026 testing
# section (empty diff, binary-only diff, malformed pr-number).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/pr-diff-vs-plan.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  mkdir -p "$STUB_DIR"

  # Default test plan referencing each artifact class we may flag.
  TEST_PLAN="${FIXTURE_DIR}/testplan.md"
  cat > "$TEST_PLAN" <<'EOF'
# QA Plan

## Scenarios

[P0] Tests `getSourcePlugins` behavior | mode: executable | expected: works
[P1] Tests `scripts/foo.sh` | mode: executable | expected: exits 0
[P2] Tests `scripts/legacy.ts` | mode: executable | expected: no regression
[P1] Tests `old/path.ts` post-rename | mode: executable | expected: still imports
EOF
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- stub writers ----------

write_gh_stub_diff() {
  # Writes a `gh` stub that prints $GH_DIFF_STDOUT on `gh pr diff` and exits
  # with $GH_DIFF_RC.
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr diff")
    rc="${GH_DIFF_RC:-0}"
    err="${GH_DIFF_ERR:-}"
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$err" >&2
      exit "$rc"
    fi
    if [ -n "${GH_DIFF_STDOUT:-}" ]; then
      printf '%s' "${GH_DIFF_STDOUT}"
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
  for bin in bash env awk sed grep tr cut wc mktemp head tail cat printf chmod rm mkdir ls test dirname basename sort jq uniq; do
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
# Arg-validation
# =====================================================================

@test "missing both args -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: pr-diff-vs-plan.sh"* ]]
}

@test "missing <test-plan> arg -> exit 2" {
  run bash "$SCRIPT" "42"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: pr-diff-vs-plan.sh"* ]]
}

@test "non-integer <pr-number> -> exit 2" {
  run bash "$SCRIPT" "abc" "$TEST_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "negative <pr-number> -> exit 2" {
  run bash "$SCRIPT" "-1" "$TEST_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "zero <pr-number> -> exit 2" {
  run bash "$SCRIPT" "0" "$TEST_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "float <pr-number> -> exit 2" {
  run bash "$SCRIPT" "1.5" "$TEST_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "hex <pr-number> -> exit 2" {
  run bash "$SCRIPT" "0x10" "$TEST_PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "non-existent test-plan file -> exit 1" {
  run bash "$SCRIPT" "42" "${FIXTURE_DIR}/nope.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read test-plan"* ]]
}

# =====================================================================
# Graceful-skip paths
# =====================================================================

@test "gh not on PATH -> exit 0, [warn] gh CLI not found, empty stdout" {
  nogh="$(empty_path_for_no_gh)"
  err_file="${FIXTURE_DIR}/err"
  out_file="${FIXTURE_DIR}/out"
  PATH="$nogh" bash "$SCRIPT" "42" "$TEST_PLAN" 2>"$err_file" >"$out_file"
  rc=$?
  [ "$rc" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] gh CLI not found"* ]]
  [ -z "$out" ]
}

@test "gh pr diff fails -> exit 0, [warn] gh pr diff failed, empty stdout" {
  write_gh_stub_diff
  err_file="${FIXTURE_DIR}/err"
  out_file="${FIXTURE_DIR}/out"
  GH_DIFF_RC=1 GH_DIFF_ERR="authentication required" \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" "42" "$TEST_PLAN" 2>"$err_file" >"$out_file"
  rc=$?
  [ "$rc" -eq 0 ]
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[warn] gh pr diff failed"* ]]
  [[ "$err" == *"authentication required"* ]]
  [ -z "$out" ]
}

# =====================================================================
# Drift classification — happy paths
# =====================================================================

@test "deleted file referenced in test plan -> flaggedFiles with drift: deleted" {
  write_gh_stub_diff
  read -r -d '' GH_DIFF_STDOUT <<'EOF' || true
diff --git a/scripts/foo.sh b/scripts/foo.sh
deleted file mode 100644
--- a/scripts/foo.sh
+++ /dev/null
EOF
  GH_DIFF_STDOUT="$GH_DIFF_STDOUT" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"drift":"deleted"'* ]]
  [[ "$output" == *"scripts/foo.sh"* ]]
}

@test "renamed file referenced in test plan -> flaggedFiles with drift: renamed and both paths" {
  write_gh_stub_diff
  read -r -d '' GH_DIFF_STDOUT <<'EOF' || true
diff --git a/old/path.ts b/new/path.ts
similarity index 95%
rename from old/path.ts
rename to new/path.ts
--- a/old/path.ts
+++ b/new/path.ts
EOF
  GH_DIFF_STDOUT="$GH_DIFF_STDOUT" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"drift":"renamed"'* ]]
  [[ "$output" == *"old/path.ts"* ]]
  [[ "$output" == *"new/path.ts"* ]]
}

@test "content-changed file referenced in test plan -> flaggedFiles with drift: content-changed" {
  write_gh_stub_diff
  read -r -d '' GH_DIFF_STDOUT <<'EOF' || true
diff --git a/scripts/legacy.ts b/scripts/legacy.ts
--- a/scripts/legacy.ts
+++ b/scripts/legacy.ts
@@ -1 +1 @@
-a
+b
EOF
  GH_DIFF_STDOUT="$GH_DIFF_STDOUT" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"drift":"content-changed"'* ]]
  [[ "$output" == *"scripts/legacy.ts"* ]]
}

@test "changed function signature referenced as identifier -> flaggedSignatures + flaggedIdentifiers" {
  write_gh_stub_diff
  read -r -d '' GH_DIFF_STDOUT <<'EOF' || true
diff --git a/scripts/legacy.ts b/scripts/legacy.ts
--- a/scripts/legacy.ts
+++ b/scripts/legacy.ts
-function getSourcePlugins(arg1)
+function getSourcePlugins(arg1, arg2)
EOF
  GH_DIFF_STDOUT="$GH_DIFF_STDOUT" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"flaggedSignatures":['*'"drift":"signature-changed"'* ]]
  [[ "$output" == *'"flaggedIdentifiers":['*'"drift":"signature-changed"'* ]]
  [[ "$output" == *"getSourcePlugins"* ]]
}

# =====================================================================
# Edge-case diffs
# =====================================================================

@test "empty diff -> all three arrays empty, exit 0" {
  write_gh_stub_diff
  GH_DIFF_STDOUT="" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"flaggedFiles":[]'* ]]
  [[ "$output" == *'"flaggedIdentifiers":[]'* ]]
  [[ "$output" == *'"flaggedSignatures":[]'* ]]
}

@test "binary-only diff -> empty flaggedSignatures, empty flaggedIdentifiers" {
  write_gh_stub_diff
  read -r -d '' GH_DIFF_STDOUT <<'EOF' || true
diff --git a/image.png b/image.png
index abcdef..123456 100644
Binary files a/image.png and b/image.png differ
EOF
  GH_DIFF_STDOUT="$GH_DIFF_STDOUT" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"flaggedSignatures":[]'* ]]
  [[ "$output" == *'"flaggedIdentifiers":[]'* ]]
}

@test "output shape: all three arrays always present" {
  write_gh_stub_diff
  GH_DIFF_STDOUT="" \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "42" "$TEST_PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"flaggedFiles":'* ]]
  [[ "$output" == *'"flaggedIdentifiers":'* ]]
  [[ "$output" == *'"flaggedSignatures":'* ]]
}
