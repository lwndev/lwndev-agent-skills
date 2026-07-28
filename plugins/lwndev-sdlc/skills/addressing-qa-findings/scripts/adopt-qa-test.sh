#!/usr/bin/env bash
set -euo pipefail

# adopt-qa-test.sh (FEAT-032 FR-5 / FR-6) — Adopt a QA-authored test into a
# *.qa.* sibling next to its peer test, via `git mv`. This script is the SOLE
# owner of QA-test deletion per FR-13 (the move IS the deletion).
#
# Usage:
#   adopt-qa-test.sh <qa-test-path>
#
# Behavior:
#   1. Determines the project's primary test framework via
#      capability-discovery.sh (or honors $QA_FRAMEWORK_OVERRIDE for tests).
#   2. Dispatches per-framework:
#        vitest / jest -> parse ES `import` / CJS `require` statements,
#                         resolve the SUT module, locate the existing peer test
#                         `<base>.test.{ts,tsx,js,jsx,mjs,cjs}`.
#        bats          -> parse `load '<file>'` and `source '<file>'` statements,
#                         locate the peer `<base>.bats` next to the loaded
#                         shell script.
#        pytest / go-test -> exit 2 with structured "framework not supported in
#                         v1" reason.
#   3. Computes the sibling target path:
#        `<existing-test-dir>/<base>.qa.<ext>`
#      where `<base>` is the peer test's base name without `.test` (vitest/jest)
#      or without `.bats` (bats), and `<ext>` mirrors the original QA test's
#      extension.
#   4. Runs `git mv <qa-test-path> <new-path>`.
#   5. Prints the new path on stdout (single line, trailing newline).
#
# Exit codes:
#   0  success — adopted; new path on stdout
#   1  filesystem / `git mv` failure (target already exists, file outside repo,
#      etc.) — git stderr passes through
#   2  SUT cannot be determined — no resolvable imports, no existing peer test,
#      a single imported SUT whose base name matches multiple ambiguous peers
#      (with no other SUT resolving singularly), or framework not supported in
#      v1. Multiple resolvable peers across distinct SUTs are tolerated: the
#      lexicographically-first peer by full repo-relative path is chosen.
#
# On exit 2, a structured stderr line of the form:
#   adopt-qa-test: <path>: <reason>
# is emitted (load-bearing — orchestrator pause UI surfaces this verbatim per
# FR-5).

usage() {
  echo "Usage: adopt-qa-test.sh <qa-test-path>" >&2
}

if [[ $# -ne 1 ]]; then
  echo "Error: expected exactly 1 argument, got $#." >&2
  usage
  exit 2
fi

QA_PATH="$1"

if [[ -z "$QA_PATH" ]]; then
  echo "Error: <qa-test-path> is required." >&2
  usage
  exit 2
fi

if [[ ! -f "$QA_PATH" ]]; then
  echo "adopt-qa-test: ${QA_PATH}: file not found" >&2
  exit 2
fi

# Reject paths outside the repo (basic sanity).
if ! git ls-files --error-unmatch -- "$QA_PATH" >/dev/null 2>&1; then
  # Allow untracked QA tests too — `git mv` will refuse anyway. We only flag
  # the case where the path is plainly outside the repo or non-regular.
  :
fi

# --- Helpers ---------------------------------------------------------------

emit_fail() {
  # emit_fail <reason>
  echo "adopt-qa-test: ${QA_PATH}: $1" >&2
}

abs_dirname() {
  # Print the directory portion of a path. Avoids `realpath -m` which is
  # non-portable on macOS without coreutils. We do NOT resolve symlinks so the
  # path stays in the same shape (relative if input was relative, absolute if
  # input was absolute) — this keeps peer-test probes in the same path space
  # as the input QA file.
  local p="$1"
  dirname -- "$p"
}

# normpath <path> — collapse `..` and `./` segments lexically. Portable across
# macOS / Linux. Falls back to a textual best-effort if python3 unavailable.
normpath() {
  local p="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$p"
  else
    echo "$p"
  fi
}

# Determine the framework by consulting capability-discovery.sh, unless an
# override is provided (used by tests).
detect_framework() {
  if [[ -n "${QA_FRAMEWORK_OVERRIDE:-}" ]]; then
    echo "$QA_FRAMEWORK_OVERRIDE"
    return 0
  fi

  local capability_script=""
  local self_dir
  self_dir="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # Prefer co-located sibling so source-tree invocations always use the matching
  # version. Fall back to CLAUDE_PLUGIN_ROOT only when the co-located script is
  # missing (e.g., when this script itself runs from a cache).
  if [[ -f "${self_dir}/../../executing-qa/scripts/capability-discovery.sh" ]]; then
    capability_script="${self_dir}/../../executing-qa/scripts/capability-discovery.sh"
  elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    capability_script="${CLAUDE_PLUGIN_ROOT}/skills/executing-qa/scripts/capability-discovery.sh"
  fi

  if [[ ! -f "$capability_script" ]]; then
    echo "" # caller treats empty as unknown
    return 0
  fi

  local report
  if ! report="$(bash "$capability_script" "$(pwd)" 2>/dev/null)"; then
    echo ""
    return 0
  fi

  # framework field is `null` JSON or a string.
  local fw
  fw="$(echo "$report" | jq -r '.framework // empty' 2>/dev/null || true)"
  echo "$fw"
}

# --- Vitest / Jest dispatch ------------------------------------------------

# parse_js_imports <file>
# Emits one resolved-relative-or-absolute import target per line. Only relative
# imports (`./` or `../`) are considered for SUT resolution because absolute /
# package-name imports (`react`, `@scope/pkg`, `node:fs`) are not source files
# in this repo.
parse_js_imports() {
  local file="$1"
  # ES imports: `import ... from '<path>'` / `import '<path>'`
  # CJS requires: `require('<path>')` / `require("<path>")`
  # Also: dynamic `import('<path>')`.
  # Use awk for portable extraction across BSD/GNU sed differences.
  awk '
    {
      line = $0
      while (match(line, /from[[:space:]]+["\x27][^"\x27]+["\x27]/)) {
        m = substr(line, RSTART, RLENGTH)
        gsub(/^from[[:space:]]+["\x27]/, "", m)
        gsub(/["\x27]$/, "", m)
        print m
        line = substr(line, RSTART + RLENGTH)
      }
    }
    {
      line = $0
      while (match(line, /require\(["\x27][^"\x27]+["\x27]\)/)) {
        m = substr(line, RSTART, RLENGTH)
        gsub(/^require\(["\x27]/, "", m)
        gsub(/["\x27]\)$/, "", m)
        print m
        line = substr(line, RSTART + RLENGTH)
      }
    }
    {
      line = $0
      while (match(line, /import\(["\x27][^"\x27]+["\x27]\)/)) {
        m = substr(line, RSTART, RLENGTH)
        gsub(/^import\(["\x27]/, "", m)
        gsub(/["\x27]\)$/, "", m)
        print m
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$file" 2>/dev/null \
    | grep -E '^(\.|/)' || true
}

# resolve_js_sut <qa-file> <import-spec>
# Resolves a relative import spec against the QA file's directory and returns
# the absolute SUT path WITHOUT extension. Caller probes extensions.
resolve_js_sut() {
  local qa_file="$1"
  local spec="$2"
  local qa_dir
  qa_dir="$(abs_dirname "$qa_file")"
  if [[ "$spec" = /* ]]; then
    normpath "$spec"
  else
    normpath "${qa_dir}/${spec}"
  fi
}

# locate_js_peer_test <sut-no-ext>
# Probes for an existing peer test for the SUT in the canonical naming
# convention `<base>.test.<ext>`. Probe order:
#   1. Co-located: `<sut-dir>/<base>.test.<ext>`
#   2. `__tests__` sibling: `<sut-dir>/__tests__/<base>.test.<ext>`
#   3. Parallel test root: `tests/**/<base>.test.<ext>` (find with bounded depth)
# Emits the peer-test path on stdout, or empty when none found.
locate_js_peer_test() {
  local sut_no_ext="$1"
  local sut_dir sut_base
  sut_dir="$(dirname -- "$sut_no_ext")"
  sut_base="$(basename -- "$sut_no_ext")"
  local ext
  for ext in ts tsx js jsx mjs cjs; do
    local candidate="${sut_dir}/${sut_base}.test.${ext}"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  for ext in ts tsx js jsx mjs cjs; do
    local candidate="${sut_dir}/__tests__/${sut_base}.test.${ext}"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  # Parallel test root: search under tests/ for <base>.test.<ext>.
  if [[ -d tests ]]; then
    local found
    found="$(find tests -maxdepth 6 \
      \( -name "${sut_base}.test.ts" \
         -o -name "${sut_base}.test.tsx" \
         -o -name "${sut_base}.test.js" \
         -o -name "${sut_base}.test.jsx" \
         -o -name "${sut_base}.test.mjs" \
         -o -name "${sut_base}.test.cjs" \
      \) -type f 2>/dev/null | head -n 2)"
    local count
    count="$(echo "$found" | grep -c '.' || true)"
    if [[ "$count" -eq 1 ]]; then
      echo "$found"
      return 0
    fi
    # Multiple peer matches for this single SUT base under the test root: emit a
    # sentinel the caller recognizes as per-SUT ambiguity. The caller tolerates it
    # when another SUT resolves singularly (multi_seen is skipped); only when NO
    # SUT resolves singularly does it surface the multi-peer reason (seen_count=0).
    if [[ "$count" -gt 1 ]]; then
      echo "<<MULTI>>"
      return 0
    fi
  fi
  echo ""
}

dispatch_vitest_jest() {
  local qa_file="$1"
  local imports
  if ! imports="$(parse_js_imports "$qa_file")" || [[ -z "$imports" ]]; then
    emit_fail "no resolvable imports found in QA test"
    exit 2
  fi

  local peers=""
  local seen_count=0
  local resolved=""
  local multi_seen=0
  while IFS= read -r spec; do
    [[ -z "$spec" ]] && continue
    local sut_no_ext
    sut_no_ext="$(resolve_js_sut "$qa_file" "$spec")"
    # Strip a trailing extension if the import included one (e.g. './foo.ts').
    sut_no_ext="${sut_no_ext%.ts}"
    sut_no_ext="${sut_no_ext%.tsx}"
    sut_no_ext="${sut_no_ext%.js}"
    sut_no_ext="${sut_no_ext%.jsx}"
    sut_no_ext="${sut_no_ext%.mjs}"
    sut_no_ext="${sut_no_ext%.cjs}"
    local peer
    peer="$(locate_js_peer_test "$sut_no_ext")"
    if [[ "$peer" = "<<MULTI>>" ]]; then
      multi_seen=1
      continue
    fi
    if [[ -n "$peer" ]]; then
      # Collect unique peers.
      if ! echo "$peers" | grep -qxF "$peer" 2>/dev/null; then
        peers="${peers}${peer}"$'\n'
        seen_count=$((seen_count + 1))
        resolved="$peer"
      fi
    fi
  done <<EOF
$imports
EOF

  if [[ "$seen_count" -eq 0 ]]; then
    # No SUT resolved to a singular peer. Distinguish the two zero-resolved
    # causes so the FR-5 pause UI reason is accurate:
    #   - multi_seen=1: at least one SUT base matched 2+ peers under tests/ and
    #     none resolved singularly — peers exist but are ambiguous for that SUT.
    #   - else: genuinely no peer test exists for any imported SUT.
    if [[ "$multi_seen" -eq 1 ]]; then
      emit_fail "multiple plausible peer tests match a single imported SUT; cannot disambiguate"
      exit 2
    fi
    emit_fail "no existing peer test found for any imported SUT"
    exit 2
  fi

  # Multiple resolved peers: pick the lexicographically-first by full repo-relative
  # path. LC_ALL=C pins byte-order comparison, making the pick stable across
  # locales and machines (P0 determinism requirement).
  resolved="$(printf '%s\n' "$peers" | grep -v '^$' | LC_ALL=C sort | head -n 1)"

  # Compute target: <peer-dir>/<peer-base-without-.test><.qa><.ext-of-qa>
  local peer_dir peer_file peer_base
  peer_dir="$(dirname -- "$resolved")"
  peer_file="$(basename -- "$resolved")"
  # Strip `.test.<ext>` from peer_file to derive base.
  peer_base="${peer_file%.test.*}"

  local qa_ext="${qa_file##*.}"
  local target
  target="$(normpath "${peer_dir}/${peer_base}.qa.test.${qa_ext}")"

  if [[ -e "$target" ]]; then
    echo "Error: target path already exists: $target" >&2
    exit 1
  fi

  if ! git mv "$qa_file" "$target"; then
    exit 1
  fi
  echo "$target"
}

# --- Bats dispatch ---------------------------------------------------------

parse_bats_loads() {
  local file="$1"
  # Match: `load '<file>'`, `load "<file>"`, `load <file>` (unquoted),
  # `source '<file>'`, `source "<file>"`, `. '<file>'`.
  #
  # The git-env sanitizer load is dropped: it is a test helper every .bats file
  # in this repo carries unconditionally (issue #326), never a SUT. Left in, it
  # makes `$loads` non-empty for every input, so the "no resolvable load/source
  # directives" branch below becomes unreachable and a QA test that loads no SUT
  # at all is misreported as "no existing peer .bats test found".
  grep -hE "^[[:space:]]*(load|source|\.)[[:space:]]+['\"]?[^'\"]+['\"]?" "$file" 2>/dev/null \
    | sed -E "s/^[[:space:]]*(load|source|\.)[[:space:]]+//" \
    | sed -E "s/^['\"]//; s/['\"]$//" \
    | grep -v '^$' \
    | grep -vE 'helpers/git-env(\.bash)?$' \
    || true
}

locate_bats_peer() {
  local loaded="$1"
  local qa_dir="$2"
  # Resolve `<loaded>` against `qa_dir`.
  local candidate="$loaded"
  if [[ "$candidate" != /* ]]; then
    candidate="${qa_dir}/${candidate}"
  fi
  # Bats-loaded scripts often omit the .sh suffix; probe both forms.
  local probe
  for probe in "$candidate" "${candidate}.sh" "${candidate}.bash"; do
    if [[ -f "$probe" ]]; then
      # The peer test is `<basename-without-suffix>.bats` next to the loaded
      # shell script, OR a sibling `.bats` of the same base.
      local d b
      d="$(dirname -- "$probe")"
      b="$(basename -- "$probe")"
      b="${b%.sh}"
      b="${b%.bash}"
      local peer="${d}/${b}.bats"
      if [[ -f "$peer" ]]; then
        echo "$peer"
        return 0
      fi
    fi
  done
  echo ""
}

dispatch_bats() {
  local qa_file="$1"
  local qa_dir
  qa_dir="$(abs_dirname "$qa_file")"
  local loads
  loads="$(parse_bats_loads "$qa_file" || true)"

  if [[ -z "$loads" ]]; then
    emit_fail "no resolvable load/source directives found in QA bats test"
    exit 2
  fi

  local peers=""
  local seen_count=0
  local resolved=""
  while IFS= read -r loaded; do
    [[ -z "$loaded" ]] && continue
    local peer
    peer="$(locate_bats_peer "$loaded" "$qa_dir")"
    if [[ -n "$peer" ]]; then
      if ! echo "$peers" | grep -qxF "$peer" 2>/dev/null; then
        peers="${peers}${peer}"$'\n'
        seen_count=$((seen_count + 1))
        resolved="$peer"
      fi
    fi
  done <<EOF
$loads
EOF

  if [[ "$seen_count" -eq 0 ]]; then
    emit_fail "no existing peer .bats test found for any loaded script"
    exit 2
  fi

  # Multiple resolved peers: pick the lexicographically-first by full repo-relative
  # path. LC_ALL=C pins byte-order comparison, making the pick stable across
  # locales and machines (P0 determinism requirement).
  resolved="$(printf '%s\n' "$peers" | grep -v '^$' | LC_ALL=C sort | head -n 1)"

  local peer_dir peer_file peer_base
  peer_dir="$(dirname -- "$resolved")"
  peer_file="$(basename -- "$resolved")"
  peer_base="${peer_file%.bats}"
  local target
  target="$(normpath "${peer_dir}/${peer_base}.qa.bats")"

  if [[ -e "$target" ]]; then
    echo "Error: target path already exists: $target" >&2
    exit 1
  fi

  if ! git mv "$qa_file" "$target"; then
    exit 1
  fi
  echo "$target"
}

# --- Main ------------------------------------------------------------------

# Decide framework dispatch from QA file extension first (faster/deterministic),
# falling back to capability-discovery.sh when ambiguous.
EXT="${QA_PATH##*.}"
case "$EXT" in
  ts|tsx|js|jsx|mjs|cjs)
    dispatch_vitest_jest "$QA_PATH"
    exit 0
    ;;
  bats)
    dispatch_bats "$QA_PATH"
    exit 0
    ;;
  py)
    emit_fail "framework not supported in v1: pytest"
    exit 2
    ;;
  go)
    emit_fail "framework not supported in v1: go-test"
    exit 2
    ;;
  *)
    # Fall back to capability-discovery.sh when the extension is unrecognized.
    FRAMEWORK="$(detect_framework || true)"
    case "$FRAMEWORK" in
      vitest|jest)
        dispatch_vitest_jest "$QA_PATH"
        exit 0
        ;;
      pytest)
        emit_fail "framework not supported in v1: pytest"
        exit 2
        ;;
      go-test)
        emit_fail "framework not supported in v1: go-test"
        exit 2
        ;;
      *)
        emit_fail "unrecognized QA test extension and no supported framework detected"
        exit 2
        ;;
    esac
    ;;
esac
