#!/usr/bin/env bash
# verify-build-health.sh — Shared build-health gate for phase-completion skills (BUG-013).
#
# Usage:
#   verify-build-health.sh [--no-interactive] [--include-validate] [--skip-test]
#
# Detects the canonical build-health scripts from `package.json` (`lint`,
# `format:check`, `test`, `build`) and runs each detected script in that order,
# halting on the first non-zero exit. `--skip-test` excludes `test` from the
# detection list (used by `executing-qa` Step 5.5, where the QA framework has
# already executed the full test suite).
#
# Auto-fix path:
#   In interactive mode (TTY on stdin AND no `--no-interactive`), a `lint` or
#   `format:check` failure prompts the caller to run the matching `lint:fix` /
#   `format` script (only when present in `scripts`) and re-run the original
#   check. The auto-fix branch is suppressed with `--no-interactive` or when
#   stdin is not a TTY (orchestrator-forked subagents have no user channel).
#
# Validate opt-in:
#   `npm run validate` is excluded from the default detection list because it
#   is project-specific. Pass `--include-validate` to also run it (after
#   `build`) when the script exists in `package.json`.
#
# Graceful skip:
#   If `package.json` is absent, no recognized scripts exist, or `npm` is not
#   on PATH, exits 0 with an `[info]` line on stderr describing the skip.
#
# Output:
#   Failing command stdout/stderr is surfaced verbatim to the caller's stderr
#   so the orchestrator's parser can pick up the failure context. Tagged
#   structured logs (`[info]`, `[warn]`, `[error]`) frame the run.
#
# Exit codes:
#   0  all detected (and selected) scripts passed, or no work to do.
#   1  any script failed and was not corrected by the auto-fix branch.
#   2  malformed args.

set -euo pipefail

# ---------- arg parsing ----------
NO_INTERACTIVE=0
INCLUDE_VALIDATE=0
SKIP_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --no-interactive)
      NO_INTERACTIVE=1
      shift
      ;;
    --include-validate)
      INCLUDE_VALIDATE=1
      shift
      ;;
    --skip-test)
      SKIP_TEST=1
      shift
      ;;
    -h|--help)
      sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[error] verify-build-health: unknown argument: $1" >&2
      echo "usage: verify-build-health.sh [--no-interactive] [--include-validate] [--skip-test]" >&2
      exit 2
      ;;
  esac
done

# ---------- locate package.json ----------
# Walk from $PWD up to filesystem root. The first ancestor with package.json wins.
find_package_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/package.json" ]; then
      printf '%s/package.json\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PKG_JSON="$(find_package_json || true)"

if [ -z "${PKG_JSON:-}" ]; then
  echo "[info] verify-build-health: no package.json found, skipping." >&2
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[info] verify-build-health: npm not on PATH, skipping." >&2
  exit 0
fi

# ---------- detect scripts ----------
# Read the `scripts` block from package.json. Prefer jq when available;
# fall back to a small grep/sed extractor.
script_exists() {
  local name="$1"
  if [ "${HAVE_JQ:-0}" -eq 1 ]; then
    jq -e --arg n "$name" '.scripts[$n] // empty' "$PKG_JSON" >/dev/null 2>&1
    return $?
  fi
  # Fallback: match a "name": "..." line under the scripts object.
  # Extract scripts block with awk, then grep for the key.
  awk '
    /"scripts"[[:space:]]*:[[:space:]]*\{/ { in_block = 1; depth = 1; next }
    in_block {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) { in_block = 0; exit } }
      }
      print
    }
  ' "$PKG_JSON" | grep -Eq "^[[:space:]]*\"${name}\"[[:space:]]*:"
}

HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
fi

# Surface malformed package.json instead of silently treating it as
# "no recognized scripts" (which the jq -e in script_exists would otherwise do).
if [ "$HAVE_JQ" -eq 1 ] && ! jq empty "$PKG_JSON" >/dev/null 2>&1; then
  echo "[error] verify-build-health: malformed package.json at ${PKG_JSON} (jq parse failed)" >&2
  exit 1
fi

# ---------- runner helpers ----------
run_npm_script() {
  # Args: <human-label> <script-name>
  # `test` is invoked as `npm test`; everything else as `npm run <name>`.
  local label="$1"
  local script="$2"
  echo "[info] verify-build-health: running ${label} (npm ${script}) ..." >&2
  if [ "$script" = "test" ]; then
    npm test
  else
    npm run "$script"
  fi
}

is_tty_stdin() {
  if [ "$NO_INTERACTIVE" -eq 1 ]; then
    return 1
  fi
  if [ ! -t 0 ]; then
    return 1
  fi
  return 0
}

prompt_yes() {
  # Args: <prompt-text>
  # Returns 0 if user accepts, 1 otherwise.
  local prompt="$1"
  local reply
  printf '%s [y/N]: ' "$prompt" >&2
  if ! IFS= read -r reply; then
    return 1
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Try to recover from a lint/format failure via the matching auto-fix script.
# Args: <failed-script> <fix-script>
# Returns 0 on successful re-run, 1 on user decline or re-run failure.
try_autofix() {
  local failed="$1"
  local fix="$2"
  if ! script_exists "$fix"; then
    echo "[info] verify-build-health: no ${fix} script available; cannot auto-fix." >&2
    return 1
  fi
  if ! is_tty_stdin; then
    return 1
  fi
  if ! prompt_yes "verify-build-health: ${failed} failed. Run npm run ${fix} and retry?"; then
    return 1
  fi
  echo "[info] verify-build-health: running auto-fix (npm run ${fix}) ..." >&2
  if ! npm run "$fix"; then
    echo "[error] verify-build-health: ${fix} exited non-zero; halting." >&2
    return 1
  fi
  echo "[info] verify-build-health: re-running ${failed} after auto-fix ..." >&2
  if [ "$failed" = "test" ]; then
    npm test
  else
    npm run "$failed"
  fi
  return $?
}

# Run a script with optional auto-fix recovery. Halts the script via `exit 1`
# on unrecoverable failure.
# Args: <human-label> <script-name> <autofix-script-or-empty>
run_or_halt() {
  local label="$1"
  local script="$2"
  local fix="${3:-}"

  if ! script_exists "$script"; then
    return 0
  fi

  if run_npm_script "$label" "$script"; then
    return 0
  fi

  echo "[error] verify-build-health: ${label} (${script}) failed." >&2

  if [ -n "$fix" ]; then
    if try_autofix "$script" "$fix"; then
      echo "[info] verify-build-health: ${label} passed after auto-fix." >&2
      return 0
    fi
  fi

  exit 1
}

# ---------- detection summary ----------
detected=()
for s in lint format:check test build; do
  if [ "$SKIP_TEST" -eq 1 ] && [ "$s" = "test" ]; then
    continue
  fi
  if script_exists "$s"; then
    detected+=("$s")
  fi
done

if [ "$INCLUDE_VALIDATE" -eq 1 ] && script_exists validate; then
  detected+=("validate")
fi

if [ "${#detected[@]}" -eq 0 ]; then
  echo "[info] verify-build-health: no recognized scripts in package.json, skipping." >&2
  exit 0
fi

echo "[info] verify-build-health: detected scripts: ${detected[*]}" >&2

# ---------- run sequence ----------
run_or_halt lint        lint         lint:fix
run_or_halt format-check format:check format
if [ "$SKIP_TEST" -ne 1 ]; then
  run_or_halt test      test         ""
fi
run_or_halt build       build        ""

if [ "$INCLUDE_VALIDATE" -eq 1 ]; then
  run_or_halt validate validate ""
fi

echo "[info] verify-build-health: all checks passed." >&2
exit 0
