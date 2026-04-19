#!/usr/bin/env bash
set -euo pipefail

# capability-discovery.sh — Inspect a consumer repo and emit a JSON capability report.
#
# Usage:
#   capability-discovery.sh <consumer-repo-root> [ID]
#
# Detects test frameworks in deterministic order (vitest → jest → pytest → go test)
# and degrades gracefully to `mode: "exploratory-only"` when none found. The report
# is written to /tmp/qa-capability-{ID}.json when an ID is provided, and also
# emitted on stdout.
#
# Exit codes:
#   0 — success (including graceful exploratory-only degradation)
#   1 — fatal error (bad arguments or missing consumer repo root)

if [[ $# -lt 1 ]]; then
  echo "Error: consumer repo root path is required." >&2
  echo "Usage: $0 <consumer-repo-root> [ID]" >&2
  exit 1
fi

REPO_ROOT="$1"
ID="${2:-}"

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "Error: consumer repo root does not exist: $REPO_ROOT" >&2
  exit 1
fi

# --- Initialize report state ---------------------------------------------------
FRAMEWORK=""
LANGUAGE=""
PACKAGE_MANAGER=""
TEST_COMMAND=""
MODE="exploratory-only"
NOTES=()

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Helpers -------------------------------------------------------------------

# pkg_has_dep <key> : returns 0 when package.json has <key> under dependencies
# or devDependencies. Relies on jq.
pkg_has_dep() {
  local key="$1"
  local pkg_json="$REPO_ROOT/package.json"
  [[ -f "$pkg_json" ]] || return 1
  jq -e --arg k "$key" \
    '((.dependencies // {}) | has($k)) or ((.devDependencies // {}) | has($k))' \
    "$pkg_json" >/dev/null 2>&1
}

# pkg_script <name> : prints the value of scripts.<name> if present.
pkg_script() {
  local name="$1"
  local pkg_json="$REPO_ROOT/package.json"
  [[ -f "$pkg_json" ]] || return 1
  jq -er --arg n "$name" '(.scripts // {})[$n] // empty' "$pkg_json" 2>/dev/null
}

# has_config_file <name> ... : returns 0 when any of the listed files exists
# directly under REPO_ROOT.
has_config_file() {
  local f
  for f in "$@"; do
    [[ -f "$REPO_ROOT/$f" ]] && return 0
  done
  return 1
}

# find_bounded <args...> : run find within REPO_ROOT with a bounded depth and
# node_modules pruned. Prints matches.
find_bounded() {
  find "$REPO_ROOT" \
    -maxdepth 5 \
    \( -path '*/node_modules' -o -path '*/.git' \) -prune -o \
    "$@" \
    -print 2>/dev/null
}

add_note() {
  NOTES+=("$1")
}

# --- Detection: package manager (for npm-family frameworks) --------------------
detect_package_manager() {
  if [[ -f "$REPO_ROOT/package-lock.json" ]]; then
    PACKAGE_MANAGER="npm"
  elif [[ -f "$REPO_ROOT/yarn.lock" ]]; then
    PACKAGE_MANAGER="yarn"
  elif [[ -f "$REPO_ROOT/pnpm-lock.yaml" ]]; then
    PACKAGE_MANAGER="pnpm"
  fi
}

# --- Detection: signals for each framework -------------------------------------

has_vitest_signal() {
  if pkg_has_dep "vitest"; then return 0; fi
  if has_config_file "vitest.config.ts" "vitest.config.js" "vitest.config.mjs"; then
    return 0
  fi
  return 1
}

has_jest_signal() {
  if pkg_has_dep "jest"; then return 0; fi
  if has_config_file "jest.config.ts" "jest.config.js" "jest.config.mjs" "jest.config.json"; then
    return 0
  fi
  return 1
}

has_pytest_signal() {
  if [[ -f "$REPO_ROOT/pyproject.toml" ]] && grep -q "pytest" "$REPO_ROOT/pyproject.toml" 2>/dev/null; then
    return 0
  fi
  if [[ -f "$REPO_ROOT/pytest.ini" ]]; then return 0; fi
  if [[ -d "$REPO_ROOT/tests" ]]; then
    # Any test_*.py under tests/ within bounded depth
    if find "$REPO_ROOT/tests" -maxdepth 4 -type f -name 'test_*.py' 2>/dev/null | head -n 1 | grep -q .; then
      return 0
    fi
  fi
  return 1
}

has_go_test_signal() {
  [[ -f "$REPO_ROOT/go.mod" ]] || return 1
  if find_bounded -type f -name '*_test.go' | head -n 1 | grep -q .; then
    return 0
  fi
  return 1
}

# --- Language inference --------------------------------------------------------
language_for_framework() {
  local fw="$1"
  case "$fw" in
    vitest|jest)
      if [[ -f "$REPO_ROOT/tsconfig.json" ]] || pkg_has_dep "typescript"; then
        echo "typescript"
      else
        echo "javascript"
      fi
      ;;
    pytest)
      echo "python"
      ;;
    go-test)
      echo "go"
      ;;
    *)
      echo ""
      ;;
  esac
}

# --- Test directory existence check (edge case 6) ------------------------------
warn_if_no_test_dir() {
  local fw="$1"
  case "$fw" in
    vitest|jest)
      # Conventional: __tests__/ anywhere (bounded), or a co-located *.test.{ts,js}
      local found
      found="$(find_bounded -type d -name '__tests__' | head -n 1)"
      if [[ -z "$found" ]]; then
        # Look for any *.test.ts/js as a secondary signal
        local any_tests
        any_tests="$(find_bounded -type f \( -name '*.test.ts' -o -name '*.test.js' -o -name '*.test.tsx' -o -name '*.test.jsx' \) | head -n 1)"
        if [[ -z "$any_tests" ]]; then
          add_note "no test directory found; skill will create __tests__ directory"
        fi
      fi
      ;;
    pytest)
      if [[ ! -d "$REPO_ROOT/tests" ]]; then
        add_note "no test directory found; skill will create tests directory"
      fi
      ;;
    go-test)
      # Already required a *_test.go to select go-test; no separate directory convention.
      :
      ;;
  esac
}

# --- Test-command resolution (edge case 2) -------------------------------------
resolve_test_command() {
  local fw="$1"
  local default_cmd=""
  case "$fw" in
    vitest)   default_cmd="npx vitest run" ;;
    jest)     default_cmd="npx jest" ;;
    pytest)   default_cmd="pytest" ;;
    go-test)  default_cmd="go test ./..." ;;
  esac

  # For npm-family frameworks, prefer scripts.test if it exists.
  case "$fw" in
    vitest|jest)
      local script_val
      if script_val="$(pkg_script test)"; then
        if [[ -n "$script_val" ]]; then
          # Emit package-manager-aware command.
          case "$PACKAGE_MANAGER" in
            yarn) TEST_COMMAND="yarn test" ;;
            pnpm) TEST_COMMAND="pnpm test" ;;
            *)    TEST_COMMAND="npm test" ;;
          esac
          return
        fi
      fi
      TEST_COMMAND="$default_cmd"
      add_note "no scripts.test entry; falling back to default runner: $default_cmd"
      ;;
    pytest|go-test)
      TEST_COMMAND="$default_cmd"
      ;;
  esac
}

# --- Main detection: first match wins, but note subsequent signals -------------
select_framework() {
  if has_vitest_signal; then FRAMEWORK="vitest"; fi

  if [[ -z "$FRAMEWORK" ]] && has_jest_signal; then
    FRAMEWORK="jest"
  elif [[ "$FRAMEWORK" == "vitest" ]] && has_jest_signal; then
    add_note "multiple frameworks detected (vitest, jest); selected vitest by precedence"
  fi

  if [[ -z "$FRAMEWORK" ]] && has_pytest_signal; then
    FRAMEWORK="pytest"
  elif [[ -n "$FRAMEWORK" && "$FRAMEWORK" != "pytest" ]] && has_pytest_signal; then
    add_note "additional framework detected (pytest); selected $FRAMEWORK by precedence"
  fi

  if [[ -z "$FRAMEWORK" ]] && has_go_test_signal; then
    FRAMEWORK="go-test"
  elif [[ -n "$FRAMEWORK" && "$FRAMEWORK" != "go-test" ]] && has_go_test_signal; then
    add_note "additional framework detected (go-test); selected $FRAMEWORK by precedence"
  fi
}

# --- Orchestrate ---------------------------------------------------------------
detect_package_manager
select_framework

if [[ -n "$FRAMEWORK" ]]; then
  MODE="test-framework"
  LANGUAGE="$(language_for_framework "$FRAMEWORK")"
  # go-test and pytest do not use an npm package manager; clear it.
  case "$FRAMEWORK" in
    pytest|go-test) PACKAGE_MANAGER="" ;;
  esac
  warn_if_no_test_dir "$FRAMEWORK"
  resolve_test_command "$FRAMEWORK"
else
  add_note "No supported framework detected. Detection attempted: vitest, jest, pytest, go test."
fi

# --- Build JSON via jq with injection-safe arg passing -------------------------
# Compose notes JSON array (handles 0-length safely via printf+jq -s).
NOTES_JSON="$(
  if [[ ${#NOTES[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\0' "${NOTES[@]}" | jq -Rrs 'split("\u0000") | map(select(length > 0))'
  fi
)"

# Represent nullable fields as explicit nulls when empty.
to_json_str_or_null() {
  if [[ -z "$1" ]]; then
    echo "null"
  else
    jq -Rn --arg v "$1" '$v'
  fi
}

FRAMEWORK_JSON="$(to_json_str_or_null "$FRAMEWORK")"
LANGUAGE_JSON="$(to_json_str_or_null "$LANGUAGE")"
PM_JSON="$(to_json_str_or_null "$PACKAGE_MANAGER")"
CMD_JSON="$(to_json_str_or_null "$TEST_COMMAND")"
ID_JSON="$(to_json_str_or_null "$ID")"

REPORT="$(
  jq -n \
    --argjson id "$ID_JSON" \
    --arg timestamp "$TIMESTAMP" \
    --arg mode "$MODE" \
    --argjson framework "$FRAMEWORK_JSON" \
    --argjson packageManager "$PM_JSON" \
    --argjson testCommand "$CMD_JSON" \
    --argjson language "$LANGUAGE_JSON" \
    --argjson notes "$NOTES_JSON" \
    '{
      id: $id,
      timestamp: $timestamp,
      mode: $mode,
      framework: $framework,
      packageManager: $packageManager,
      testCommand: $testCommand,
      language: $language,
      notes: $notes
    }
    | if $id == null then del(.id) else . end'
)"

echo "$REPORT"

if [[ -n "$ID" ]]; then
  OUT_PATH="/tmp/qa-capability-${ID}.json"
  echo "$REPORT" > "$OUT_PATH"
fi
