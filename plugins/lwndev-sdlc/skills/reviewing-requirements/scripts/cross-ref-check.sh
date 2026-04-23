#!/usr/bin/env bash
# cross-ref-check.sh — Focused cross-reference verification (FEAT-026 / FR-4).
#
# Extracts FEAT-/CHORE-/BUG- cross-references from a requirement document via
# the sibling `extract-references.sh` and verifies each one resolves to exactly
# one requirement file under `requirements/{features,chores,bugs}/<REF>-*.md`.
# A narrow wrapper for callers that only need the cross-ref slice (SKILL.md
# Step 7) without the full four-category extract + verify round-trip.
#
# Usage:
#   cross-ref-check.sh <doc-path>
#
# Exit codes:
#   0  success (classification emitted)
#   1  <doc-path> not found / unreadable, or extract-references.sh failed
#   2  missing arg
#
# Dependencies:
#   bash, ls. `jq` is optional — used for JSON assembly when available; falls
#   back to pure-bash printf construction otherwise. `extract-references.sh`
#   must exist alongside this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT="${SCRIPT_DIR}/extract-references.sh"

# --- Argument handling --------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "[error] usage: cross-ref-check.sh <doc-path>" >&2
  exit 2
fi

DOC_PATH="$1"

if [[ ! -r "$DOC_PATH" || ! -f "$DOC_PATH" ]]; then
  echo "[error] cross-ref-check: cannot read file: ${DOC_PATH}" >&2
  exit 1
fi

if [[ ! -x "$EXTRACT" && ! -r "$EXTRACT" ]]; then
  echo "[error] cross-ref-check: extract-references.sh not found at ${EXTRACT}" >&2
  exit 1
fi

# --- Run extract-references ---------------------------------------------------
REFS_JSON=$(bash "$EXTRACT" "$DOC_PATH")

# Pull the crossRefs array out. Prefer jq; fall back to a narrow grep/sed.
if command -v jq >/dev/null 2>&1; then
  cross_refs=$(printf '%s' "$REFS_JSON" | jq -r '.crossRefs[]? // empty')
else
  # Assume the canonical single-line output from extract-references.sh.
  # Grab the text between `"crossRefs":[` and the next `]`, split on `,`,
  # strip quotes.
  cross_refs=$(
    printf '%s' "$REFS_JSON" \
      | sed -n 's/.*"crossRefs":\[\([^]]*\)\].*/\1/p' \
      | tr ',' '\n' \
      | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' \
      | grep -E '^(FEAT|CHORE|BUG)-[0-9]+$' || true
  )
fi

# --- Helpers ------------------------------------------------------------------

emit_json_array_of_entries() {
  # Input: each line is `<ref>|<detail>` (detail may be empty).
  if command -v jq >/dev/null 2>&1; then
    jq -Rs '
      split("\n")
      | map(select(length > 0))
      | map(
          . as $line
          | ($line | index("|")) as $i
          | if $i == null
              then {category: "crossRefs", ref: $line, detail: ""}
              else {category: "crossRefs",
                    ref: $line[0:$i],
                    detail: $line[$i+1:]}
            end
        )
    '
  else
    local first=1
    printf '['
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ref detail
      ref="${line%%|*}"
      if [[ "$line" == *"|"* ]]; then
        detail="${line#*|}"
      else
        detail=""
      fi
      if [[ "$first" -eq 1 ]]; then first=0; else printf ','; fi
      local d_esc="${detail//\\/\\\\}"
      d_esc="${d_esc//\"/\\\"}"
      d_esc="${d_esc//$'\t'/\\t}"
      d_esc="${d_esc//$'\r'/\\r}"
      d_esc="${d_esc//$'\n'/\\n}"
      printf '{"category":"crossRefs","ref":"%s","detail":"%s"}' "$ref" "$d_esc"
    done
    printf ']'
  fi
}

# --- Classification -----------------------------------------------------------

ok_lines=""
ambiguous_lines=""
missing_lines=""

while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  case "$ref" in
    FEAT-*) subdir="features" ;;
    CHORE-*) subdir="chores" ;;
    BUG-*) subdir="bugs" ;;
    *) continue ;;
  esac

  # Enumerate matching files. A non-matching glob is left literal by default in
  # bash; use a nullglob-lite pattern via `compgen -G` to avoid that.
  matches=()
  while IFS= read -r match; do
    [[ -n "$match" ]] && matches+=("$match")
  done < <(compgen -G "requirements/${subdir}/${ref}-*.md" 2>/dev/null || true)

  count=${#matches[@]}
  if [[ "$count" -eq 1 ]]; then
    ok_lines+="${ref}|${matches[0]}"$'\n'
  elif [[ "$count" -eq 0 ]]; then
    missing_lines+="${ref}|no file matching requirements/${subdir}/${ref}-*.md"$'\n'
  else
    detail="multiple matches: $(IFS=,; echo "${matches[*]}")"
    ambiguous_lines+="${ref}|${detail}"$'\n'
  fi
done <<<"$cross_refs"

arr_ok=$(printf '%s' "$ok_lines" | emit_json_array_of_entries)
arr_amb=$(printf '%s' "$ambiguous_lines" | emit_json_array_of_entries)
arr_miss=$(printf '%s' "$missing_lines" | emit_json_array_of_entries)

if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --argjson ok "$arr_ok" \
    --argjson amb "$arr_amb" \
    --argjson miss "$arr_miss" \
    '{ok: $ok, ambiguous: $amb, missing: $miss}'
else
  printf '{"ok":%s,"ambiguous":%s,"missing":%s}\n' "$arr_ok" "$arr_amb" "$arr_miss"
fi
