#!/usr/bin/env bash
set -euo pipefail

# render-qa-results.sh (FR-7) — Write the QA results artifact at
# qa/test-results/QA-results-{ID}.md per the Phase-1 contract.
#
# Usage:
#   render-qa-results.sh <ID> <verdict> <capability-json> <execution-json>
#
# Args:
#   <ID>              Requirement ID (e.g., FEAT-030).
#   <verdict>         One of PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY.
#   <capability-json> Path to the capability JSON (output of capability-discovery.sh).
#   <execution-json>  Path to the execution JSON (output of run-framework.sh).
#                     For EXPLORATORY-ONLY, pass /dev/null or an empty-object
#                     JSON file ({}).
#
# Optional environment overrides for the Findings / Reconciliation Delta /
# Exploratory sections (the caller wires these from the surrounding scripts):
#   QA_FINDINGS_BODY      Markdown body for `## Findings` (default: per-verdict).
#   QA_RECONCILIATION     Markdown body for `## Reconciliation Delta`
#                         (default: empty-alignment template).
#   QA_EXPLORATORY_REASON One-line reason for EXPLORATORY-ONLY verdict.
#   QA_SCENARIOS_BODY     Markdown body for `## Scenarios Run`
#                         (default: derived from execution JSON).
#   QA_SUMMARY_BODY       Markdown body for `## Summary`
#                         (default: one-line verdict summary).
#   QA_OUTPUT_DIR         Output dir (default: qa/test-results under PWD).
#
# Exit codes:
#   0  artifact written
#   1  invalid verdict / missing required field
#   2  missing/invalid args

usage() {
  echo "Usage: render-qa-results.sh <ID> <verdict> <capability-json> <execution-json>" >&2
}

if [[ $# -ne 4 ]]; then
  echo "Error: expected 4 args, got $#." >&2
  usage
  exit 2
fi

ID="$1"
VERDICT="$2"
CAPABILITY_JSON_PATH="$3"
EXECUTION_JSON_PATH="$4"

if [[ -z "$ID" ]]; then
  echo "Error: ID is required." >&2
  exit 2
fi

case "$VERDICT" in
  PASS|ISSUES-FOUND|ERROR|EXPLORATORY-ONLY) ;;
  *)
    echo "Error: invalid verdict '$VERDICT' (allowed: PASS | ISSUES-FOUND | ERROR | EXPLORATORY-ONLY)" >&2
    exit 1
    ;;
esac

if [[ ! -f "$CAPABILITY_JSON_PATH" ]]; then
  echo "Error: capability JSON not found: $CAPABILITY_JSON_PATH" >&2
  exit 2
fi
if ! jq -e . "$CAPABILITY_JSON_PATH" >/dev/null 2>&1; then
  echo "Error: capability JSON is not valid JSON: $CAPABILITY_JSON_PATH" >&2
  exit 2
fi

# EXPLORATORY-ONLY tolerates a missing/empty execution JSON.
EXECUTION_JSON='{}'
if [[ "$EXECUTION_JSON_PATH" != "/dev/null" ]]; then
  if [[ ! -f "$EXECUTION_JSON_PATH" ]]; then
    if [[ "$VERDICT" != "EXPLORATORY-ONLY" ]]; then
      echo "Error: execution JSON not found: $EXECUTION_JSON_PATH" >&2
      exit 2
    fi
  else
    if ! jq -e . "$EXECUTION_JSON_PATH" >/dev/null 2>&1; then
      echo "Error: execution JSON is not valid JSON: $EXECUTION_JSON_PATH" >&2
      exit 2
    fi
    EXECUTION_JSON="$(cat "$EXECUTION_JSON_PATH")"
  fi
fi

CAPABILITY_JSON="$(cat "$CAPABILITY_JSON_PATH")"

# Verdict-specific required-field validation.
PASSED=$(printf '%s' "$EXECUTION_JSON" | jq -r '.passed // 0')
FAILED=$(printf '%s' "$EXECUTION_JSON" | jq -r '.failed // 0')
ERRORED=$(printf '%s' "$EXECUTION_JSON" | jq -r '.errored // 0')
FAILING_NAMES_JSON=$(printf '%s' "$EXECUTION_JSON" | jq -c '.failingNames // []')
TRUNCATED=$(printf '%s' "$EXECUTION_JSON" | jq -r '.truncatedOutput // ""')

case "$VERDICT" in
  PASS)
    if [[ "$FAILED" -ne 0 ]]; then
      echo "Error: PASS verdict requires Failed: 0; got Failed=$FAILED." >&2
      exit 1
    fi
    ;;
  ISSUES-FOUND)
    if [[ "$(printf '%s' "$FAILING_NAMES_JSON" | jq 'length')" -eq 0 ]]; then
      echo "Error: ISSUES-FOUND verdict requires at least one failingNames entry." >&2
      exit 1
    fi
    ;;
  ERROR)
    # No structural assertion at this layer; the rendered Findings section
    # passes the truncatedOutput stack trace through. Validate execution JSON
    # at least carries an exitCode field.
    if [[ "$(printf '%s' "$EXECUTION_JSON" | jq 'has("exitCode")')" != "true" ]]; then
      echo "Error: ERROR verdict requires execution JSON with 'exitCode' field." >&2
      exit 1
    fi
    ;;
  EXPLORATORY-ONLY)
    if [[ -z "${QA_EXPLORATORY_REASON:-}" ]]; then
      echo "Error: EXPLORATORY-ONLY verdict requires QA_EXPLORATORY_REASON env var." >&2
      exit 1
    fi
    PASSED=0
    FAILED=0
    ERRORED=0
    ;;
esac

# Defaults for optional sections.
SUMMARY_BODY="${QA_SUMMARY_BODY:-Verdict ${VERDICT}: passed=${PASSED}, failed=${FAILED}, errored=${ERRORED}.}"

# Default scenarios body — single bullet per failing name + a roll-up bullet.
if [[ -n "${QA_SCENARIOS_BODY:-}" ]]; then
  SCENARIOS_BODY="$QA_SCENARIOS_BODY"
else
  SCENARIOS_BODY="- Ran ${PASSED} passing tests, ${FAILED} failing tests, ${ERRORED} errored tests."
fi

# Default findings body, per verdict.
if [[ -n "${QA_FINDINGS_BODY:-}" ]]; then
  FINDINGS_BODY="$QA_FINDINGS_BODY"
else
  case "$VERDICT" in
    PASS)
      FINDINGS_BODY=""
      ;;
    ISSUES-FOUND)
      # One bullet per failing test name.
      FINDINGS_BODY="$(printf '%s' "$FAILING_NAMES_JSON" | jq -r '.[] | "- " + .')"
      ;;
    ERROR)
      # Pass through the truncated output verbatim inside a fenced block.
      FINDINGS_BODY=$'```\n'"$TRUNCATED"$'\n```'
      ;;
    EXPLORATORY-ONLY)
      FINDINGS_BODY=""
      ;;
  esac
fi

# Default reconciliation body.
RECONCILIATION_BODY="${QA_RECONCILIATION:-### Coverage beyond requirements

### Coverage gaps

### Summary
- coverage-surplus: 0
- coverage-gap: 0}"

OUTPUT_DIR="${QA_OUTPUT_DIR:-qa/test-results}"
OUT_PATH="${OUTPUT_DIR}/QA-results-${ID}.md"

mkdir -p "$OUTPUT_DIR"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build the artifact.
{
  echo "---"
  echo "id: ${ID}"
  echo "version: 2"
  echo "timestamp: ${TIMESTAMP}"
  echo "verdict: ${VERDICT}"
  echo "persona: qa"
  echo "---"
  echo ""
  echo "## Summary"
  echo ""
  echo "$SUMMARY_BODY"
  echo ""
  echo "## Capability Report"
  echo ""
  echo '```json'
  printf '%s\n' "$CAPABILITY_JSON" | jq .
  echo '```'
  echo ""
  if [[ "$VERDICT" != "EXPLORATORY-ONLY" ]]; then
    echo "## Execution Results"
    echo ""
    echo "Passed: ${PASSED}"
    echo "Failed: ${FAILED}"
    echo "Errored: ${ERRORED}"
    if [[ "$VERDICT" == "ERROR" ]]; then
      echo ""
      echo '```'
      printf '%s\n' "$TRUNCATED"
      echo '```'
    fi
    echo ""
  fi
  echo "## Scenarios Run"
  echo ""
  echo "$SCENARIOS_BODY"
  echo ""
  echo "## Findings"
  echo ""
  if [[ -n "$FINDINGS_BODY" ]]; then
    echo "$FINDINGS_BODY"
    echo ""
  fi
  echo "## Reconciliation Delta"
  echo ""
  echo "$RECONCILIATION_BODY"
  echo ""
  if [[ "$VERDICT" == "EXPLORATORY-ONLY" ]]; then
    echo "## Exploratory Mode"
    echo ""
    echo "Reason: ${QA_EXPLORATORY_REASON}"
    echo ""
  fi
} > "$OUT_PATH"

echo "$OUT_PATH"
exit 0
