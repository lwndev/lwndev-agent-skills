#!/usr/bin/env bats
# Bats fixture for create-pr.sh (FR-9).
#
# Strategy: PATH-prepend a stub directory containing fake `git` and `gh`
# scripts. Behavior is controlled by env vars exported by each test:
#   GIT_PUSH_FAIL=1   → fake git's `push` subcommand returns 1
#   GH_FAIL=1         → fake gh returns 1
# Side effects recorded by stubs:
#   ${STUBDIR}/gh.args   → JSON-ish lines of args gh was invoked with
#   ${STUBDIR}/gh.body   → body content passed via --body
#   ${STUBDIR}/gh.invoked → presence indicates gh was called at all

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CREATE_PR="${SCRIPT_DIR}/create-pr.sh"
  TMPDIR_TEST="$(mktemp -d)"
  STUBDIR="${TMPDIR_TEST}/bin"
  mkdir -p "$STUBDIR"

  # Fake `git`: supports rev-parse --abbrev-ref HEAD and push.
  cat > "${STUBDIR}/git" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
  rev-parse)
    if [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then
      echo "feat/FEAT-020-demo"
      exit 0
    fi
    # Fall through to failure.
    echo "fake-git: unexpected rev-parse args: $*" >&2
    exit 99
    ;;
  push)
    if [ -n "${GIT_PUSH_FAIL:-}" ]; then
      echo "fatal: unable to push (stub)" >&2
      exit 1
    fi
    echo "To origin: pushed (stub)"
    exit 0
    ;;
  *)
    echo "fake-git: unhandled subcommand: $*" >&2
    exit 99
    ;;
esac
STUBEOF
  chmod +x "${STUBDIR}/git"

  # Fake `gh`: expects `pr create --title <t> --body <b>`.
  cat > "${STUBDIR}/gh" <<STUBEOF
#!/usr/bin/env bash
touch "${STUBDIR}/gh.invoked"
# Persist every arg on its own line.
: > "${STUBDIR}/gh.args"
for a in "\$@"; do
  printf '%s\n' "\$a" >> "${STUBDIR}/gh.args"
done
# Capture --body for assertions.
body=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --body)
      body="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' "\$body" > "${STUBDIR}/gh.body"
if [ -n "\${GH_FAIL:-}" ]; then
  echo "gh: stub failure" >&2
  exit 1
fi
echo "https://github.com/example/repo/pull/123"
exit 0
STUBEOF
  chmod +x "${STUBDIR}/gh"

  PATH="${STUBDIR}:${PATH}"
  export PATH
  unset GIT_PUSH_FAIL
  unset GH_FAIL
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

@test "happy path: pushes, calls gh, prints PR URL, exit 0" {
  run bash "$CREATE_PR" feat FEAT-020 "shared scripts library"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/example/repo/pull/123"* ]]
  [ -f "${STUBDIR}/gh.invoked" ]
  # Title assembly: "feat(FEAT-020): shared scripts library"
  grep -qF -- "feat(FEAT-020): shared scripts library" "${STUBDIR}/gh.args"
}

@test "--closes #42: body contains 'Closes #42'" {
  run bash "$CREATE_PR" feat FEAT-020 "shared scripts" --closes "#42"
  [ "$status" -eq 0 ]
  grep -qF "Closes #42" "${STUBDIR}/gh.body"
}

@test "no --closes: body contains no 'Closes' line" {
  run bash "$CREATE_PR" feat FEAT-020 "shared scripts"
  [ "$status" -eq 0 ]
  ! grep -qF "Closes " "${STUBDIR}/gh.body"
}

@test "body contains the Claude Code trailer" {
  run bash "$CREATE_PR" feat FEAT-020 "shared scripts"
  [ "$status" -eq 0 ]
  grep -qF "Generated with" "${STUBDIR}/gh.body"
  grep -qF "Claude Code" "${STUBDIR}/gh.body"
}

@test "--closes with empty string: exit 2, gh not invoked" {
  run bash "$CREATE_PR" feat FEAT-020 "x" --closes ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "--closes bare '#': exit 2, gh not invoked" {
  run bash "$CREATE_PR" feat FEAT-020 "x" --closes "#"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "git push failure: exit 1, gh NOT invoked" {
  GIT_PUSH_FAIL=1
  export GIT_PUSH_FAIL
  run bash "$CREATE_PR" feat FEAT-020 "x"
  [ "$status" -eq 1 ]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "gh pr create failure: exit 1" {
  GH_FAIL=1
  export GH_FAIL
  run bash "$CREATE_PR" feat FEAT-020 "x"
  [ "$status" -eq 1 ]
  # gh WAS invoked before it failed.
  [ -f "${STUBDIR}/gh.invoked" ]
}

@test "invalid type: exit 2, git not pushed, gh not invoked" {
  run bash "$CREATE_PR" badtype FEAT-020 "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  [ ! -f "${STUBDIR}/gh.invoked" ]
}

@test "missing required args: exit 2" {
  run bash "$CREATE_PR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"error:"* ]]
  run bash "$CREATE_PR" feat
  [ "$status" -eq 2 ]
  run bash "$CREATE_PR" feat FEAT-020
  [ "$status" -eq 2 ]
}

@test "--closes= form (inline value) works too" {
  run bash "$CREATE_PR" feat FEAT-020 "x" --closes=#7
  [ "$status" -eq 0 ]
  grep -qF "Closes #7" "${STUBDIR}/gh.body"
}

@test "summary with '&' survives body substitution (bash 5.2+ patsub_replacement guard)" {
  # Regression guard: bash 5.2 enables patsub_replacement by default, which
  # makes `&' in the replacement of `${var//pat/rep}` refer to the matched
  # text. create-pr.sh disables that shopt at entry so user-supplied summaries
  # containing `&' stay literal. If someone removes the shopt line, this test
  # catches the regression even before the vitest qa scenario runs.
  run bash "$CREATE_PR" feat FEAT-020 "tests & fixtures & more"
  [ "$status" -eq 0 ]
  grep -qF "tests & fixtures & more" "${STUBDIR}/gh.body"
  # And make sure the body does not contain any leaked placeholder fragment
  # that would indicate the `&' re-expanded into the matched `${SUMMARY}`.
  ! grep -qF '${SUMMARY}' "${STUBDIR}/gh.body"
}
