#!/usr/bin/env bash
# parse-model-flags.sh — Partition the orchestrator's argv into model-selection
# flags (FEAT-014 FR-8) and the single positional workflow token.
#
# Usage: parse-model-flags.sh "$@"
#
# Recognised flags (all use the two-token `--flag value` shape unless noted; `=` form rejected):
#   --model <tier>          hard blanket override; <tier> in {haiku,sonnet,opus}
#   --complexity <tier>     soft blanket override; <tier> in
#                           {haiku,sonnet,opus,low,medium,high} with low→haiku,
#                           medium→sonnet, high→opus normalisation
#   --model-for <step>:<tier>   hard per-step override; repeatable, later
#                               entries overwrite earlier ones for the same step
#   --approve-advance       FEAT-032 FR-8 boolean. Resume past `qa-loop-exhausted`
#                           by advancing past the QA loop without resetting the
#                           counter. Single token, no value.
#   --qa-loop-cap <N>       FEAT-032 FR-8 positive integer. Resume by raising
#                           the QA fix-attempt cap to <N> and resetting the
#                           counter to 0. Mutually exclusive with --approve-advance.
#
# Emits one JSON object on stdout with all six fields always present:
#   {"cliModel":"<tier>|null",
#    "cliComplexity":"<tier>|null",
#    "cliModelFor":{"<step>":"<tier>"}|null,
#    "approveAdvance":true|false,
#    "qaLoopCap":<int>|null,
#    "positional":"<token-or-empty-string>"}
#
# Uses jq for JSON assembly when available; pure-bash printf fallback otherwise.
#
# Exit codes:
#   0 success (including empty argv)
#   2 unknown flag, malformed tier, missing flag argument, equals-sign form,
#     or more than one surviving positional token

set -euo pipefail

# --- tier validation / normalisation ----------------------------------------

# Validate that a string is a bare tier (haiku/sonnet/opus) and echo it on
# stdout. Returns 1 on rejection.
_is_bare_tier() {
  case "$1" in
    haiku|sonnet|opus) return 0 ;;
    *) return 1 ;;
  esac
}

# Normalise a --complexity tier argument. Accepts haiku/sonnet/opus or the
# low/medium/high labels (mapped to haiku/sonnet/opus). Echoes the bare tier
# on stdout; returns 1 on rejection.
_normalise_complexity_tier() {
  case "$1" in
    haiku|sonnet|opus) printf '%s' "$1" ;;
    low)    printf 'haiku' ;;
    medium) printf 'sonnet' ;;
    high)   printf 'opus' ;;
    *) return 1 ;;
  esac
}

# --- argv partition ----------------------------------------------------------

cli_model=""
cli_complexity=""

# Parallel arrays for the cliModelFor map (bash 3.2 compatible, no assoc arrays).
model_for_steps=()
model_for_tiers=()

# FEAT-032 FR-8 resume flags.
approve_advance=0
qa_loop_cap=""

positional=""
positional_count=0

while [ "$#" -gt 0 ]; do
  arg="$1"

  # Reject the `=`-form explicitly.
  case "$arg" in
    --model=*|--complexity=*|--model-for=*|--qa-loop-cap=*)
      echo "[error] parse-model-flags: equals-sign form not supported: $arg" >&2
      exit 2
      ;;
  esac

  case "$arg" in
    --model)
      if [ "$#" -lt 2 ]; then
        echo "[error] parse-model-flags: --model requires a tier argument" >&2
        exit 2
      fi
      if ! _is_bare_tier "$2"; then
        echo "[error] parse-model-flags: --model tier must be haiku|sonnet|opus; got: $2" >&2
        exit 2
      fi
      cli_model="$2"
      shift 2
      ;;
    --complexity)
      if [ "$#" -lt 2 ]; then
        echo "[error] parse-model-flags: --complexity requires a tier argument" >&2
        exit 2
      fi
      normalised="$(_normalise_complexity_tier "$2" 2>/dev/null || true)"
      if [ -z "$normalised" ]; then
        echo "[error] parse-model-flags: --complexity tier must be haiku|sonnet|opus or low|medium|high; got: $2" >&2
        exit 2
      fi
      cli_complexity="$normalised"
      shift 2
      ;;
    --model-for)
      if [ "$#" -lt 2 ]; then
        echo "[error] parse-model-flags: --model-for requires a <step>:<tier> argument" >&2
        exit 2
      fi
      spec="$2"
      if [[ "$spec" != *:* ]]; then
        echo "[error] parse-model-flags: --model-for must be <step>:<tier>; got: $spec" >&2
        exit 2
      fi
      step="${spec%%:*}"
      tier="${spec#*:}"
      if [ -z "$step" ]; then
        echo "[error] parse-model-flags: --model-for step must be non-empty: $spec" >&2
        exit 2
      fi
      if ! _is_bare_tier "$tier"; then
        echo "[error] parse-model-flags: --model-for tier must be haiku|sonnet|opus; got: $tier" >&2
        exit 2
      fi
      # Overwrite last entry for same step; else append.
      found_idx=-1
      i=0
      while [ "$i" -lt "${#model_for_steps[@]}" ]; do
        if [ "${model_for_steps[$i]}" = "$step" ]; then
          found_idx=$i
          break
        fi
        i=$((i + 1))
      done
      if [ "$found_idx" -ge 0 ]; then
        model_for_tiers[$found_idx]="$tier"
      else
        model_for_steps+=("$step")
        model_for_tiers+=("$tier")
      fi
      shift 2
      ;;
    --approve-advance)
      approve_advance=1
      shift 1
      ;;
    --qa-loop-cap)
      if [ "$#" -lt 2 ]; then
        echo "[error] parse-model-flags: --qa-loop-cap requires a positive integer argument" >&2
        exit 2
      fi
      if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "[error] parse-model-flags: --qa-loop-cap must be a positive integer; got: $2" >&2
        exit 2
      fi
      qa_loop_cap="$2"
      shift 2
      ;;
    --*)
      echo "[error] parse-model-flags: unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      positional_count=$((positional_count + 1))
      if [ "$positional_count" -gt 1 ]; then
        echo "[error] parse-model-flags: at most one positional token permitted; got a second: $arg" >&2
        exit 2
      fi
      positional="$arg"
      shift 1
      ;;
  esac
done

# --- FEAT-032 FR-8 mutual-exclusion guard ------------------------------------

if [ "$approve_advance" -eq 1 ] && [ -n "$qa_loop_cap" ]; then
  echo "Error: --approve-advance and --qa-loop-cap are mutually exclusive" >&2
  exit 2
fi

# --- JSON emission ----------------------------------------------------------

_have_jq() {
  command -v jq >/dev/null 2>&1
}

emit_json() {
  if _have_jq; then
    local model_for_json="null"
    if [ "${#model_for_steps[@]}" -gt 0 ]; then
      # Build the map one key at a time with jq --arg.
      model_for_json="$(jq -n '{}')"
      local i=0
      while [ "$i" -lt "${#model_for_steps[@]}" ]; do
        model_for_json="$(jq -n \
          --argjson acc "$model_for_json" \
          --arg step "${model_for_steps[$i]}" \
          --arg tier "${model_for_tiers[$i]}" \
          '$acc + {($step): $tier}')"
        i=$((i + 1))
      done
    fi

    local approve_advance_json="false"
    if [ "$approve_advance" -eq 1 ]; then
      approve_advance_json="true"
    fi
    local qa_loop_cap_json="null"
    if [ -n "$qa_loop_cap" ]; then
      qa_loop_cap_json="$qa_loop_cap"
    fi

    jq -n \
      --arg cliModel "$cli_model" \
      --arg cliComplexity "$cli_complexity" \
      --argjson cliModelFor "$model_for_json" \
      --argjson approveAdvance "$approve_advance_json" \
      --argjson qaLoopCap "$qa_loop_cap_json" \
      --arg positional "$positional" \
      '{
        cliModel: (if $cliModel == "" then null else $cliModel end),
        cliComplexity: (if $cliComplexity == "" then null else $cliComplexity end),
        cliModelFor: $cliModelFor,
        approveAdvance: $approveAdvance,
        qaLoopCap: $qaLoopCap,
        positional: $positional
      }' -c
    return
  fi

  # pure-bash JSON assembly
  local out="{"
  if [ -n "$cli_model" ]; then
    out+="\"cliModel\":\"$cli_model\""
  else
    out+="\"cliModel\":null"
  fi
  out+=","
  if [ -n "$cli_complexity" ]; then
    out+="\"cliComplexity\":\"$cli_complexity\""
  else
    out+="\"cliComplexity\":null"
  fi
  out+=","
  if [ "${#model_for_steps[@]}" -gt 0 ]; then
    out+="\"cliModelFor\":{"
    local i=0
    local first=1
    while [ "$i" -lt "${#model_for_steps[@]}" ]; do
      if [ "$first" -eq 0 ]; then
        out+=","
      fi
      out+="\"${model_for_steps[$i]}\":\"${model_for_tiers[$i]}\""
      first=0
      i=$((i + 1))
    done
    out+="}"
  else
    out+="\"cliModelFor\":null"
  fi
  out+=","
  if [ "$approve_advance" -eq 1 ]; then
    out+="\"approveAdvance\":true"
  else
    out+="\"approveAdvance\":false"
  fi
  out+=","
  if [ -n "$qa_loop_cap" ]; then
    out+="\"qaLoopCap\":$qa_loop_cap"
  else
    out+="\"qaLoopCap\":null"
  fi
  out+=","
  # Escape positional value's backslashes and double-quotes for JSON.
  local pos_escaped="${positional//\\/\\\\}"
  pos_escaped="${pos_escaped//\"/\\\"}"
  out+="\"positional\":\"$pos_escaped\""
  out+="}"
  printf '%s\n' "$out"
}

emit_json
exit 0
