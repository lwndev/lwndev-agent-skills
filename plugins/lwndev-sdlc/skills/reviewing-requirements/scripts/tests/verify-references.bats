#!/usr/bin/env bats
# Bats fixture for verify-references.sh (FEAT-026 / FR-3).
#
# Uses PATH-shadowing stubs for `gh` and `git` to cover every classification
# branch (ok / moved / ambiguous / missing / unavailable) across the four
# reference categories (filePaths / identifiers / crossRefs / ghRefs).
#
# Also exercises the dual-shape dispatch (JSON literal vs file path) and the
# tolerant-forward shape handling (missing array keys treated as empty).

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/verify-references.sh"

  FIXTURE_DIR="$(mktemp -d)"
  STUB_DIR="${FIXTURE_DIR}/stubs"
  TRACER="${FIXTURE_DIR}/tracer.log"
  mkdir -p "$STUB_DIR"
  : > "$TRACER"

  export TRACER

  # Work in a hermetic dir so requirements/ globs resolve against fixtures.
  TEST_CWD="${FIXTURE_DIR}/work"
  mkdir -p "${TEST_CWD}/requirements/features"
  mkdir -p "${TEST_CWD}/requirements/chores"
  mkdir -p "${TEST_CWD}/requirements/bugs"
  cd "$TEST_CWD"
}

teardown() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

# ---------- stub writers ----------

write_git_stub() {
  # GIT_LS_FILES_STDOUT  — lines that `git ls-files` returns.
  # GIT_GREP_STDOUT      — output of `git grep -nF -- <id>` (newline-delimited
  #                        lines; empty = 0 matches). Passes stdin to the stub
  #                        via env var to sidestep trying to encode newlines
  #                        through the stub's argv.
  cat > "${STUB_DIR}/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:git:$*" >> "${TRACER}"
case "$1" in
  ls-files)
    if [ -n "${GIT_LS_FILES_STDOUT+x}" ]; then
      printf '%s' "${GIT_LS_FILES_STDOUT}"
    fi
    exit 0
    ;;
  grep)
    # Expect `git grep -nF -- <id>`; find the <id> argument.
    shift
    while [ $# -gt 0 ] && [[ "$1" == -* && "$1" != "--" ]]; do shift; done
    [ "$1" = "--" ] && shift
    id="${1:-}"
    # Look up per-id override in GIT_GREP_RESULTS env: `id1=N1;id2=N2`.
    if [ -n "${GIT_GREP_RESULTS:-}" ]; then
      IFS=';' read -ra pairs <<< "${GIT_GREP_RESULTS}"
      for p in "${pairs[@]}"; do
        pid="${p%%=*}"
        pcount="${p#*=}"
        if [ "$pid" = "$id" ]; then
          i=0
          while [ "$i" -lt "$pcount" ]; do
            printf 'file%d.ts:%d:%s\n' "$i" "$i" "$id"
            i=$((i+1))
          done
          exit 0
        fi
      done
    fi
    # Default: emit GIT_GREP_COUNT matches (0 if unset).
    count="${GIT_GREP_COUNT:-0}"
    i=0
    while [ "$i" -lt "$count" ]; do
      printf 'file%d.ts:%d:%s\n' "$i" "$i" "$id"
      i=$((i+1))
    done
    exit 0
    ;;
  remote)
    # verify-references.sh does not call `git remote`, but extract-references
    # does. Always succeed with no output.
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
}

write_gh_stub() {
  # GH_ISSUE_VIEW_RC    — exit code for `gh issue view` (default 0).
  # GH_ISSUE_VIEW_ERR   — stderr text when non-zero.
  # GH_ISSUE_VIEW_MAP   — per-issue RC override: `184=0;999=1`.
  # GH_ISSUE_VIEW_ERR_MAP — per-issue stderr: `999=not found;500=server 500`.
  # GH_AUTH_RC          — exit code for `gh auth status` (default 0).
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "TRACE:gh:$*" >> "${TRACER}"
case "$1" in
  auth)
    [ "$2" = "status" ] && exit "${GH_AUTH_RC:-0}"
    exit 0
    ;;
  issue)
    if [ "$2" = "view" ]; then
      num="$3"
      rc="${GH_ISSUE_VIEW_RC:-0}"
      err="${GH_ISSUE_VIEW_ERR:-}"
      if [ -n "${GH_ISSUE_VIEW_MAP:-}" ]; then
        IFS=';' read -ra pairs <<< "${GH_ISSUE_VIEW_MAP}"
        for p in "${pairs[@]}"; do
          pid="${p%%=*}"
          pv="${p#*=}"
          [ "$pid" = "$num" ] && rc="$pv"
        done
      fi
      if [ -n "${GH_ISSUE_VIEW_ERR_MAP:-}" ]; then
        IFS=';' read -ra pairs <<< "${GH_ISSUE_VIEW_ERR_MAP}"
        for p in "${pairs[@]}"; do
          pid="${p%%=*}"
          pv="${p#*=}"
          [ "$pid" = "$num" ] && err="$pv"
        done
      fi
      if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$err" >&2
        exit "$rc"
      fi
      printf '{"number":%s,"state":"OPEN"}' "$num"
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
  # Include a stubbed git that returns empty ls-files / zero-match grep so the
  # script's git calls succeed without real-repo coupling.
  cat > "$dir/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls-files) exit 0 ;;
  grep) exit 0 ;;
esac
exit 0
EOF
  chmod +x "$dir/git"
  printf '%s' "$dir"
}

# =====================================================================
# Arg-validation
# =====================================================================

@test "missing arg -> exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: verify-references.sh"* ]]
}

@test "unparseable JSON (neither file nor valid JSON) -> exit 1" {
  run bash "$SCRIPT" "totally-not-json-or-path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot parse JSON input"* ]]
}

# =====================================================================
# Shape invariant + dual-shape dispatch
# =====================================================================

@test "empty object -> five empty arrays" {
  PATH="${STUB_DIR}:${PATH}" write_git_stub
  PATH="${STUB_DIR}:${PATH}" write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "{}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[]'* ]]
  [[ "$output" == *'"moved":[]'* ]]
  [[ "$output" == *'"ambiguous":[]'* ]]
  [[ "$output" == *'"missing":[]'* ]]
  [[ "$output" == *'"unavailable":[]'* ]]
}

@test "missing array keys treated as empty (tolerant forward shape)" {
  write_git_stub
  write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":[]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[]'* ]]
  [[ "$output" == *'"missing":[]'* ]]
}

@test "dispatch: arg starting with { is treated as literal JSON" {
  write_git_stub
  write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":[],"identifiers":[],"crossRefs":[],"ghRefs":[]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[]'* ]]
}

@test "dispatch: arg is a file path containing JSON -> file is read" {
  write_git_stub
  write_gh_stub
  echo '{"filePaths":[],"identifiers":[],"crossRefs":[],"ghRefs":[]}' > input.json
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "input.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":[]'* ]]
}

@test "dispatch: non-existent path that is not valid JSON -> exit 1" {
  write_git_stub
  write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" "nosuchfile.json"
  [ "$status" -eq 1 ]
}

# =====================================================================
# filePaths classification
# =====================================================================

@test "filePaths: exact-path match -> ok" {
  write_git_stub
  write_gh_stub
  : > actual.md
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":["actual.md"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"category":"filePaths","ref":"actual.md","detail":"exact path exists"'* ]]
}

@test "filePaths: basename match at different path -> moved" {
  write_git_stub
  write_gh_stub
  # The ref does not exist on disk; but git ls-files contains a matching basename
  # at a different path.
  GIT_LS_FILES_STDOUT=$'other/path/foo.sh\nirrelevant.md\n' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":["scripts/foo.sh"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"moved":['* ]]
  [[ "$output" == *'"ref":"scripts/foo.sh"'* ]]
  [[ "$output" == *"other/path/foo.sh"* ]]
}

@test "filePaths: multiple basename matches -> ambiguous" {
  write_git_stub
  write_gh_stub
  GIT_LS_FILES_STDOUT=$'a/foo.sh\nb/foo.sh\nc/foo.sh\n' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":["scripts/foo.sh"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ambiguous":['* ]]
  [[ "$output" == *'"ref":"scripts/foo.sh"'* ]]
  [[ "$output" == *"multiple basename matches"* ]]
}

@test "filePaths: no match anywhere -> missing" {
  write_git_stub
  write_gh_stub
  GIT_LS_FILES_STDOUT=$'unrelated.md\n' \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"filePaths":["scripts/nowhere.sh"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"missing":['* ]]
  [[ "$output" == *'"ref":"scripts/nowhere.sh"'* ]]
}

# =====================================================================
# identifiers classification
# =====================================================================

@test "identifiers: 1..19 matches -> ok" {
  write_git_stub
  write_gh_stub
  GIT_GREP_COUNT=5 \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"identifiers":["somefunc"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"ref":"somefunc"'* ]]
  [[ "$output" == *'5 match(es)'* ]]
}

@test "identifiers: 0 matches -> missing" {
  write_git_stub
  write_gh_stub
  GIT_GREP_COUNT=0 \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"identifiers":["nowhere"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"missing":['* ]]
  [[ "$output" == *'"ref":"nowhere"'* ]]
}

@test "identifiers: 20+ matches -> ambiguous" {
  write_git_stub
  write_gh_stub
  GIT_GREP_COUNT=25 \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"identifiers":["common"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ambiguous":['* ]]
  [[ "$output" == *'"ref":"common"'* ]]
  [[ "$output" == *'25 matches'* ]]
}

@test "identifiers: 19 matches -> ok (threshold boundary)" {
  write_git_stub
  write_gh_stub
  GIT_GREP_COUNT=19 \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"identifiers":["edge19"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"ref":"edge19"'* ]]
}

@test "identifiers: 20 matches -> ambiguous (threshold boundary)" {
  write_git_stub
  write_gh_stub
  GIT_GREP_COUNT=20 \
    PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"identifiers":["edge20"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ambiguous":['* ]]
}

# =====================================================================
# crossRefs classification
# =====================================================================

@test "crossRefs: FEAT-020 with one matching file -> ok" {
  write_git_stub
  write_gh_stub
  : > requirements/features/FEAT-020-plugin-shared.md
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"crossRefs":["FEAT-020"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"category":"crossRefs","ref":"FEAT-020"'* ]]
}

@test "crossRefs: FEAT-999 no file -> missing" {
  write_git_stub
  write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"crossRefs":["FEAT-999"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"missing":['* ]]
  [[ "$output" == *'"ref":"FEAT-999"'* ]]
}

@test "crossRefs: CHORE-003 multiple files -> ambiguous" {
  write_git_stub
  write_gh_stub
  : > requirements/chores/CHORE-003-a.md
  : > requirements/chores/CHORE-003-b.md
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"crossRefs":["CHORE-003"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ambiguous":['* ]]
  [[ "$output" == *'"ref":"CHORE-003"'* ]]
}

# =====================================================================
# ghRefs classification
# =====================================================================

@test "ghRefs: gh succeeds -> ok" {
  write_git_stub
  write_gh_stub
  PATH="${STUB_DIR}:${PATH}" run bash "$SCRIPT" '{"ghRefs":["#184"]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":['* ]]
  [[ "$output" == *'"category":"ghRefs","ref":"#184"'* ]]
}

@test "ghRefs: 404 -> missing" {
  write_git_stub
  write_gh_stub
  err_file="${FIXTURE_DIR}/err_404"
  out_file="${FIXTURE_DIR}/out_404"
  GH_ISSUE_VIEW_RC=1 GH_ISSUE_VIEW_ERR="issue not found" \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" '{"ghRefs":["#999"]}' 2>"$err_file" >"$out_file"
  out="$(cat "$out_file")"
  [[ "$out" == *'"missing":['* ]]
  [[ "$out" == *'"ref":"#999"'* ]]
}

@test "ghRefs: gh non-404 error -> unavailable with [info]" {
  write_git_stub
  write_gh_stub
  err_file="${FIXTURE_DIR}/err_500"
  out_file="${FIXTURE_DIR}/out_500"
  GH_ISSUE_VIEW_RC=1 GH_ISSUE_VIEW_ERR="server error 500" \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" '{"ghRefs":["#42"]}' 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[info] verify-references: gh unavailable; 1 ghRefs marked unavailable."* ]]
  [[ "$out" == *'"unavailable":['* ]]
  [[ "$out" == *'"ref":"#42"'* ]]
}

@test "ghRefs: gh not on PATH -> unavailable with [info]" {
  nogh="$(empty_path_for_no_gh)"
  err_file="${FIXTURE_DIR}/err_nogh"
  out_file="${FIXTURE_DIR}/out_nogh"
  PATH="$nogh" bash "$SCRIPT" '{"ghRefs":["#1"]}' 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[info] verify-references: gh unavailable; 1 ghRefs marked unavailable."* ]]
  [[ "$out" == *'"unavailable":['* ]]
}

@test "ghRefs: gh unauthenticated -> unavailable with [info]" {
  write_git_stub
  write_gh_stub
  err_file="${FIXTURE_DIR}/err_unauth"
  out_file="${FIXTURE_DIR}/out_unauth"
  GH_AUTH_RC=1 \
    PATH="${STUB_DIR}:${PATH}" bash "$SCRIPT" '{"ghRefs":["#1"]}' 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  [[ "$err" == *"[info] verify-references: gh unavailable; 1 ghRefs marked unavailable."* ]]
  [[ "$out" == *'"unavailable":['* ]]
}

@test "ghRefs: multiple refs, gh unavailable -> single [info] line (not one per ref)" {
  nogh="$(empty_path_for_no_gh)"
  err_file="${FIXTURE_DIR}/err_multi"
  out_file="${FIXTURE_DIR}/out_multi"
  PATH="$nogh" bash "$SCRIPT" '{"ghRefs":["#1","#2","#3"]}' 2>"$err_file" >"$out_file"
  err="$(cat "$err_file")"
  out="$(cat "$out_file")"
  # Count the [info] emission lines — should be exactly one.
  info_count=$(printf '%s\n' "$err" | grep -c "\[info\] verify-references: gh unavailable" || true)
  [ "$info_count" = "1" ]
  [[ "$err" == *"3 ghRefs marked unavailable"* ]]
  [[ "$out" == *'"unavailable":['* ]]
}
