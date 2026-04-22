#!/usr/bin/env bats
# Bats fixture for preflight-checks.sh (FR-2).
#
# Stubs `git` and `gh` via PATH shadowing. Stubs are generated per-test so
# each case controls its own behavior.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PREFLIGHT="${SCRIPT_DIR}/preflight-checks.sh"
  STUB_DIR="$(mktemp -d)"
  # Put stubs first on PATH; keep the rest of PATH intact so jq / sed / awk /
  # bash / sleep / mktemp remain resolvable.
  export PATH="${STUB_DIR}:${PATH}"
}

teardown() {
  if [ -n "${STUB_DIR:-}" ] && [ -d "$STUB_DIR" ]; then
    rm -rf "$STUB_DIR"
  fi
}

# Helper: write a git stub that dispatches on the first arg.
# Usage:
#   write_git_stub <porcelain-output> <branch-output>
write_git_stub() {
  local porcelain="$1" branch="$2"
  cat > "${STUB_DIR}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "status" ] && [ "\$2" = "--porcelain" ]; then
  printf '%s' '${porcelain}'
  exit 0
fi
if [ "\$1" = "branch" ] && [ "\$2" = "--show-current" ]; then
  printf '%s\n' '${branch}'
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/git"
}

# Helper: write a gh stub.
# Usage:
#   write_gh_stub <mode>
# Modes:
#   ok                → OPEN + MERGEABLE happy path (PR #142 "Test title")
#   no-pr             → exit 1 (simulates "no PR for current branch")
#   closed            → OPEN replaced with CLOSED
#   conflicting       → mergeable=CONFLICTING
#   unknown-then-ok   → first call UNKNOWN, second call MERGEABLE
#   unknown-twice     → both calls UNKNOWN
write_gh_stub() {
  local mode="$1"
  local state_dir="${STUB_DIR}/gh-state"
  mkdir -p "$state_dir"
  echo 0 > "${state_dir}/calls"
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
# Handle \`gh auth status\` — always succeed in tests.
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit 0
fi
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  calls=\$(cat '${state_dir}/calls')
  calls=\$((calls + 1))
  echo \$calls > '${state_dir}/calls'
  mode='${mode}'
  case "\$mode" in
    ok)
      printf '{"number":142,"title":"Test title","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/foo/bar/pull/142"}\n'
      exit 0
      ;;
    no-pr)
      echo "no pull requests found for branch" >&2
      exit 1
      ;;
    closed)
      printf '{"number":142,"title":"Test title","state":"CLOSED","mergeable":"MERGEABLE","url":"https://github.com/foo/bar/pull/142"}\n'
      exit 0
      ;;
    conflicting)
      printf '{"number":142,"title":"Test title","state":"OPEN","mergeable":"CONFLICTING","url":"https://github.com/foo/bar/pull/142"}\n'
      exit 0
      ;;
    unknown-then-ok)
      if [ \$calls -eq 1 ]; then
        printf '{"number":142,"title":"Test title","state":"OPEN","mergeable":"UNKNOWN","url":"https://github.com/foo/bar/pull/142"}\n'
      else
        printf '{"number":142,"title":"Test title","state":"OPEN","mergeable":"MERGEABLE","url":"https://github.com/foo/bar/pull/142"}\n'
      fi
      exit 0
      ;;
    unknown-twice)
      printf '{"number":142,"title":"Test title","state":"OPEN","mergeable":"UNKNOWN","url":"https://github.com/foo/bar/pull/142"}\n'
      exit 0
      ;;
  esac
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/gh"
}

@test "happy path: clean tree + feature branch + open+mergeable PR → exit 0" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "ok"
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"prNumber":142'* ]]
  [[ "$output" == *'"prTitle":"Test title"'* ]]
  [[ "$output" == *'"prUrl":"https://github.com/foo/bar/pull/142"'* ]]
}

@test "dirty tree → exit 1 with 'working directory has uncommitted changes'" {
  write_git_stub " M some-file.txt" "feat/FEAT-022-foo"
  write_gh_stub "ok"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'working directory has uncommitted changes'* ]]
  [[ "$stderr" == *'[error] preflight: working directory has uncommitted changes'* ]] || \
    [[ "$output" == *'[error] preflight: working directory has uncommitted changes'* ]]
}

@test "on main → exit 1 with 'already on main/master'" {
  write_git_stub "" "main"
  write_gh_stub "ok"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'already on main/master; nothing to finalize'* ]]
}

@test "no PR → exit 1 with 'no PR found for current branch'" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "no-pr"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'no PR found for current branch'* ]]
}

@test "PR state CLOSED → exit 1 with 'PR is not open (state: CLOSED)'" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "closed"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'PR is not open (state: CLOSED)'* ]]
}

@test "PR mergeable CONFLICTING → exit 1 with 'PR is not mergeable (CONFLICTING)'" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "conflicting"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status":"abort"'* ]]
  [[ "$output" == *'PR is not mergeable (CONFLICTING)'* ]]
}

@test "UNKNOWN → retry → MERGEABLE → exit 0" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "unknown-then-ok"
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"prNumber":142'* ]]
}

@test "UNKNOWN → retry → still UNKNOWN → exit 0 with info note" {
  write_git_stub "" "feat/FEAT-022-foo"
  write_gh_stub "unknown-twice"
  # Capture stderr to file for isolated assertion; stdout to $output via run.
  run bash -c "bash '$PREFLIGHT' 2> '${STUB_DIR}/err'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  err_content="$(cat "${STUB_DIR}/err")"
  [[ "$err_content" == *'[info] PR mergeable state UNKNOWN after retry'* ]]
  [[ "$err_content" == *'proceeding'* ]]
}

@test "gh missing on PATH → exit 1 with missing-gh stderr" {
  # Create stub git only. Build a minimal PATH that has ONLY the directories
  # required for bash / awk / sed / mktemp / sleep / jq to resolve. We keep
  # /bin and /usr/bin (no gh there) and point STUB_DIR first.
  write_git_stub "" "feat/FEAT-022-foo"
  # Build a PATH with common system utility dirs but no homebrew (where gh
  # typically lives on macOS).
  mini_path="${STUB_DIR}:/usr/bin:/bin"
  PATH="$mini_path" run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'gh CLI not found on PATH'* ]] || \
    [[ "$output" == *'"status":"abort"'* ]]
}
