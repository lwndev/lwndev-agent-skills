#!/usr/bin/env bash
set -euo pipefail

# qa-verify-coverage.sh (FR-9) — Verify adversarial coverage of a QA plan or
# results artifact against the five required dimensions, scenario metadata, the
# empty-findings directive, and no-spec drift (plan only).
#
# Usage:
#   qa-verify-coverage.sh <artifact-path>
#
# Args:
#   <artifact-path>  Path to a QA plan (qa/test-plans/QA-plan-{ID}.md) or a
#                    QA results artifact (qa/test-results/QA-results-{ID}.md).
#
# Output (stdout):
#   JSON {
#     verdict: "COVERAGE-ADEQUATE" | "COVERAGE-GAPS",
#     perDimension: [{ dimension, status, scenarioCount }],
#     gaps: [ ... ]
#   }
#
# Exit codes:
#   0  JSON emitted (regardless of verdict)
#   2  missing/invalid args

# The five adversarial dimensions, in order.
FIVE_DIMENSIONS="Inputs|State transitions|Environment|Dependency failure|Cross-cutting"

usage() {
  echo "Usage: qa-verify-coverage.sh <artifact-path>" >&2
}

if [[ $# -ne 1 ]]; then
  echo "Error: expected 1 arg, got $#." >&2
  usage
  exit 2
fi

ARTIFACT="$1"

if [[ -z "$ARTIFACT" ]]; then
  echo "Error: artifact path must not be empty." >&2
  usage
  exit 2
fi

if [[ ! -f "$ARTIFACT" ]]; then
  echo "Error: artifact not found: $ARTIFACT" >&2
  usage
  exit 2
fi

# ---- Detect artifact type -----------------------------------------------
# Plans: QA-plan-{ID}.md         → scenarios section is "## Scenarios"
# Results: QA-results-{ID}.md    → scenarios section is "## Scenarios Run"
BASENAME="$(basename "$ARTIFACT")"
if [[ "$BASENAME" == QA-results-* ]]; then
  IS_RESULTS=1
  SCENARIOS_HEADING="## Scenarios Run"
else
  IS_RESULTS=0
  SCENARIOS_HEADING="## Scenarios"
fi

# ---- Extract a named section from the artifact --------------------------
# Prints lines between the heading and the next ## heading (exclusive).
extract_section() {
  local file="$1"
  local heading="$2"
  local in_section=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$heading" ]]; then
      in_section=1
      continue
    fi
    if [[ $in_section -eq 1 ]]; then
      if [[ "$line" =~ ^##[^#] ]]; then
        break
      fi
      printf '%s\n' "$line"
    fi
  done < "$file"
}

SCENARIOS_TEXT="$(extract_section "$ARTIFACT" "$SCENARIOS_HEADING")"

# ---- Per-dimension counts and justification flags -----------------------
# We track counts as plain variables because Bash 3.2 lacks associative arrays.
# Index mapping (0-based):
#   0 = Inputs
#   1 = State transitions
#   2 = Environment
#   3 = Dependency failure
#   4 = Cross-cutting

count_0=0; count_1=0; count_2=0; count_3=0; count_4=0
just_0=0;  just_1=0;  just_2=0;  just_3=0;  just_4=0

# Return the index for a given dimension name, or "" if not a known dimension.
dim_index() {
  case "$1" in
    "Inputs")             echo 0 ;;
    "State transitions")  echo 1 ;;
    "Environment")        echo 2 ;;
    "Dependency failure") echo 3 ;;
    "Cross-cutting")      echo 4 ;;
    *)                    echo "" ;;
  esac
}

# Get count for dimension index.
get_count() {
  case "$1" in
    0) echo "$count_0" ;;
    1) echo "$count_1" ;;
    2) echo "$count_2" ;;
    3) echo "$count_3" ;;
    4) echo "$count_4" ;;
  esac
}

# Increment count for dimension index.
inc_count() {
  case "$1" in
    0) count_0=$(( count_0 + 1 )) ;;
    1) count_1=$(( count_1 + 1 )) ;;
    2) count_2=$(( count_2 + 1 )) ;;
    3) count_3=$(( count_3 + 1 )) ;;
    4) count_4=$(( count_4 + 1 )) ;;
  esac
}

# Get justification flag for dimension index.
get_just() {
  case "$1" in
    0) echo "$just_0" ;;
    1) echo "$just_1" ;;
    2) echo "$just_2" ;;
    3) echo "$just_3" ;;
    4) echo "$just_4" ;;
  esac
}

# Set justification flag for dimension index.
set_just() {
  case "$1" in
    0) just_0=1 ;;
    1) just_1=1 ;;
    2) just_2=1 ;;
    3) just_3=1 ;;
    4) just_4=1 ;;
  esac
}

# Walk the scenarios section, tracking the current ### subsection.
CURRENT_IDX=""
while IFS= read -r line || [[ -n "$line" ]]; do
  # Detect ### <Dimension> subsection heading.
  if [[ "$line" =~ ^###[[:space:]]+(.+)$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    # Trim trailing whitespace/carriage-return.
    candidate="${candidate%"${candidate##*[![:space:]$'\r']}"}"
    CURRENT_IDX="$(dim_index "$candidate")"
    continue
  fi

  if [[ -z "$CURRENT_IDX" ]]; then
    continue
  fi

  # Scenario line: starts with optional whitespace, then "- [".
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[ ]]; then
    inc_count "$CURRENT_IDX"
    continue
  fi

  # Non-applicability justification: line mentions relevant keywords.
  lower_line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower_line" == *"not applicable"* || "$lower_line" == *"n/a"* || \
        "$lower_line" == *"no external"* || "$lower_line" == *"no scenarios"* || \
        "$lower_line" == *"does not apply"* || "$lower_line" == *"not relevant"* || \
        "$lower_line" == *"justification:"* ]]; then
    set_just "$CURRENT_IDX"
  fi
done <<< "$SCENARIOS_TEXT"

# ---- Metadata validation ------------------------------------------------
# Walk all scenario lines and check priority and execution mode.

INVALID_PRIORITY_GAPS=""
INVALID_MODE_GAPS=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[ ]]; then
    continue
  fi

  label="${line:0:100}"

  # Priority: must contain [P0], [P1], or [P2].
  if ! [[ "$line" =~ \[(P0|P1|P2)\] ]]; then
    if [[ -n "$INVALID_PRIORITY_GAPS" ]]; then
      INVALID_PRIORITY_GAPS="$INVALID_PRIORITY_GAPS
Missing or invalid priority (expected P0|P1|P2): $label"
    else
      INVALID_PRIORITY_GAPS="Missing or invalid priority (expected P0|P1|P2): $label"
    fi
  fi

  # Execution mode: must contain "mode: test-framework" or "mode: exploratory".
  if ! [[ "$line" =~ mode:[[:space:]]*(test-framework|exploratory) ]]; then
    if [[ -n "$INVALID_MODE_GAPS" ]]; then
      INVALID_MODE_GAPS="$INVALID_MODE_GAPS
Missing or invalid execution mode (expected test-framework|exploratory): $label"
    else
      INVALID_MODE_GAPS="Missing or invalid execution mode (expected test-framework|exploratory): $label"
    fi
  fi
done <<< "$SCENARIOS_TEXT"

# ---- Empty-findings directive (results artifacts only) ------------------
EMPTY_FINDINGS_GAPS=""

if [[ $IS_RESULTS -eq 1 ]]; then
  FINDINGS_TEXT="$(extract_section "$ARTIFACT" "## Findings")"
  # Strip whitespace and check if findings section is empty.
  findings_content="$(printf '%s' "$FINDINGS_TEXT" | tr -d '[:space:]')"
  if [[ -z "$findings_content" ]]; then
    # No findings at all — flag every dimension that had scenarios and no justification.
    for idx in 0 1 2 3 4; do
      cnt="$(get_count "$idx")"
      jst="$(get_just "$idx")"
      if [[ "$cnt" -gt 0 && "$jst" -eq 0 ]]; then
        case "$idx" in
          0) dim_name="Inputs" ;;
          1) dim_name="State transitions" ;;
          2) dim_name="Environment" ;;
          3) dim_name="Dependency failure" ;;
          4) dim_name="Cross-cutting" ;;
        esac
        gap_text="Dimension '$dim_name': ${cnt} scenario(s) ran, zero findings recorded, no justification"
        if [[ -n "$EMPTY_FINDINGS_GAPS" ]]; then
          EMPTY_FINDINGS_GAPS="$EMPTY_FINDINGS_GAPS
$gap_text"
        else
          EMPTY_FINDINGS_GAPS="$gap_text"
        fi
      fi
    done
  fi
fi

# ---- No-spec drift (plan only) ------------------------------------------
SPEC_DRIFT_GAPS=""

if [[ $IS_RESULTS -eq 0 ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Match FR-\d+, AC-\d+, or NFR-\d+ tokens.
    if [[ "$line" =~ (FR-[0-9]+|AC-[0-9]+|NFR-[0-9]+) ]]; then
      token="${BASH_REMATCH[1]}"
      label="${line:0:120}"
      gap_text="Spec token '$token' found in plan ## Scenarios: $label"
      if [[ -n "$SPEC_DRIFT_GAPS" ]]; then
        SPEC_DRIFT_GAPS="$SPEC_DRIFT_GAPS
$gap_text"
      else
        SPEC_DRIFT_GAPS="$gap_text"
      fi
    fi
  done <<< "$SCENARIOS_TEXT"
fi

# ---- Build gaps list as a JSON array ------------------------------------
GAPS_JSON="["
first_gap=1

# Dimension-coverage gaps.
for idx in 0 1 2 3 4; do
  cnt="$(get_count "$idx")"
  jst="$(get_just "$idx")"
  if [[ "$cnt" -eq 0 && "$jst" -eq 0 ]]; then
    case "$idx" in
      0) dim_name="Inputs" ;;
      1) dim_name="State transitions" ;;
      2) dim_name="Environment" ;;
      3) dim_name="Dependency failure" ;;
      4) dim_name="Cross-cutting" ;;
    esac
    gap_text="Dimension '$dim_name' has no scenarios and no non-applicability justification"
    entry="$(jq -n --arg g "$gap_text" '$g')"
    if [[ $first_gap -eq 1 ]]; then GAPS_JSON+="$entry"; first_gap=0; else GAPS_JSON+=",$entry"; fi
  fi
done

# Priority gaps.
if [[ -n "$INVALID_PRIORITY_GAPS" ]]; then
  while IFS= read -r g || [[ -n "$g" ]]; do
    [[ -z "$g" ]] && continue
    entry="$(jq -n --arg g "$g" '$g')"
    if [[ $first_gap -eq 1 ]]; then GAPS_JSON+="$entry"; first_gap=0; else GAPS_JSON+=",$entry"; fi
  done <<< "$INVALID_PRIORITY_GAPS"
fi

# Mode gaps.
if [[ -n "$INVALID_MODE_GAPS" ]]; then
  while IFS= read -r g || [[ -n "$g" ]]; do
    [[ -z "$g" ]] && continue
    entry="$(jq -n --arg g "$g" '$g')"
    if [[ $first_gap -eq 1 ]]; then GAPS_JSON+="$entry"; first_gap=0; else GAPS_JSON+=",$entry"; fi
  done <<< "$INVALID_MODE_GAPS"
fi

# Empty-findings gaps.
if [[ -n "$EMPTY_FINDINGS_GAPS" ]]; then
  while IFS= read -r g || [[ -n "$g" ]]; do
    [[ -z "$g" ]] && continue
    entry="$(jq -n --arg g "$g" '$g')"
    if [[ $first_gap -eq 1 ]]; then GAPS_JSON+="$entry"; first_gap=0; else GAPS_JSON+=",$entry"; fi
  done <<< "$EMPTY_FINDINGS_GAPS"
fi

# Spec-drift gaps.
if [[ -n "$SPEC_DRIFT_GAPS" ]]; then
  while IFS= read -r g || [[ -n "$g" ]]; do
    [[ -z "$g" ]] && continue
    entry="$(jq -n --arg g "$g" '$g')"
    if [[ $first_gap -eq 1 ]]; then GAPS_JSON+="$entry"; first_gap=0; else GAPS_JSON+=",$entry"; fi
  done <<< "$SPEC_DRIFT_GAPS"
fi

GAPS_JSON+="]"

# ---- Derive verdict -----------------------------------------------------
if [[ "$GAPS_JSON" == "[]" ]]; then
  VERDICT="COVERAGE-ADEQUATE"
else
  VERDICT="COVERAGE-GAPS"
fi

# ---- Build perDimension array -------------------------------------------
PER_DIM_JSON="["
dim_names=("Inputs" "State transitions" "Environment" "Dependency failure" "Cross-cutting")
first_dim=1
for idx in 0 1 2 3 4; do
  cnt="$(get_count "$idx")"
  jst="$(get_just "$idx")"
  dim_name="${dim_names[$idx]}"
  if [[ "$cnt" -gt 0 ]]; then
    dim_status="covered"
  elif [[ "$jst" -eq 1 ]]; then
    dim_status="justified"
  else
    dim_status="missing"
  fi
  entry="$(jq -n \
    --arg dimension "$dim_name" \
    --arg status "$dim_status" \
    --argjson scenarioCount "$cnt" \
    '{dimension: $dimension, status: $status, scenarioCount: $scenarioCount}')"
  if [[ $first_dim -eq 1 ]]; then PER_DIM_JSON+="$entry"; first_dim=0; else PER_DIM_JSON+=",$entry"; fi
done
PER_DIM_JSON+="]"

# ---- Emit final JSON output ---------------------------------------------
jq -n \
  --arg verdict "$VERDICT" \
  --argjson perDimension "$PER_DIM_JSON" \
  --argjson gaps "$GAPS_JSON" \
  '{verdict: $verdict, perDimension: $perDimension, gaps: $gaps}'

exit 0
