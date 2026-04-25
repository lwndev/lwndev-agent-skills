#!/usr/bin/env bash
set -euo pipefail

# capability-report-diff.sh (FR-3) — Compare a plan-embedded capability report
# against a fresh capability JSON, emit a drift report.
#
# Usage:
#   capability-report-diff.sh <plan-file> <fresh-json>
#
# Args:
#   <plan-file>  Path to the QA plan or implementation plan that embeds a
#                capability report. The capability JSON is recovered from a
#                fenced ```json block under a `## Capability Report` heading,
#                or from frontmatter `capability:` block, or from any fenced
#                ```json block whose decoded object has a `framework` key.
#   <fresh-json> Path to a freshly generated capability JSON (the output of
#                capability-discovery.sh).
#
# Output:
#   stdout JSON {drift: bool, fields: [{field, planValue, freshValue}]}.
#   Comparable fields: framework, language, packageManager, testCommand, mode.
#   `notes` and `timestamp` are intentionally ignored.
#
# Exit codes:
#   0  success (drift report emitted)
#   2  missing/invalid args (file does not exist, unparseable JSON, etc.)

usage() {
  echo "Usage: capability-report-diff.sh <plan-file> <fresh-json>" >&2
}

if [[ $# -ne 2 ]]; then
  echo "Error: expected 2 args, got $#." >&2
  usage
  exit 2
fi

PLAN_FILE="$1"
FRESH_JSON="$2"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "Error: plan file not found: $PLAN_FILE" >&2
  exit 2
fi
if [[ ! -f "$FRESH_JSON" ]]; then
  echo "Error: fresh capability JSON not found: $FRESH_JSON" >&2
  exit 2
fi

# Validate fresh JSON parseability.
if ! jq -e . "$FRESH_JSON" >/dev/null 2>&1; then
  echo "Error: fresh capability JSON is not valid JSON: $FRESH_JSON" >&2
  exit 2
fi

# Extract candidate capability JSON blocks from the plan file.
# Strategy: walk the file, accumulate fenced ```json blocks, pick the first
# whose decoded object has a `framework` key. Fall back to scanning all
# fenced blocks if no framework key found.
extract_plan_capability() {
  local file="$1"
  local in_fence=0
  local fence_lang=""
  local buffer=""
  local found_capability=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ $in_fence -eq 0 ]]; then
      if [[ "$line" =~ ^\`\`\`(.*)$ ]]; then
        fence_lang="${BASH_REMATCH[1]}"
        if [[ "$fence_lang" == "json" || "$fence_lang" == "" ]]; then
          in_fence=1
          buffer=""
        fi
      fi
    else
      if [[ "$line" =~ ^\`\`\` ]]; then
        # End of fence — try to parse the buffer.
        if [[ -n "$buffer" ]]; then
          if printf '%s' "$buffer" | jq -e 'type == "object" and has("framework")' >/dev/null 2>&1; then
            found_capability="$buffer"
            echo "$found_capability"
            return 0
          fi
        fi
        in_fence=0
        buffer=""
      else
        buffer+="$line"$'\n'
      fi
    fi
  done < "$file"
  return 1
}

PLAN_CAPABILITY="$(extract_plan_capability "$PLAN_FILE" || true)"
if [[ -z "$PLAN_CAPABILITY" ]]; then
  echo "Error: no capability report (json block with 'framework' key) found in plan: $PLAN_FILE" >&2
  exit 2
fi

# Validate the recovered capability JSON parseability.
if ! printf '%s' "$PLAN_CAPABILITY" | jq -e . >/dev/null 2>&1; then
  echo "Error: recovered plan capability JSON is not valid JSON" >&2
  exit 2
fi

# Compare comparable fields.
COMPARABLE_FIELDS=(framework language packageManager testCommand mode)

# Build a JSON object reading both files.
DIFF_JSON="$(
  jq -nrc \
    --argjson plan "$PLAN_CAPABILITY" \
    --slurpfile fresh "$FRESH_JSON" \
    --argjson fields "$(printf '%s\n' "${COMPARABLE_FIELDS[@]}" | jq -R . | jq -s .)" \
    '
    ($fresh[0]) as $f |
    {
      fields: ($fields | map(. as $k | {
        field: $k,
        planValue: ($plan[$k] // null),
        freshValue: ($f[$k] // null)
      }) | map(select(.planValue != .freshValue)))
    }
    | .drift = ((.fields | length) > 0)
    | {drift: .drift, fields: .fields}
    '
)"

echo "$DIFF_JSON"
exit 0
