#!/usr/bin/env bash
# phase-complexity-budget.sh — Score each phase block in an implementation
# plan against the per-phase complexity budget table (FEAT-029 / FR-3).
#
# Usage: phase-complexity-budget.sh <plan-file> [--phase N]
#
# Per-phase budget table (verbatim from FR-3):
#
#   Signal               haiku            sonnet              opus
#   ---------------------------------------------------------------
#   Implementation steps ≤3               4-7                 ≥8
#   Deliverables         ≤4               5-9                 ≥10
#   Distinct file paths  ≤3               4-8                 ≥9
#   Low-tier flag        bumps tier +1 (capped at opus); flags = schema, migration, test infra
#   High-tier flag       bumps tier +1 (capped at opus); flags = public api, security, multi-skill refactor
#
# Final tier = max(steps_tier, deliverables_tier, files_tier) + heuristic
# bumps, capped at opus. `**ComplexityOverride:** <tier>` in the phase block
# (fence-aware) replaces the computed tier outright. `overBudget` is true
# when any single signal independently scored opus AND no override clamped
# the result down.
#
# Output:
#   --phase N: single JSON object
#   no --phase: JSON array of objects in document order
#
#   Object shape:
#     {
#       "phase": <N>,
#       "tier": "haiku|sonnet|opus",
#       "signals": {
#         "steps": <count>,
#         "deliverables": <count>,
#         "files": <count>,
#         "flagsLow": [...],
#         "flagsHigh": [...]
#       },
#       "overBudget": true|false,
#       "override": "haiku|sonnet|opus" | null
#     }
#
# Exit codes:
#   0  success.
#   1  plan I/O error or no `### Phase` blocks in plan.
#   2  missing arg or malformed --phase value.
#
# Bash 3.2-compatible.

set -euo pipefail

# ---------------------------------------------------------------------------
# Budget thresholds — tune in one place.
# ---------------------------------------------------------------------------
STEPS_LOW_MAX=3
STEPS_MED_MAX=7
DELIVERABLES_LOW_MAX=4
DELIVERABLES_MED_MAX=9
FILES_LOW_MAX=3
FILES_MED_MAX=8

# Heuristic flag substrings (case-insensitive matching at lookup time).
LOW_FLAGS=("schema" "migration" "test infra")
HIGH_FLAGS=("public api" "security" "multi-skill refactor")

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
if [ "$#" -lt 1 ]; then
  echo "error: usage: phase-complexity-budget.sh <plan-file> [--phase N]" >&2
  exit 2
fi

plan=""
filter_phase=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase)
      shift
      if [ "$#" -lt 1 ]; then
        echo "error: --phase requires a value" >&2
        exit 2
      fi
      filter_phase="$1"
      if ! printf '%s' "$filter_phase" | grep -Eq '^[1-9][0-9]*$'; then
        echo "error: --phase must be a positive integer, got: ${filter_phase}" >&2
        exit 2
      fi
      shift
      ;;
    --phase=*)
      filter_phase="${1#--phase=}"
      if ! printf '%s' "$filter_phase" | grep -Eq '^[1-9][0-9]*$'; then
        echo "error: --phase must be a positive integer, got: ${filter_phase}" >&2
        exit 2
      fi
      shift
      ;;
    --)
      shift
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$plan" ]; then
        plan="$1"
      else
        echo "error: unexpected positional argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$plan" ]; then
  echo "error: usage: phase-complexity-budget.sh <plan-file> [--phase N]" >&2
  exit 2
fi

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Block-aware extraction. awk emits one record per phase, fields separated
# by ASCII US (\x1f), with sub-records inside fields separated by RS placeholders.
# To keep parsing simple in bash, we emit:
#
#   <num>\x1f<steps>\x1f<deliverables>\x1f<files-joined-by-\x1e>\x1f<body-joined-by-newline-encoded-as-\x1d>\x1f<override-or-empty>
#
# - steps:        count of `^[0-9]+\.` lines in `#### Implementation Steps` (until next `####` or `### Phase`).
# - deliverables: count of `- \[[ x]\]` lines in `#### Deliverables` (until next `####` or `### Phase`).
# - files:        unique backticked tokens extracted from each `- \[[ x]\]` line in deliverables.
# - body:         entire phase block body (lines outside fences) for substring flag scanning.
# - override:     value of `**ComplexityOverride:**` line found OUTSIDE fences inside the block, or empty.
#
# All fence-aware: lines inside ``` / ~~~ are excluded from counting and
# from the override scan. Body field is also fence-stripped — flag scanning
# never inspects fenced documentation.
# ---------------------------------------------------------------------------

US=$'\x1f'   # field separator
RSREC=$'\x1e' # record separator inside `files`
LF=$'\x1d'    # line separator inside body

parsed=$(
  tr -d '\r' < "$plan" \
    | awk -v US="$US" -v RSREC="$RSREC" -v LF="$LF" '
        BEGIN {
          in_fence = 0
          in_phase = 0
          in_steps = 0
          in_deliv = 0
          steps = 0
          deliv = 0
          files_str = ""
          body_str = ""
          override = ""
          cur_num = ""
        }
        function emit() {
          if (in_phase) {
            printf "%s%s%d%s%d%s%s%s%s%s%s\n", \
              cur_num, US, steps, US, deliv, US, files_str, US, body_str, US, override
          }
        }
        function reset_phase() {
          in_steps = 0
          in_deliv = 0
          steps = 0
          deliv = 0
          files_str = ""
          body_str = ""
          override = ""
        }
        function add_files_from_line(line,    rest, tok) {
          rest = line
          while (match(rest, /`[^`]+`/)) {
            tok = substr(rest, RSTART + 1, RLENGTH - 2)
            # Dedupe: only add if not already in files_str (delimited).
            if (index(RSREC files_str RSREC, RSREC tok RSREC) == 0) {
              if (files_str == "") files_str = tok
              else files_str = files_str RSREC tok
            }
            rest = substr(rest, RSTART + RLENGTH)
          }
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)

          # Fence toggles.
          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            # Append to body verbatim so structure is preserved if needed,
            # but mark as fenced so substring scanner ignores it. Easier:
            # simply skip fenced lines entirely from body, since flag
            # scanning is the only consumer.
            next
          }
          if (in_fence) next

          # Phase heading.
          if (match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            emit()
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            cur_num = num
            in_phase = 1
            reset_phase()
            next
          }

          if (!in_phase) next

          # Subsection boundaries.
          if (match(line, /^####[ ]+Implementation Steps[ \t]*$/)) {
            in_steps = 1
            in_deliv = 0
            # Body capture continues.
            body_str = (body_str == "" ? line : body_str LF line)
            next
          }
          if (match(line, /^####[ ]+Deliverables[ \t]*$/)) {
            in_steps = 0
            in_deliv = 1
            body_str = (body_str == "" ? line : body_str LF line)
            next
          }
          # Any other #### closes prior subsections.
          if (match(line, /^####[ ]+/)) {
            in_steps = 0
            in_deliv = 0
            body_str = (body_str == "" ? line : body_str LF line)
            next
          }

          # Override line — first occurrence wins.
          if (override == "" && match(line, /^\*\*ComplexityOverride:\*\*[ ]+/)) {
            val = line
            sub(/^\*\*ComplexityOverride:\*\*[ ]+/, "", val)
            sub(/[ \t]+$/, "", val)
            override = val
          }

          # Step count: numbered list lines inside Implementation Steps.
          if (in_steps && match(line, /^[0-9]+\./)) {
            steps += 1
          }

          # Deliverable count + file extraction inside Deliverables.
          if (in_deliv && match(line, /^-[ ]+\[[ xX]\]/)) {
            deliv += 1
            add_files_from_line(line)
          }

          body_str = (body_str == "" ? line : body_str LF line)
        }
        END { emit() }
      '
)

if [ -z "$parsed" ]; then
  echo "error: no \`### Phase\` blocks found in ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read parsed records into arrays.
# ---------------------------------------------------------------------------
phase_nums=()
phase_steps=()
phase_deliv=()
phase_files=()  # files joined by RSREC
phase_bodies=() # bodies joined by LF
phase_overrides=()

while IFS="$US" read -r p_num p_steps p_deliv p_files p_body p_override; do
  [ -z "$p_num" ] && continue
  phase_nums+=("$p_num")
  phase_steps+=("$p_steps")
  phase_deliv+=("$p_deliv")
  phase_files+=("$p_files")
  phase_bodies+=("$p_body")
  phase_overrides+=("$p_override")
done <<< "$parsed"

# ---------------------------------------------------------------------------
# Scoring helpers.
# ---------------------------------------------------------------------------
# Map a count to a tier ordinal: 0=haiku, 1=sonnet, 2=opus.
score_count() {
  local count="$1"
  local low_max="$2"
  local med_max="$3"
  if [ "$count" -le "$low_max" ]; then
    echo 0
  elif [ "$count" -le "$med_max" ]; then
    echo 1
  else
    echo 2
  fi
}

ord_to_tier() {
  case "$1" in
    0) echo "haiku" ;;
    1) echo "sonnet" ;;
    2) echo "opus" ;;
  esac
}

tier_to_ord() {
  case "$1" in
    haiku) echo 0 ;;
    sonnet) echo 1 ;;
    opus) echo 2 ;;
    *) echo -1 ;;
  esac
}

# Bash 3.2-safe lowercasing via tr.
tolower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Count distinct files in a RSREC-joined string.
count_files() {
  local s="$1"
  if [ -z "$s" ]; then
    echo 0
    return
  fi
  printf '%s' "$s" | awk -v RSREC="$RSREC" '
    {
      n = split($0, a, RSREC)
      print n
    }
  '
}

# Find substring matches (case-insensitive) of each flag in body text.
# Emit matching flags joined by US.
find_flags() {
  local body="$1"
  shift
  local body_lc
  body_lc="$(tolower "$body")"
  local out=""
  local flag flag_lc
  for flag in "$@"; do
    flag_lc="$(tolower "$flag")"
    case "$body_lc" in
      *"$flag_lc"*)
        if [ -z "$out" ]; then out="$flag"
        else out="${out}${US}${flag}"
        fi
        ;;
    esac
  done
  printf '%s' "$out"
}

# JSON helpers (jq when available, printf fallback).
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

json_array_of_strings() {
  # arg1: US-joined list (may be empty)
  local list="$1"
  if [ -z "$list" ]; then
    printf '[]'
    return
  fi
  local out="["
  local first=1
  local IFS_save="$IFS"
  IFS="$US"
  set -- $list
  IFS="$IFS_save"
  local item esc
  for item in "$@"; do
    esc="$(json_escape "$item")"
    if [ "$first" -eq 1 ]; then
      out="${out}\"${esc}\""
      first=0
    else
      out="${out},\"${esc}\""
    fi
  done
  out="${out}]"
  printf '%s' "$out"
}

# Build one JSON object for a phase.
build_phase_object() {
  local num="$1"
  local tier="$2"
  local steps="$3"
  local deliv="$4"
  local files_count="$5"
  local flags_low="$6"   # US-joined
  local flags_high="$7"  # US-joined
  local over_budget="$8" # true|false
  local override="$9"    # haiku|sonnet|opus or empty

  if command -v jq >/dev/null 2>&1; then
    # Build the flag arrays as proper JSON via jq's --arg + split.
    local low_json high_json
    low_json="$(printf '%s' "$flags_low" | awk -v US="$US" 'BEGIN{first=1; printf "["} {n=split($0,a,US); for(i=1;i<=n;i++){ if(a[i]==""){continue} if(!first){printf ","} else first=0; gsub(/\\/, "\\\\", a[i]); gsub(/"/, "\\\"", a[i]); printf "\"%s\"", a[i] } } END{printf "]"}')"
    high_json="$(printf '%s' "$flags_high" | awk -v US="$US" 'BEGIN{first=1; printf "["} {n=split($0,a,US); for(i=1;i<=n;i++){ if(a[i]==""){continue} if(!first){printf ","} else first=0; gsub(/\\/, "\\\\", a[i]); gsub(/"/, "\\\"", a[i]); printf "\"%s\"", a[i] } } END{printf "]"}')"
    local override_arg='null'
    if [ -n "$override" ]; then
      override_arg="$(jq -cn --arg v "$override" '$v')"
    fi
    jq -cn \
      --argjson phase "$num" \
      --arg tier "$tier" \
      --argjson steps "$steps" \
      --argjson deliverables "$deliv" \
      --argjson files "$files_count" \
      --argjson flagsLow "$low_json" \
      --argjson flagsHigh "$high_json" \
      --argjson overBudget "$over_budget" \
      --argjson override "$override_arg" \
      '{phase:$phase,tier:$tier,signals:{steps:$steps,deliverables:$deliverables,files:$files,flagsLow:$flagsLow,flagsHigh:$flagsHigh},overBudget:$overBudget,override:$override}'
  else
    # Pure-bash printf fallback.
    local low_arr high_arr
    low_arr="$(json_array_of_strings "$flags_low")"
    high_arr="$(json_array_of_strings "$flags_high")"
    local over_lit="$over_budget"
    local override_lit
    if [ -z "$override" ]; then
      override_lit="null"
    else
      override_lit="\"$(json_escape "$override")\""
    fi
    printf '{"phase":%s,"tier":"%s","signals":{"steps":%s,"deliverables":%s,"files":%s,"flagsLow":%s,"flagsHigh":%s},"overBudget":%s,"override":%s}' \
      "$num" "$tier" "$steps" "$deliv" "$files_count" "$low_arr" "$high_arr" "$over_lit" "$override_lit"
  fi
}

# ---------------------------------------------------------------------------
# Score every phase, optionally filtering to --phase N.
# ---------------------------------------------------------------------------
results=()  # JSON object strings

for i in "${!phase_nums[@]}"; do
  num="${phase_nums[$i]}"
  if [ -n "$filter_phase" ] && [ "$num" != "$filter_phase" ]; then
    continue
  fi

  steps="${phase_steps[$i]}"
  deliv="${phase_deliv[$i]}"
  files_str="${phase_files[$i]}"
  body="${phase_bodies[$i]}"
  override="${phase_overrides[$i]}"

  # body uses LF placeholder; substitute back to real newlines for substring
  # matching (case-insensitive).
  body_real="${body//$LF/$'\n'}"

  files_count="$(count_files "$files_str")"

  steps_ord="$(score_count "$steps" "$STEPS_LOW_MAX" "$STEPS_MED_MAX")"
  deliv_ord="$(score_count "$deliv" "$DELIVERABLES_LOW_MAX" "$DELIVERABLES_MED_MAX")"
  files_ord="$(score_count "$files_count" "$FILES_LOW_MAX" "$FILES_MED_MAX")"

  base_ord=$steps_ord
  [ $deliv_ord -gt $base_ord ] && base_ord=$deliv_ord
  [ $files_ord -gt $base_ord ] && base_ord=$files_ord

  # Heuristic flag matches (case-insensitive substring scan over body).
  flags_low="$(find_flags "$body_real" "${LOW_FLAGS[@]}")"
  flags_high="$(find_flags "$body_real" "${HIGH_FLAGS[@]}")"

  # Count matches (US-separated tokens).
  count_tokens() {
    local s="$1"
    if [ -z "$s" ]; then echo 0; return; fi
    local IFS_save="$IFS"
    IFS="$US"
    # shellcheck disable=SC2086
    set -- $s
    IFS="$IFS_save"
    echo "$#"
  }
  low_count="$(count_tokens "$flags_low")"
  high_count="$(count_tokens "$flags_high")"

  bumped_ord=$((base_ord + low_count + high_count))
  [ $bumped_ord -gt 2 ] && bumped_ord=2

  computed_tier="$(ord_to_tier "$bumped_ord")"

  # overBudget: any single signal independently scored opus AND no override.
  any_opus=0
  if [ $steps_ord -eq 2 ] || [ $deliv_ord -eq 2 ] || [ $files_ord -eq 2 ]; then
    any_opus=1
  fi
  over_budget="false"
  if [ "$any_opus" -eq 1 ] && [ -z "$override" ]; then
    over_budget="true"
  fi

  # Override clamps the final tier outright (validate value).
  final_tier="$computed_tier"
  override_value=""
  if [ -n "$override" ]; then
    case "$override" in
      haiku|sonnet|opus)
        final_tier="$override"
        override_value="$override"
        ;;
      *)
        echo "error: phase ${num} has invalid **ComplexityOverride:** value: ${override} (allowed: haiku, sonnet, opus)" >&2
        exit 1
        ;;
    esac
  fi

  obj="$(build_phase_object "$num" "$final_tier" "$steps" "$deliv" "$files_count" "$flags_low" "$flags_high" "$over_budget" "$override_value")"
  results+=("$obj")
done

# ---------------------------------------------------------------------------
# Emit output.
# ---------------------------------------------------------------------------
if [ -n "$filter_phase" ]; then
  if [ "${#results[@]}" -eq 0 ]; then
    echo "error: phase ${filter_phase} not found in plan" >&2
    exit 1
  fi
  printf '%s\n' "${results[0]}"
  exit 0
fi

# Array of objects in document order.
if [ "${#results[@]}" -eq 0 ]; then
  printf '[]\n'
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  printf '%s\n' "${results[@]}" | jq -cs '.'
else
  out="["
  first=1
  for obj in "${results[@]}"; do
    if [ "$first" -eq 1 ]; then
      out="${out}${obj}"
      first=0
    else
      out="${out},${obj}"
    fi
  done
  out="${out}]"
  printf '%s\n' "$out"
fi
exit 0
