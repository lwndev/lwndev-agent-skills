#!/usr/bin/env bash
set -euo pipefail

# qa-reconcile-delta.sh (FR-6, also closes #192) — Bidirectional FR-N / NFR-N
# / AC / edge-case match between a QA results artifact and the requirements
# doc it was executed against. Emits the markdown body for the artifact's
# `## Reconciliation Delta` section (without the heading itself; caller
# inserts that).
#
# Usage:
#   qa-reconcile-delta.sh <results-doc> <requirements-doc>
#
# Args:
#   <results-doc>      Path to qa/test-results/QA-results-{ID}.md.
#   <requirements-doc> Path to the requirements doc (FEAT-* / CHORE-* / BUG-*).
#
# Output:
#   stdout markdown:
#     ### Coverage beyond requirements
#     - <item>
#     ### Coverage gaps
#     - <item>
#     ### Summary
#     - coverage-surplus: N
#     - coverage-gap: N
#
# Exit codes:
#   0  delta produced (also when in full alignment — empty lists, zeros)
#   1  requirements doc not found
#   2  missing/invalid args

usage() {
  echo "Usage: qa-reconcile-delta.sh <results-doc> <requirements-doc>" >&2
}

if [[ $# -ne 2 ]]; then
  echo "Error: expected 2 args, got $#." >&2
  usage
  exit 2
fi

RESULTS_DOC="$1"
REQS_DOC="$2"

if [[ ! -f "$RESULTS_DOC" ]]; then
  echo "Error: results doc not found: $RESULTS_DOC" >&2
  exit 2
fi
if [[ ! -f "$REQS_DOC" ]]; then
  echo "Error: requirements doc not found: $REQS_DOC" >&2
  exit 1
fi

# strip_fenced_code <file> — emit file contents with fenced ``` blocks removed.
# Identifier matches inside fenced code blocks (e.g., FR-3 in a sample command)
# must NOT count as spec references.
strip_fenced_code() {
  local file="$1"
  awk '
    BEGIN { in_fence = 0 }
    /^[[:space:]]*```/ {
      in_fence = !in_fence
      next
    }
    {
      if (!in_fence) print
    }
  ' "$file"
}

# extract_section <stripped-text> <heading-regex>
# Emit lines from after the heading up to (but excluding) the next `## ` heading
# at the same level.
extract_section() {
  local text="$1"
  local heading="$2"
  printf '%s\n' "$text" | awk -v h="$heading" '
    BEGIN { in_section = 0 }
    {
      if ($0 ~ ("^## " h "([[:space:]]|$)")) {
        in_section = 1
        next
      }
      if (in_section && /^## /) {
        in_section = 0
      }
      if (in_section) print
    }
  '
}

# Normalize identifier (FR-03 -> FR-3, NFR-007 -> NFR-7).
normalize_id() {
  local raw="$1"
  local prefix="${raw%%-*}"
  local num="${raw#*-}"
  # Strip leading zeros; default to "0".
  num="$(printf '%d' "$((10#${num}))" 2>/dev/null || printf '0')"
  printf '%s-%s' "$prefix" "$num"
}

# requirements_items
#   Read REQS_DOC, strip fenced code, extract FR/NFR identifiers from
#   `## Functional Requirements` and `## Non-Functional Requirements`,
#   AC identifiers from `## Acceptance Criteria`, and edge-case lines from
#   `## Edge Cases`. Emit one record per line, tab-separated:
#     <kind>\t<identifier>\t<short-summary>
#   where <kind> is one of fr | nfr | ac | edge.
requirements_items() {
  local stripped
  stripped="$(strip_fenced_code "$REQS_DOC")"

  # FR section
  local fr_section
  fr_section="$(extract_section "$stripped" 'Functional Requirements')"
  if [[ -n "$fr_section" ]]; then
    # Walk full lines so we can capture the summary that follows the identifier
    # without losing trailing words to grep -oE truncation.
    while IFS= read -r line; do
      local id summary
      id="$(printf '%s' "$line" | grep -oE 'FR-[0-9]+' | head -n 1 || true)"
      [[ -z "$id" ]] && continue
      id="$(normalize_id "$id")"
      # Strip leading bullet markers + the identifier + any **/colon/dash glue.
      summary="$(printf '%s' "$line" | sed -E 's/.*FR-[0-9]+[*:[:space:]_-]*//' | tr -d '*`')"
      summary="${summary:0:160}"
      printf '%s\t%s\t%s\n' "fr" "$id" "$summary"
    done <<< "$fr_section"
  fi

  # NFR section
  local nfr_section
  nfr_section="$(extract_section "$stripped" 'Non-Functional Requirements')"
  if [[ -n "$nfr_section" ]]; then
    while IFS= read -r line; do
      local id summary
      id="$(printf '%s' "$line" | grep -oE 'NFR-[0-9]+' | head -n 1 || true)"
      [[ -z "$id" ]] && continue
      id="$(normalize_id "$id")"
      summary="$(printf '%s' "$line" | sed -E 's/.*NFR-[0-9]+[*:[:space:]_-]*//' | tr -d '*`')"
      summary="${summary:0:160}"
      printf '%s\t%s\t%s\n' "nfr" "$id" "$summary"
    done <<< "$nfr_section"
  fi

  # AC section — items are bulleted lines or numbered. Identifier is the first
  # quoted phrase or, when absent, the first 80 chars of the line.
  local ac_section
  ac_section="$(extract_section "$stripped" 'Acceptance Criteria')"
  if [[ -n "$ac_section" ]]; then
    local idx=0
    while IFS= read -r line; do
      # Bulleted items only.
      if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+ ]]; then
        idx=$((idx + 1))
        local body="${line#*[-*] }"
        body="${body## }"
        local summary="${body:0:120}"
        printf '%s\t%s\t%s\n' "ac" "AC-$idx" "$summary"
      fi
    done <<< "$ac_section"
  fi

  # Edge cases — bulleted or numbered lines under `## Edge Cases`.
  local edge_section
  edge_section="$(extract_section "$stripped" 'Edge Cases')"
  if [[ -n "$edge_section" ]]; then
    local idx=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+ ]] || [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+ ]]; then
        idx=$((idx + 1))
        local body
        body="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+//')"
        local summary="${body:0:120}"
        printf '%s\t%s\t%s\n' "edge" "EDGE-$idx" "$summary"
      fi
    done <<< "$edge_section"
  fi
}

# results_items
#   Parse `## Scenarios Run` and `## Findings` from RESULTS_DOC. Emit
#   one record per line, tab-separated:
#     <source>\t<title>\t<refs>
#   where <source> is `scenario` or `finding`, <title> is the bullet text,
#   and <refs> is a comma-separated list of FR-N/NFR-N/AC-N/EDGE-N tokens
#   that appear inside the same bullet (used for matching).
results_items() {
  local stripped
  stripped="$(strip_fenced_code "$RESULTS_DOC")"

  for section in 'Scenarios Run' 'Findings'; do
    local section_text
    section_text="$(extract_section "$stripped" "$section")"
    [[ -z "$section_text" ]] && continue
    local source_kind
    if [[ "$section" == "Scenarios Run" ]]; then
      source_kind="scenario"
    else
      source_kind="finding"
    fi
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+ ]]; then
        local body
        body="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]+//')"
        local title="${body:0:160}"
        # Find spec-token references inside the bullet.
        local refs
        refs="$(printf '%s' "$body" | grep -oE '\b(FR|NFR|AC|EDGE)-[0-9]+\b' | sort -u | paste -sd, - || true)"
        printf '%s\t%s\t%s\n' "$source_kind" "$title" "$refs"
      fi
    done <<< "$section_text"
  done
}

REQS_RECORDS_FILE="$(mktemp)"
RESULTS_RECORDS_FILE="$(mktemp)"
trap 'rm -f "$REQS_RECORDS_FILE" "$RESULTS_RECORDS_FILE"' EXIT

requirements_items > "$REQS_RECORDS_FILE"
results_items     > "$RESULTS_RECORDS_FILE"

GAPS_FILE="$(mktemp)"
SURPLUS_FILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$REQS_RECORDS_FILE' '$RESULTS_RECORDS_FILE' '$GAPS_FILE' '$SURPLUS_FILE'" EXIT

# Bidirectional matching is performed in a single awk pass for performance.
# Token rule: lowercase, alphanumeric run >= 4 chars. A bullet matches a
# requirement when (a) the bullet cites the requirement identifier, or (b)
# the bullet and the requirement share at least two distinct >=4-char tokens.
awk -F'\t' '
  BEGIN {
    # Coerce counters to numeric 0; otherwise the first
    # `req_id[NR_R] = $2` keys under "" (empty string), and the END loop
    # using numeric `j` then misses every record.
    NR_R = 0
    NR_S = 0
  }
  function tokenize(text,    i, n, parts, out) {
    # Lowercase, replace non-alphanumeric with space, split on space, keep
    # tokens of length >= 4.
    text = tolower(text)
    gsub(/[^a-z0-9 ]+/, " ", text)
    n = split(text, parts, /[[:space:]]+/)
    delete out
    for (i = 1; i <= n; i++) {
      if (length(parts[i]) >= 4) {
        out[parts[i]] = 1
      }
    }
    return out_len(out)
  }
  function out_len(arr,    k, c) { c = 0; for (k in arr) c++; return c }

  FILENAME == reqs_file {
    # Each line: kind \t id \t summary
    rid = $2; rsummary = $3
    req_id[NR_R] = rid
    req_kind[NR_R] = $1
    req_summary[NR_R] = rsummary
    # Build per-requirement token set.
    delete tmp_tokens
    tokenize(rsummary)
    # Save tokens in a flat string for sharing-count comparison.
    req_tokens[NR_R] = ""
    text = tolower(rsummary)
    gsub(/[^a-z0-9 ]+/, " ", text)
    n = split(text, parts, /[[:space:]]+/)
    seen = ""
    for (i = 1; i <= n; i++) {
      if (length(parts[i]) >= 4) {
        if (index(seen, " " parts[i] " ") == 0) {
          seen = seen " " parts[i] " "
        }
      }
    }
    req_tokens[NR_R] = seen
    NR_R++
    next
  }
  FILENAME == results_file {
    src = $1; rtitle = $2; rrefs = $3
    res_src[NR_S] = src
    res_title[NR_S] = rtitle
    res_refs[NR_S] = rrefs
    text = tolower(rtitle)
    gsub(/[^a-z0-9 ]+/, " ", text)
    n = split(text, parts, /[[:space:]]+/)
    seen = ""
    for (i = 1; i <= n; i++) {
      if (length(parts[i]) >= 4) {
        if (index(seen, " " parts[i] " ") == 0) {
          seen = seen " " parts[i] " "
        }
      }
    }
    res_tokens[NR_S] = seen
    NR_S++
    next
  }

  END {
    # For every requirement, decide covered / not.
    for (i = 0; i < NR_R; i++) {
      covered = 0
      rid = req_id[i]
      # Identifier-citation check: does any results bullet cite this id?
      for (j = 0; j < NR_S; j++) {
        # Match the id surrounded by non-alphanumeric or end-of-field.
        if (match(res_refs[j], "(^|,)" rid "(,|$)") > 0) { covered = 1; break }
        # Also tolerate the id appearing inside the title text itself.
        if (index(" " res_title[j] " ", " " rid " ") > 0 || \
            index(" " res_title[j] " ", "(" rid ")") > 0 || \
            index(res_title[j], rid) > 0) { covered = 1; break }
      }
      if (covered) { req_covered[i] = 1; continue }
      # Substring-token >=2 overlap check.
      n = split(req_tokens[i], rtoks, /[[:space:]]+/)
      for (j = 0; j < NR_S; j++) {
        m = 0
        ttok_str = res_tokens[j]
        for (k = 1; k <= n; k++) {
          tk = rtoks[k]
          if (length(tk) < 4) continue
          if (index(ttok_str, " " tk " ") > 0) m++
          if (m >= 2) break
        }
        if (m >= 2) { covered = 1; break }
      }
      req_covered[i] = covered
    }

    # For every result bullet, decide matched / not.
    for (j = 0; j < NR_S; j++) {
      matched = 0
      # Explicit identifier reference resolves first.
      n_refs = split(res_refs[j], rfs, ",")
      for (r = 1; r <= n_refs; r++) {
        ref = rfs[r]
        if (length(ref) == 0) continue
        for (i = 0; i < NR_R; i++) {
          if (req_id[i] == ref) { matched = 1; break }
        }
        if (matched) break
      }
      if (matched) { res_matched[j] = 1; continue }
      # Substring-token overlap.
      n = split(res_tokens[j], ttoks, /[[:space:]]+/)
      for (i = 0; i < NR_R; i++) {
        m = 0
        rtok_str = req_tokens[i]
        for (k = 1; k <= n; k++) {
          tk = ttoks[k]
          if (length(tk) < 4) continue
          if (index(rtok_str, " " tk " ") > 0) m++
          if (m >= 2) break
        }
        if (m >= 2) { matched = 1; break }
      }
      res_matched[j] = matched
    }

    # Emit gap lines.
    for (i = 0; i < NR_R; i++) {
      if (!req_covered[i]) {
        s = req_summary[i]
        if (length(s) == 0) s = req_kind[i] " item"
        printf("GAP\t- %s \"%s\" — no corresponding scenario in plan\n", req_id[i], s)
      }
    }
    # Emit surplus lines.
    for (j = 0; j < NR_S; j++) {
      if (!res_matched[j]) {
        if (res_src[j] == "scenario") {
          printf("SURPLUS\t- Scenario \"%s\" — not mentioned in spec\n", res_title[j])
        } else {
          printf("SURPLUS\t- Finding \"%s\" — not mentioned in spec\n", res_title[j])
        }
      }
    }
  }
' \
  reqs_file="$REQS_RECORDS_FILE" results_file="$RESULTS_RECORDS_FILE" \
  "$REQS_RECORDS_FILE" "$RESULTS_RECORDS_FILE" \
  | awk -F'\t' -v gaps="$GAPS_FILE" -v surplus="$SURPLUS_FILE" '
    $1 == "GAP"     { print $2 >> gaps }
    $1 == "SURPLUS" { print $2 >> surplus }
  '

GAP_COUNT=$( [[ -s "$GAPS_FILE" ]] && wc -l < "$GAPS_FILE" | tr -d ' ' || echo 0 )
SURPLUS_COUNT=$( [[ -s "$SURPLUS_FILE" ]] && wc -l < "$SURPLUS_FILE" | tr -d ' ' || echo 0 )

echo "### Coverage beyond requirements"
if [[ "$SURPLUS_COUNT" -gt 0 ]]; then
  cat "$SURPLUS_FILE"
fi
echo ""
echo "### Coverage gaps"
if [[ "$GAP_COUNT" -gt 0 ]]; then
  cat "$GAPS_FILE"
fi
echo ""
echo "### Summary"
echo "- coverage-surplus: $SURPLUS_COUNT"
echo "- coverage-gap: $GAP_COUNT"

exit 0
