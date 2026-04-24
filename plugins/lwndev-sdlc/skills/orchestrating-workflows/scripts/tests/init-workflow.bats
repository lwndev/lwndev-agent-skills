#!/usr/bin/env bats
# Bats fixture for init-workflow.sh (FEAT-028 / FR-5).
#
# Covers:
#   * TYPE / prefix happy paths: feature|chore|bug each emit the projected
#     JSON with correct ID, type, complexity, issueRef.
#   * Active-marker test: .sdlc/workflows/.active exists AND contains the ID
#     after a successful run (and it is written BEFORE the advance step).
#   * Graceful-degradation: empty issueRef (no `## GitHub Issue` section),
#     stub returning failure, stub missing entirely.
#   * Error paths: missing args (2), unknown TYPE (2), non-existent artifact
#     (1), TYPE/filename-prefix mismatch (1 + `[warn] init-workflow: ...`).
#
# Fixture strategy: each test chdirs into a per-test mktemp dir so
# `.sdlc/workflows/` writes stay sandboxed. Stubs for `workflow-state.sh`
# and `extract-issue-ref.sh` are installed into a PATH-shadowed directory
# so the real scripts are never invoked.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
  INIT="${SCRIPT_DIR}/init-workflow.sh"
  TMPDIR_TEST="$(mktemp -d)"
  STUB_DIR="${TMPDIR_TEST}/stubs"
  mkdir -p "$STUB_DIR"

  # Seed fixture copies into the sandbox with ID-prefixed filenames so the
  # TYPE-prefix regex in init-workflow.sh succeeds.
  mkdir -p "${TMPDIR_TEST}/reqs"
  cp "${FIXTURES_DIR}/feature-requirement.md" "${TMPDIR_TEST}/reqs/FEAT-028-fixture.md"
  cp "${FIXTURES_DIR}/chore-requirement.md"   "${TMPDIR_TEST}/reqs/CHORE-001-fixture.md"
  cp "${FIXTURES_DIR}/bug-requirement.md"     "${TMPDIR_TEST}/reqs/BUG-001-fixture.md"
  cp "${FIXTURES_DIR}/requirement-no-issue.md" "${TMPDIR_TEST}/reqs/FEAT-028-no-issue.md"

  # Install the default stubs. Individual tests can overwrite them.
  install_workflow_state_stub
  install_extract_issue_ref_stub
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# Install a default workflow-state.sh stub that:
#   * init <ID> <TYPE>            → writes .sdlc/workflows/<ID>.json, exit 0
#   * classify-init <ID> <doc>    → echoes "medium", exit 0
#   * set-complexity <ID> <tier>  → exit 0 silently
#   * advance <ID> [doc]          → exit 0 silently
install_workflow_state_stub() {
  cat > "${STUB_DIR}/workflow-state.sh" <<'STUB'
#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  init)
    id="${1:-}"
    type="${2:-}"
    mkdir -p .sdlc/workflows
    cat > ".sdlc/workflows/${id}.json" <<EOF
{"id":"${id}","type":"${type}","currentStep":0,"status":"in-progress","pauseReason":null,"complexity":null,"complexityStage":"init"}
EOF
    echo "initialized ${id}"
    ;;
  classify-init)
    echo "medium"
    ;;
  set-complexity)
    # no-op
    ;;
  advance)
    # no-op
    ;;
  *)
    echo "stub: unknown command $cmd" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/workflow-state.sh"
}

install_extract_issue_ref_stub() {
  # Default: delegate to the real extract-issue-ref.sh (it is pure parse and
  # has its own tests).
  local real="${SCRIPT_DIR}/../../managing-work-items/scripts/extract-issue-ref.sh"
  cat > "${STUB_DIR}/extract-issue-ref.sh" <<STUB
#!/usr/bin/env bash
exec bash "${real}" "\$@"
STUB
  chmod +x "${STUB_DIR}/extract-issue-ref.sh"
}

# Emit the current sandbox PATH so tests can PATH-shadow with STUB_DIR first.
run_with_stubs() {
  PATH="${STUB_DIR}:${PATH}" run "$@"
}

get_field() {
  local json="$1"
  local key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r ".${key}"
  else
    printf '%s' "$json" | sed -E "s/.*\"${key}\":\"([^\"]*)\".*/\1/"
  fi
}

# ---- TYPE happy paths -------------------------------------------------------

@test "feature TYPE + feature artifact → emits id, type, complexity, issueRef" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" feature reqs/FEAT-028-fixture.md
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" id)" = "FEAT-028" ]
  [ "$(get_field "$output" type)" = "feature" ]
  [ "$(get_field "$output" complexity)" = "medium" ]
  [ "$(get_field "$output" issueRef)" = "#186" ]
}

@test "chore TYPE + chore artifact → type=chore" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" chore reqs/CHORE-001-fixture.md
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" id)" = "CHORE-001" ]
  [ "$(get_field "$output" type)" = "chore" ]
  [ "$(get_field "$output" issueRef)" = "#42" ]
}

@test "bug TYPE + bug artifact → type=bug" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" bug reqs/BUG-001-fixture.md
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" id)" = "BUG-001" ]
  [ "$(get_field "$output" type)" = "bug" ]
  [ "$(get_field "$output" issueRef)" = "#99" ]
}

# ---- TYPE / prefix mismatch --------------------------------------------------

@test "chore TYPE + FEAT-prefixed artifact → exit 1 with [warn] init-workflow" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" chore reqs/FEAT-028-fixture.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"[warn] init-workflow: could not extract"* ]] || \
    [[ "${stderr:-}" == *"[warn] init-workflow: could not extract"* ]]
}

# ---- active marker ----------------------------------------------------------

@test "active marker written before advance with ID contents" {
  cd "$TMPDIR_TEST"
  # Override the advance stub to inspect the marker at the moment advance is
  # called — if the marker is absent at that moment the composite ordering is
  # broken.
  cat > "${STUB_DIR}/workflow-state.sh" <<'STUB'
#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  init)
    id="${1:-}"
    type="${2:-}"
    mkdir -p .sdlc/workflows
    cat > ".sdlc/workflows/${id}.json" <<EOF
{"id":"${id}","type":"${type}"}
EOF
    ;;
  classify-init)
    echo "medium"
    ;;
  set-complexity)
    : # no-op
    ;;
  advance)
    # Assert the marker exists at the moment advance runs.
    if [ ! -f .sdlc/workflows/.active ]; then
      echo "FAIL: .active absent at advance time" >&2
      exit 99
    fi
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/workflow-state.sh"

  run_with_stubs bash "$INIT" feature reqs/FEAT-028-fixture.md
  [ "$status" -eq 0 ]
  [ -f .sdlc/workflows/.active ]
  [ "$(cat .sdlc/workflows/.active)" = "FEAT-028" ]
}

# ---- graceful issue-ref degradation -----------------------------------------

@test "artifact missing GitHub Issue section → issueRef empty, exit 0" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" feature reqs/FEAT-028-no-issue.md
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" issueRef)" = "" ]
}

@test "extract-issue-ref stub exits non-zero → issueRef empty, exit 0" {
  cd "$TMPDIR_TEST"
  cat > "${STUB_DIR}/extract-issue-ref.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub failure" >&2
exit 1
STUB
  chmod +x "${STUB_DIR}/extract-issue-ref.sh"
  run_with_stubs bash "$INIT" feature reqs/FEAT-028-fixture.md
  [ "$status" -eq 0 ]
  [ "$(get_field "$output" issueRef)" = "" ]
}

@test "extract-issue-ref not found on PATH and real script absent → issueRef empty, exit 0" {
  cd "$TMPDIR_TEST"
  # Remove the stub AND temporarily rename the real script so neither path
  # resolves. Restore the real script in a trap so other tests remain happy.
  rm -f "${STUB_DIR}/extract-issue-ref.sh"
  local real="${SCRIPT_DIR}/../../managing-work-items/scripts/extract-issue-ref.sh"
  local hidden="${real}.hidden-for-test"
  mv "$real" "$hidden"
  trap 'mv "'"$hidden"'" "'"$real"'"' EXIT

  run_with_stubs bash "$INIT" feature reqs/FEAT-028-fixture.md
  mv "$hidden" "$real"
  trap - EXIT

  [ "$status" -eq 0 ]
  [ "$(get_field "$output" issueRef)" = "" ]
}

# ---- arg / error paths -------------------------------------------------------

@test "missing args → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT"
  [ "$status" -eq 2 ]
}

@test "only TYPE (missing artifact-path) → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" feature
  [ "$status" -eq 2 ]
}

@test "unknown TYPE (task) → exit 2" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" task reqs/FEAT-028-fixture.md
  [ "$status" -eq 2 ]
}

@test "non-existent artifact → exit 1" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" feature reqs/does-not-exist.md
  [ "$status" -eq 1 ]
}

# ---- state file created on disk ---------------------------------------------

@test "state file .sdlc/workflows/<ID>.json exists after run" {
  cd "$TMPDIR_TEST"
  run_with_stubs bash "$INIT" feature reqs/FEAT-028-fixture.md
  [ "$status" -eq 0 ]
  [ -f .sdlc/workflows/FEAT-028.json ]
}
