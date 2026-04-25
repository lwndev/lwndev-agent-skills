#!/usr/bin/env bash
# split-phase-suggest.sh — Advisory phase-split heuristic (FEAT-029 / FR-4).
#
# Usage: split-phase-suggest.sh <plan-file> <phase-N>
#
# Reads the requested phase block, extracts the implementation-step list,
# and proposes a contiguous split into roughly equal chunks. Honours
# explicit `Depends on Step <N>` annotations within step lines so a chunk
# never terminates before its prerequisite step is included.
#
# Default split shape:
#   ≤3 steps        → no split, returns `{"original":N,"suggestions":[]}`.
#   4–7 steps       → 2-way split.
#   ≥8 steps        → 3-way split.
#
# Stdout: single JSON object
#   {
#     "original": <total-step-count>,
#     "suggestions": [
#       {"name": "<heuristic-name>", "steps": [1, 2, 3]},
#       ...
#     ]
#   }
#
# Output is advisory only. The script never writes the plan file. The
# semantic judgment (does this split keep TDD pairing intact? does it
# preserve the phase's narrative arc?) remains the model's responsibility.
#
# Exit codes:
#   0  success (including the no-split case for ≤3 steps).
#   1  plan I/O error or phase block missing.
#   2  missing args.
#
# Bash 3.2-compatible (macOS ships /bin/bash 3.2). No associative arrays,
# no mapfile, no ${var,,}.

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "error: usage: split-phase-suggest.sh <plan-file> <phase-N>" >&2
  exit 2
fi

plan="$1"
phase_n="$2"

if ! printf '%s' "$phase_n" | grep -Eq '^[1-9][0-9]*$'; then
  echo "error: <phase-N> must be a positive integer, got: ${phase_n}" >&2
  exit 2
fi

if [ ! -f "$plan" ] || [ ! -r "$plan" ]; then
  echo "error: plan file not found or unreadable: ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract the requested phase block. Reuse the fence-aware block scanner
# established by Phase 2.
#
# awk emits one record per step line (and one record per deliverable line)
# inside the requested phase. Records are delimited by ASCII US (\x1f) on
# stdout; lines are tagged with a leading kind:
#
#   step\x1f<index>\x1f<text>
#   deliv\x1f<text>
# ---------------------------------------------------------------------------

US=$'\x1f'

parsed=$(
  tr -d '\r' < "$plan" \
    | awk -v want="$phase_n" -v US="$US" '
        BEGIN {
          in_fence = 0
          in_phase = 0
          target_seen = 0
          in_steps = 0
          in_deliv = 0
          step_idx = 0
        }
        {
          line = $0
          stripped = line
          sub(/^[ \t]+/, "", stripped)

          if (stripped ~ /^(```|~~~)/) {
            in_fence = !in_fence
            next
          }
          if (in_fence) next

          if (match(line, /^###[ ]+Phase[ ]+[0-9]+:/)) {
            num = line
            sub(/^###[ ]+Phase[ ]+/, "", num)
            sub(/:.*$/, "", num)
            if (num == want) {
              in_phase = 1
              target_seen = 1
              in_steps = 0
              in_deliv = 0
              step_idx = 0
            } else if (in_phase) {
              # Leaving the target phase.
              exit
            }
            next
          }

          if (!in_phase) next

          if (match(line, /^####[ ]+Implementation Steps[ \t]*$/)) {
            in_steps = 1
            in_deliv = 0
            next
          }
          if (match(line, /^####[ ]+Deliverables[ \t]*$/)) {
            in_steps = 0
            in_deliv = 1
            next
          }
          if (match(line, /^####[ ]+/)) {
            in_steps = 0
            in_deliv = 0
            next
          }

          if (in_steps && match(line, /^[0-9]+\./)) {
            step_idx += 1
            text = line
            sub(/^[0-9]+\.[ \t]*/, "", text)
            printf "step%s%d%s%s\n", US, step_idx, US, text
            next
          }

          if (in_deliv && match(line, /^-[ ]+\[[ xX]\]/)) {
            text = line
            sub(/^-[ ]+\[[ xX]\][ \t]*/, "", text)
            printf "deliv%s%s\n", US, text
            next
          }
        }
        END {
          if (!target_seen) exit 2
        }
      '
) || awk_status=$?

awk_status="${awk_status:-0}"

if [ "$awk_status" -eq 2 ]; then
  echo "error: phase ${phase_n} not found in ${plan}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read records into parallel arrays.
# ---------------------------------------------------------------------------
step_idx_list=()
step_text_list=()
deliv_text_list=()

while IFS= read -r record; do
  [ -z "$record" ] && continue
  kind="${record%%${US}*}"
  rest="${record#*${US}}"
  case "$kind" in
    step)
      idx="${rest%%${US}*}"
      text="${rest#*${US}}"
      step_idx_list+=("$idx")
      step_text_list+=("$text")
      ;;
    deliv)
      deliv_text_list+=("$rest")
      ;;
  esac
done <<< "$parsed"

step_count=${#step_idx_list[@]}

# ---------------------------------------------------------------------------
# Emit `{"original":N,"suggestions":[]}` when the phase has ≤3 steps.
# ---------------------------------------------------------------------------
emit_empty() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson original "$step_count" '{original:$original,suggestions:[]}'
  else
    printf '{"original":%d,"suggestions":[]}\n' "$step_count"
  fi
}

if [ "$step_count" -le 3 ]; then
  emit_empty
  exit 0
fi

# ---------------------------------------------------------------------------
# Decide split arity: 2-way for 4–7 steps, 3-way for ≥8.
# ---------------------------------------------------------------------------
if [ "$step_count" -le 7 ]; then
  arity=2
else
  arity=3
fi

# ---------------------------------------------------------------------------
# Parse explicit `Depends on Step <N>` annotations from each step text.
# `prereq[i]` holds the highest prerequisite step index for step (i+1), or
# 0 when none.
# ---------------------------------------------------------------------------
prereq=()
i=0
while [ "$i" -lt "$step_count" ]; do
  text="${step_text_list[$i]}"
  text_lc="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  hi=0
  rest="$text_lc"
  while :; do
    # Match "depends on step <N>" (case-insensitive via lowercased copy).
    match="$(printf '%s' "$rest" | grep -oE 'depends on step[ ]+[0-9]+' | head -n1 || true)"
    [ -z "$match" ] && break
    n="$(printf '%s' "$match" | grep -oE '[0-9]+' | head -n1)"
    if [ "$n" -gt "$hi" ]; then
      hi="$n"
    fi
    # Trim past this match for the next iteration.
    rest="${rest#*$match}"
  done
  prereq+=("$hi")
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Reject impossible dependency annotations: a step cannot declare a
# `Depends on Step <N>` where N is the step's own position or a later
# step (forward-pointing). Such constraints are unsatisfiable in any
# chunking, and the constraint loop below would silently swallow them.
# Surface a diagnostic so the model can repair the plan instead.
# ---------------------------------------------------------------------------
i=0
while [ "$i" -lt "$step_count" ]; do
  p="${prereq[$i]}"
  step_num=$((i + 1))
  if [ "$p" -gt 0 ] && [ "$p" -ge "$step_num" ]; then
    printf '[error] split-phase-suggest: phase has impossible dependency — step %d declares "Depends on Step %d" (>= own position).\n' "$step_num" "$p" >&2
    exit 1
  fi
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Compute initial chunk boundaries (1-based, inclusive end indices) by
# spreading `step_count` items across `arity` chunks within ±1.
# ---------------------------------------------------------------------------
base=$((step_count / arity))
extra=$((step_count - base * arity))

boundaries=()  # inclusive end index per chunk, 1-based
acc=0
c=0
while [ "$c" -lt "$arity" ]; do
  size=$base
  if [ "$c" -lt "$extra" ]; then
    size=$((size + 1))
  fi
  acc=$((acc + size))
  boundaries+=("$acc")
  c=$((c + 1))
done

# ---------------------------------------------------------------------------
# Adjust boundaries to honour `Depends on Step <N>` constraints.
#
# Constraint: if a step at index k has prereq p>0, then step p must be in
# the same chunk as step k or in an earlier chunk. Equivalently, no chunk
# boundary may fall between step p and step k. If a boundary at end-index
# `b` violates this (b >= p AND b < k), push it forward to k (so k is
# included in the same chunk as p).
#
# We sweep chunks left-to-right, repeatedly extending the current
# boundary forward until no constraint is violated within the chunk's
# range. The final chunk always ends at step_count.
# ---------------------------------------------------------------------------
chunk_start=1
adjusted=()
c=0
while [ "$c" -lt "$arity" ]; do
  if [ "$c" -eq $((arity - 1)) ]; then
    end=$step_count
  else
    end="${boundaries[$c]}"
  fi

  # Keep extending `end` while any step in [chunk_start..end] has a
  # prereq that lies in [chunk_start..end] but its dependent (k) is at
  # an index > end. Equivalently: any step k > end has prereq <= end.
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    if [ "$end" -ge "$step_count" ]; then
      end=$step_count
      break
    fi
    # For every step k in (end+1..step_count), check whether its prereq
    # falls within [chunk_start..end]. If so, the chunk would terminate
    # before k while k depends on a step the chunk owns — we must extend
    # `end` to include k.
    k=$((end + 1))
    while [ "$k" -le "$step_count" ]; do
      p="${prereq[$((k - 1))]}"
      if [ "$p" -gt 0 ] && [ "$p" -ge "$chunk_start" ] && [ "$p" -le "$end" ]; then
        end=$k
        changed=1
        break
      fi
      k=$((k + 1))
    done
  done

  adjusted+=("$end")
  chunk_start=$((end + 1))
  if [ "$chunk_start" -gt "$step_count" ]; then
    # Remaining chunks become empty — collapse arity in practice.
    break
  fi
  c=$((c + 1))
done

# ---------------------------------------------------------------------------
# Build the actual chunk lists.
# ---------------------------------------------------------------------------
chunk_starts=()
chunk_ends=()
chunk_start=1
for end in "${adjusted[@]}"; do
  chunk_starts+=("$chunk_start")
  chunk_ends+=("$end")
  chunk_start=$((end + 1))
done

# ---------------------------------------------------------------------------
# Derive a heuristic name per chunk: leading verb of first step + a noun
# pulled from the deliverable list (best-effort). The model authors the
# real names; this is a placeholder with enough signal to be useful in
# review.
# ---------------------------------------------------------------------------
extract_first_word() {
  printf '%s' "$1" | awk '{ for (i=1;i<=NF;i++) { gsub(/[^A-Za-z0-9_-]/, "", $i); if ($i != "") { print $i; exit } } }'
}

# Pull a noun token from the deliverable list: prefer the basename of the
# first backticked path; fall back to the first deliverable's first word.
extract_noun() {
  if [ "${#deliv_text_list[@]}" -eq 0 ]; then
    printf 'work'
    return
  fi
  for d in "${deliv_text_list[@]}"; do
    tok="$(printf '%s' "$d" | grep -oE '`[^`]+`' | head -n1 || true)"
    if [ -n "$tok" ]; then
      tok="${tok#\`}"
      tok="${tok%\`}"
      base="$(basename "$tok")"
      base="${base%.*}"
      if [ -n "$base" ]; then
        printf '%s' "$base"
        return
      fi
    fi
  done
  extract_first_word "${deliv_text_list[0]}"
}

noun="$(extract_noun)"
if [ -z "$noun" ]; then
  noun="work"
fi

chunk_names=()
i=0
while [ "$i" -lt "${#chunk_starts[@]}" ]; do
  s="${chunk_starts[$i]}"
  verb="$(extract_first_word "${step_text_list[$((s - 1))]}")"
  if [ -z "$verb" ]; then
    verb="step"
  fi
  # Lowercase the verb for a friendlier label.
  verb_lc="$(printf '%s' "$verb" | tr '[:upper:]' '[:lower:]')"
  chunk_names+=("${verb_lc}-${noun}")
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Emit JSON.
# ---------------------------------------------------------------------------
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

build_steps_array() {
  local s="$1"
  local e="$2"
  local out="["
  local first=1
  local k=$s
  while [ "$k" -le "$e" ]; do
    if [ "$first" -eq 1 ]; then
      out="${out}${k}"
      first=0
    else
      out="${out},${k}"
    fi
    k=$((k + 1))
  done
  out="${out}]"
  printf '%s' "$out"
}

if command -v jq >/dev/null 2>&1; then
  # Build a JSON array of {name, steps} objects via jq.
  args=( -cn --argjson original "$step_count" )
  filter='{original:$original, suggestions: ['
  i=0
  while [ "$i" -lt "${#chunk_starts[@]}" ]; do
    s="${chunk_starts[$i]}"
    e="${chunk_ends[$i]}"
    name="${chunk_names[$i]}"
    steps_arr="$(build_steps_array "$s" "$e")"
    args+=( --arg "name${i}" "$name" --argjson "steps${i}" "$steps_arr" )
    if [ "$i" -gt 0 ]; then
      filter="${filter},"
    fi
    filter="${filter}{name:\$name${i},steps:\$steps${i}}"
    i=$((i + 1))
  done
  filter="${filter}]}"
  jq "${args[@]}" "$filter"
else
  out="{\"original\":${step_count},\"suggestions\":["
  first=1
  i=0
  while [ "$i" -lt "${#chunk_starts[@]}" ]; do
    s="${chunk_starts[$i]}"
    e="${chunk_ends[$i]}"
    name_esc="$(json_escape "${chunk_names[$i]}")"
    steps_arr="$(build_steps_array "$s" "$e")"
    if [ "$first" -eq 1 ]; then
      first=0
    else
      out="${out},"
    fi
    out="${out}{\"name\":\"${name_esc}\",\"steps\":${steps_arr}}"
    i=$((i + 1))
  done
  out="${out}]}"
  printf '%s\n' "$out"
fi

exit 0
