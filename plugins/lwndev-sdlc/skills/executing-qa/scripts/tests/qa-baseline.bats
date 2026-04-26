#!/usr/bin/env bats
# Bats test suite for qa-baseline.sh (FEAT-030 / Phase 4).
#
# Covers:
#   * init — writes marker with current HEAD SHA; idempotent.
#   * clear — removes marker; exit 0 when marker absent.
#   * Exit 2 — missing subcommand, missing ID, unknown subcommand.

SCRIPT_DIR=""
SCRIPT=""

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${SCRIPT_DIR}/qa-baseline.sh"

  TMPDIR_TEST="$(mktemp -d)"

  # Init a real git repo so git rev-parse HEAD works.
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email "test@bats"
  git -C "$TMPDIR_TEST" config user.name "Bats Test"
  printf 'placeholder\n' > "$TMPDIR_TEST/README"
  git -C "$TMPDIR_TEST" add README
  git -C "$TMPDIR_TEST" commit -q -m "init"

  cd "$TMPDIR_TEST"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---------------------------------------------------------------------------
# init subcommand
# ---------------------------------------------------------------------------

@test "init: writes marker file containing current HEAD SHA" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT" init "FEAT-030"
  [ "$status" -eq 0 ]
  [ -f ".sdlc/qa/.executing-qa-baseline-FEAT-030" ]
  expected_sha="$(git rev-parse HEAD)"
  written_sha="$(cat .sdlc/qa/.executing-qa-baseline-FEAT-030)"
  [ "$written_sha" = "$expected_sha" ]
}

@test "init: idempotent — re-running init overwrites marker with current HEAD" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT" init "FEAT-030"
  [ "$status" -eq 0 ]

  # Make a new commit so HEAD advances.
  printf 'more\n' >> "$TMPDIR_TEST/README"
  git -C "$TMPDIR_TEST" add README
  git -C "$TMPDIR_TEST" commit -q -m "second"

  run bash "$SCRIPT" init "FEAT-030"
  [ "$status" -eq 0 ]

  expected_sha="$(git rev-parse HEAD)"
  written_sha="$(cat .sdlc/qa/.executing-qa-baseline-FEAT-030)"
  [ "$written_sha" = "$expected_sha" ]
}

@test "init: creates .sdlc/qa directory if absent" {
  cd "$TMPDIR_TEST"
  [ ! -d ".sdlc/qa" ]
  run bash "$SCRIPT" init "FEAT-999"
  [ "$status" -eq 0 ]
  [ -d ".sdlc/qa" ]
  [ -f ".sdlc/qa/.executing-qa-baseline-FEAT-999" ]
}

# ---------------------------------------------------------------------------
# clear subcommand
# ---------------------------------------------------------------------------

@test "clear: removes existing marker, exits 0" {
  cd "$TMPDIR_TEST"
  mkdir -p .sdlc/qa
  touch ".sdlc/qa/.executing-qa-baseline-FEAT-030"

  run bash "$SCRIPT" clear "FEAT-030"
  [ "$status" -eq 0 ]
  [ ! -f ".sdlc/qa/.executing-qa-baseline-FEAT-030" ]
}

@test "clear: exits 0 even when marker is absent" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT" clear "FEAT-030"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Exit 2 — bad args
# ---------------------------------------------------------------------------

@test "no args → exit 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "subcommand only, no ID → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT" init
  [ "$status" -eq 2 ]
}

@test "unknown subcommand → exit 2" {
  cd "$TMPDIR_TEST"
  run bash "$SCRIPT" bogus "FEAT-030"
  [ "$status" -eq 2 ]
}
