#!/usr/bin/env bash
set -euo pipefail

# stop-hook.sh — Validate the version-2 QA results artifact.
#
# Reads Claude Code stop-hook JSON from stdin; checks that the
# executing-qa skill has produced a well-formed version-2 results
# artifact at qa/test-results/QA-results-{ID}.md. Grades on artifact
# structure (FEAT-018) rather than regex-matching the last assistant
# message.
#
# Exit codes:
#   0 — allow stop (artifact is valid; or skill not active; or stop_hook_active set)
#   2 — block stop (artifact missing or malformed; actionable error on stderr)
#
# Validation rules (FR-5 / FR-9):
#   1. Frontmatter present.
#   2. Frontmatter contains `version: 2`.
#   3. Frontmatter contains `verdict: <PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY>`.
#   4. `## Summary` and `## Capability Report` sections present.
#   5. For PASS/ISSUES-FOUND: `## Execution Results` contains Total:,
#      Passed:, Failed:, Errored:, Exit code: lines.
#      - PASS: Failed == 0 (verdict-vs-counts consistency).
#      - ISSUES-FOUND: at least one failing test listed in `## Findings`.
#   6. For ERROR: artifact contains a stack trace (a line with either a
#      language-specific stack-trace marker, e.g. `at ` / `Traceback`,
#      or an `Exit code:` line with a non-zero value).
#   7. For EXPLORATORY-ONLY: `## Exploratory Mode` section present with
#      a `Reason:` line.

ACTIVE_FILE=".sdlc/qa/.executing-active"
QA_RESULTS_DIR="qa/test-results"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [[ ! -f "$ACTIVE_FILE" ]]; then
  exit 0
fi

INPUT="$(cat)" || exit 0
if [[ -z "$INPUT" ]]; then
  exit 0
fi

STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  rm -f "$ACTIVE_FILE"
  exit 0
fi

MESSAGE="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")"

# ---------------------------------------------------------------------------
# Locate the results artifact.
# ---------------------------------------------------------------------------
RESULTS_PATH=""
if [[ -n "$MESSAGE" ]]; then
  CAND="$(echo "$MESSAGE" | grep -oE 'QA-results-[A-Za-z0-9_-]+\.md' | head -n 1 || true)"
  if [[ -n "$CAND" ]]; then
    RESULTS_PATH="${QA_RESULTS_DIR}/${CAND}"
  fi
fi

# If the message claims a verdict but no artifact file, that is the classic
# false-PASS failure mode from BUG-010 — block explicitly.
if [[ -z "$RESULTS_PATH" ]]; then
  if [[ -d "$QA_RESULTS_DIR" ]]; then
    # Only consider v2 results (those with `version: 2` in frontmatter).
    # Fall-back candidates are ranked newest-first by find -printf is not
    # portable on macOS, so use stat when narrowing down.
    MATCHES=()
    while IFS= read -r -d '' f; do
      MATCHES+=("$f")
    done < <(find "$QA_RESULTS_DIR" -maxdepth 1 -type f -name 'QA-results-*.md' -print0 2>/dev/null)
    # Filter to v2 (contains `version: 2` in frontmatter). If exactly one
    # v2 file exists, use it.
    V2_MATCHES=()
    for f in "${MATCHES[@]:-}"; do
      [[ -n "$f" ]] || continue
      if head -n 20 "$f" 2>/dev/null | grep -qE '^version[[:space:]]*:[[:space:]]*2[[:space:]]*$'; then
        V2_MATCHES+=("$f")
      fi
    done
    if [[ ${#V2_MATCHES[@]} -eq 1 ]]; then
      RESULTS_PATH="${V2_MATCHES[0]}"
    fi
  fi
fi

if [[ -z "$RESULTS_PATH" ]]; then
  echo "Stop hook: could not determine QA results artifact path from the last assistant message. Reference the file path in your final message (e.g., 'Results saved to qa/test-results/QA-results-FEAT-001.md')." >&2
  exit 2
fi

if [[ ! -f "$RESULTS_PATH" ]]; then
  echo "Stop hook: results artifact ${RESULTS_PATH} does not exist. The executing-qa skill must write the results file before stopping." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Parse frontmatter.
# ---------------------------------------------------------------------------
FIRST_LINE="$(head -n 1 "$RESULTS_PATH" 2>/dev/null || true)"
if [[ "$FIRST_LINE" == "<!--" ]]; then
  FM_START="$(awk '
    /^<!--/ { in_c = 1 }
    in_c && /-->/ { in_c = 0; next }
    !in_c && $0 == "---" { print NR; exit }
  ' "$RESULTS_PATH")"
else
  FM_START="$(awk '$0 == "---" { print NR; exit }' "$RESULTS_PATH")"
fi

if [[ -z "${FM_START:-}" ]]; then
  echo "Stop hook: results artifact ${RESULTS_PATH} is missing YAML frontmatter (expected leading '---' block with id, version, timestamp, verdict, persona)." >&2
  exit 2
fi

FRONTMATTER="$(awk -v start="$FM_START" '
  NR == start { in_fm = 1; next }
  in_fm && $0 == "---" { closed = 1; exit }
  in_fm
  END { if (!closed) exit 1 }
' "$RESULTS_PATH")" || FRONTMATTER=""

FM_DELIMS="$(awk -v start="$FM_START" '
  NR >= start && $0 == "---" { n++ }
  END { print n+0 }
' "$RESULTS_PATH")"

if [[ -z "$FRONTMATTER" || "$FM_DELIMS" -lt 2 ]]; then
  echo "Stop hook: results artifact ${RESULTS_PATH} has empty or unclosed frontmatter block (missing closing '---')." >&2
  exit 2
fi

# version: 2
if ! echo "$FRONTMATTER" | grep -qE '^[[:space:]]*version[[:space:]]*:[[:space:]]*2[[:space:]]*$'; then
  echo "Stop hook: results artifact ${RESULTS_PATH} is missing 'version: 2' in frontmatter. The FEAT-018 redesign requires version-2 artifacts." >&2
  exit 2
fi

# verdict: <enum>
VERDICT_LINE="$(echo "$FRONTMATTER" | grep -E '^[[:space:]]*verdict[[:space:]]*:' | head -n 1 || true)"
if [[ -z "$VERDICT_LINE" ]]; then
  echo "Stop hook: results artifact ${RESULTS_PATH} is missing 'verdict:' in frontmatter." >&2
  exit 2
fi
VERDICT="$(echo "$VERDICT_LINE" | sed -E 's/^[[:space:]]*verdict[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')"

case "$VERDICT" in
  PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY)
    ;;
  *)
    echo "Stop hook: results artifact ${RESULTS_PATH} verdict '${VERDICT}' is not one of PASS, ISSUES-FOUND, ERROR, EXPLORATORY-ONLY." >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# Required sections.
# ---------------------------------------------------------------------------
require_section() {
  local heading="$1"
  if ! grep -qE "^${heading}[[:space:]]*\$" "$RESULTS_PATH"; then
    echo "Stop hook: results artifact ${RESULTS_PATH} is missing required section '${heading}'." >&2
    exit 2
  fi
}

require_section '## Summary'
require_section '## Capability Report'
require_section '## Scenarios Run'
require_section '## Reconciliation Delta'

# ---------------------------------------------------------------------------
# Verdict-specific validation.
# ---------------------------------------------------------------------------

get_section_block() {
  # Print everything between `## <heading>` and the next `## ` or EOF.
  local heading="$1"
  sed -n "/^## ${heading}\$/,/^## /p" "$RESULTS_PATH" | sed '$d'
}

case "$VERDICT" in
  PASS|ISSUES-FOUND)
    if ! grep -qE '^## Execution Results[[:space:]]*$' "$RESULTS_PATH"; then
      echo "Stop hook: results artifact ${RESULTS_PATH} has verdict '${VERDICT}' but is missing '## Execution Results' section." >&2
      exit 2
    fi
    EXEC_BLOCK="$(get_section_block 'Execution Results')"
    # Required counter lines.
    for field in 'Total' 'Passed' 'Failed' 'Errored' 'Exit code'; do
      if ! echo "$EXEC_BLOCK" | grep -qE "^-[[:space:]]+${field}[[:space:]]*:"; then
        echo "Stop hook: results artifact ${RESULTS_PATH} '## Execution Results' is missing the '${field}:' line (required for verdict ${VERDICT})." >&2
        exit 2
      fi
    done

    # Extract Failed count; strip any trailing non-digits.
    FAILED_VAL="$(echo "$EXEC_BLOCK" | grep -E '^-[[:space:]]+Failed[[:space:]]*:' | head -n 1 | sed -E 's/^-[[:space:]]+Failed[[:space:]]*:[[:space:]]*//' | sed -E 's/[^0-9].*$//' )"
    if [[ -z "$FAILED_VAL" ]]; then
      echo "Stop hook: results artifact ${RESULTS_PATH} 'Failed:' line is not a valid number." >&2
      exit 2
    fi

    if [[ "$VERDICT" == "PASS" ]]; then
      if [[ "$FAILED_VAL" -gt 0 ]]; then
        echo "Stop hook: results artifact ${RESULTS_PATH} verdict is PASS but Failed=${FAILED_VAL} (>0). PASS requires zero failing tests — use ISSUES-FOUND instead." >&2
        exit 2
      fi
    fi

    if [[ "$VERDICT" == "ISSUES-FOUND" ]]; then
      # Require at least one entry in Findings listing a failing test name.
      if ! grep -qE '^## Findings[[:space:]]*$' "$RESULTS_PATH"; then
        echo "Stop hook: results artifact ${RESULTS_PATH} has verdict ISSUES-FOUND but is missing '## Findings' section." >&2
        exit 2
      fi
      FINDINGS_BLOCK="$(get_section_block 'Findings')"
      # Heuristic: at least one non-blank, non-placeholder line that names a
      # test. Accept list items starting with `- ` that contain either a
      # framework-specific test reference or an inline test/failing marker.
      # Patterns covered:
      #   - vitest/jest: `.spec.` / `.test.` filename fragments
      #   - python (partial): `_test.` fragment
      #   - go: `_test.go` filename
      #   - pytest: `module.py::test_name` nodeid notation
      #   - go: `--- FAIL: TestX` verbose-output prefix
      #   - go: `- FAIL TestX` / trailing `FAIL TestMain` summary form
      #   - inline markers: `test:` / `Test:` / `Failing test` / `failing case`
      if ! echo "$FINDINGS_BLOCK" | grep -qE '^-[[:space:]]+.*(\.(spec|test)\.|_test\.|_test\.go|\.py::|---[[:space:]]+FAIL:|FAIL[[:space:]]+Test|[Tt]est[[:space:]]*:|[Ff]ailing[[:space:]]*(test|case))'; then
        echo "Stop hook: results artifact ${RESULTS_PATH} has verdict ISSUES-FOUND but '## Findings' does not name any failing tests. Each finding must identify the failing test (e.g., test file path or test name)." >&2
        exit 2
      fi
    fi
    ;;

  ERROR)
    # Stack trace required somewhere in the artifact. Accept:
    #   - a line starting with `  at ` (JS/TS stack),
    #   - `Traceback` (Python),
    #   - `panic:` (Go),
    #   - `Error:` with a subsequent indented line,
    #   - or `Exit code:` with non-zero value.
    HAS_TRACE=false
    if grep -qE '^\s*at [A-Za-z_<(/.:]' "$RESULTS_PATH"; then HAS_TRACE=true; fi
    if grep -qE '^Traceback \(most recent call last\)' "$RESULTS_PATH"; then HAS_TRACE=true; fi
    if grep -qE '^panic:' "$RESULTS_PATH"; then HAS_TRACE=true; fi
    if grep -qE '^[[:space:]]*(goroutine [0-9]+ \[|[A-Za-z_][A-Za-z_0-9.]*\.go:[0-9]+)' "$RESULTS_PATH"; then HAS_TRACE=true; fi
    if grep -qE '^-?[[:space:]]*Exit code[[:space:]]*:[[:space:]]*[1-9][0-9]*' "$RESULTS_PATH"; then HAS_TRACE=true; fi
    if [[ "$HAS_TRACE" != "true" ]]; then
      echo "Stop hook: results artifact ${RESULTS_PATH} has verdict ERROR but no stack trace / non-zero exit code was found. Include the runner's error output in the artifact." >&2
      exit 2
    fi
    ;;

  EXPLORATORY-ONLY)
    if ! grep -qE '^## Exploratory Mode[[:space:]]*$' "$RESULTS_PATH"; then
      echo "Stop hook: results artifact ${RESULTS_PATH} has verdict EXPLORATORY-ONLY but is missing '## Exploratory Mode' section." >&2
      exit 2
    fi
    EXPL_BLOCK="$(get_section_block 'Exploratory Mode')"
    if ! echo "$EXPL_BLOCK" | grep -qE '^[[:space:]]*Reason[[:space:]]*:[[:space:]]*[^[:space:]]'; then
      echo "Stop hook: results artifact ${RESULTS_PATH} '## Exploratory Mode' is missing a non-empty 'Reason:' line." >&2
      exit 2
    fi
    ;;
esac

# All checks passed.
rm -f "$ACTIVE_FILE"
exit 0
