#!/usr/bin/env bats
# Bats fixture for verify-build-health.sh (BUG-013).
#
# Covers: detection of package.json scripts, fail-fast on first failure,
# graceful skip when package.json/npm absent, --include-validate opt-in,
# auto-fix opt-in path (interactive), --no-interactive suppression,
# and non-TTY suppression.

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  VERIFY="${SCRIPT_DIR}/verify-build-health.sh"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"

  # Create a stub `npm` on PATH that records invocations and dispatches
  # to scripts defined in `npm-mock.env`.
  STUB_BIN="$TMPDIR_TEST/_bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/npm" <<'STUB'
#!/usr/bin/env bash
# Stub npm. Logs each invocation to $TMPDIR_TEST/npm.log and reads
# expected exit codes from $TMPDIR_TEST/npm-codes.env.
LOG="$TMPDIR_TEST/npm.log"
CODES="$TMPDIR_TEST/npm-codes.env"

# Build a target token. `npm test` runs the test script directly;
# `npm run <name>` runs <name>.
target=""
if [ "$1" = "test" ]; then
  target="test"
elif [ "$1" = "run" ] && [ -n "${2:-}" ]; then
  target="$2"
else
  echo "stub-npm: unhandled args: $*" >&2
  exit 99
fi

echo "$target" >> "$LOG"

code=0
if [ -f "$CODES" ]; then
  # Format: "target=code" lines. First match wins.
  while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    if [ "$key" = "$target" ]; then
      code="$val"
      break
    fi
  done < "$CODES"
fi

echo "stub-npm: ran $target (exit $code)"
exit "$code"
STUB
  chmod +x "$STUB_BIN/npm"
  export TMPDIR_TEST
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  if [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ]; then
    rm -rf "$TMPDIR_TEST"
  fi
}

# ---------- helpers ----------
write_pkg() {
  # Args: <space-separated script names>
  local entries=""
  local first=1
  for s in "$@"; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      entries+=","
    fi
    entries+=$'\n    "'"$s"'": "exit 0"'
  done
  cat > "$TMPDIR_TEST/package.json" <<EOF
{
  "name": "fixture",
  "scripts": {${entries}
  }
}
EOF
}

set_codes() {
  : > "$TMPDIR_TEST/npm-codes.env"
  for entry in "$@"; do
    echo "$entry" >> "$TMPDIR_TEST/npm-codes.env"
  done
}

# ---------- pass / detection ----------
@test "pass case: all detected scripts succeed" {
  write_pkg lint format:check test build
  set_codes
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"detected scripts: lint format:check test build"* ]]
  [[ "$output" == *"all checks passed"* ]]
  # Confirm each was invoked exactly once, in order.
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint
format:check
test
build" ]
}

@test "subset detection: only test + build present, lint and format absent" {
  write_pkg test build
  set_codes
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "test
build" ]
}

# ---------- fail-fast ----------
@test "fail-fast: first failing script halts; later scripts not invoked" {
  write_pkg lint format:check test build
  set_codes "lint=2"
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 1 ]
  [[ "$output" == *"lint (lint) failed"* ]]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint" ]
}

@test "fail-fast at format-check: lint passes, format:check fails, test/build skipped" {
  write_pkg lint format:check test build
  set_codes "format:check=1"
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 1 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint
format:check" ]
}

# ---------- graceful skip ----------
@test "no package.json: exit 0 with [info] skip message" {
  rm -f "$TMPDIR_TEST/package.json"
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"no package.json found, skipping."* ]]
}

@test "package.json with no relevant scripts: exit 0 with [info] skip message" {
  cat > "$TMPDIR_TEST/package.json" <<'EOF'
{
  "name": "fixture",
  "scripts": {
    "start": "node index.js"
  }
}
EOF
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"no recognized scripts in package.json"* ]]
}

@test "npm absent on PATH: exit 0 with [info] skip message" {
  write_pkg lint test
  # Override PATH with a directory that does not contain npm.
  empty_path="$TMPDIR_TEST/_emptybin"
  mkdir -p "$empty_path"
  run env PATH="$empty_path:/usr/bin:/bin" bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm not on PATH, skipping."* ]]
}

# ---------- --include-validate ----------
@test "--include-validate: validate runs after build when present" {
  write_pkg lint test build validate
  set_codes
  run bash "$VERIFY" --no-interactive --include-validate
  [ "$status" -eq 0 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint
test
build
validate" ]
}

@test "default (no --include-validate): validate is skipped even when present" {
  write_pkg lint test build validate
  set_codes
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 0 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint
test
build" ]
}

@test "--include-validate without validate script: still runs the rest, no error" {
  write_pkg lint test
  set_codes
  run bash "$VERIFY" --no-interactive --include-validate
  [ "$status" -eq 0 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint
test" ]
}

# ---------- non-TTY suppression ----------
@test "non-TTY (stdin redirected from /dev/null): no auto-fix prompt, fail-fast" {
  write_pkg lint lint:fix test
  set_codes "lint=2"
  # Stdin redirected from /dev/null. No --no-interactive flag, so the
  # suppression must come from the TTY check.
  run bash "$VERIFY" </dev/null
  [ "$status" -eq 1 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  # lint:fix should not have run; only lint was invoked.
  [ "$log" = "lint" ]
  # No prompt output to stderr.
  [[ "$output" != *"Run npm run lint:fix"* ]]
}

@test "--no-interactive flag: suppresses auto-fix even if lint:fix exists" {
  write_pkg lint lint:fix test
  set_codes "lint=2"
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 1 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint" ]
}

# ---------- auto-fix opt-in (interactive) ----------
@test "auto-fix accepted: lint fails, user accepts, lint:fix runs, lint re-runs and passes" {
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not available — required to simulate a TTY for auto-fix"
  fi
  write_pkg lint lint:fix format:check test
  # Sequenced npm stub: each invocation increments a counter so we can
  # script "first lint fails, lint:fix passes, second lint passes".
  cat > "$TMPDIR_TEST/_bin/npm" <<'STUB'
#!/usr/bin/env bash
LOG="$TMPDIR_TEST/npm.log"
COUNT_FILE="$TMPDIR_TEST/npm.count"

target=""
if [ "$1" = "test" ]; then
  target="test"
elif [ "$1" = "run" ] && [ -n "${2:-}" ]; then
  target="$2"
fi

count=0
[ -f "$COUNT_FILE" ] && count="$(cat "$COUNT_FILE")"
count=$((count + 1))
echo "$count" > "$COUNT_FILE"

echo "$count:$target" >> "$LOG"

# Sequence:
#   1: lint   -> fail (1)
#   2: lint:fix -> pass (0)
#   3: lint   -> pass (0)
#   4: format:check -> pass (0)
#   5: test   -> pass (0)
case "$count" in
  1) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$TMPDIR_TEST/_bin/npm"

  # Use expect to allocate a PTY and answer the prompt with "y".
  run expect -c "
    set timeout 10
    spawn -noecho bash $VERIFY
    expect {
      -re {Run npm run lint:fix and retry\?} {
        send \"y\r\"
        exp_continue
      }
      eof
    }
    catch wait result
    exit [lindex \$result 3]
  "
  [ "$status" -eq 0 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "1:lint
2:lint:fix
3:lint
4:format:check
5:test" ]
}

@test "auto-fix declined: lint fails, user declines via PTY, fail-fast at exit 1" {
  if ! command -v expect >/dev/null 2>&1; then
    skip "expect not available — required to simulate a TTY for auto-fix"
  fi
  write_pkg lint lint:fix
  set_codes "lint=1" "lint:fix=0"
  run expect -c "
    set timeout 10
    spawn -noecho bash $VERIFY
    expect {
      -re {Run npm run lint:fix and retry\?} {
        send \"n\r\"
        exp_continue
      }
      eof
    }
    catch wait result
    exit [lindex \$result 3]
  "
  [ "$status" -eq 1 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  [ "$log" = "lint" ]
}

@test "auto-fix unavailable: format:check fails but no format script defined → fail-fast" {
  # Only format:check defined, not format. The auto-fix branch must report
  # "no format script available" and halt. Non-interactive path is fine
  # because the absence of a format script halts before the prompt anyway.
  write_pkg lint format:check
  set_codes "format:check=1"
  run bash "$VERIFY" --no-interactive
  [ "$status" -eq 1 ]
  log="$(cat "$TMPDIR_TEST/npm.log")"
  # lint passed; format:check failed; format never invoked (no script).
  [ "$log" = "lint
format:check" ]
}

# ---------- malformed args ----------
@test "unknown argument: exit 2 with usage" {
  run bash "$VERIFY" --frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
  [[ "$output" == *"usage:"* ]]
}
