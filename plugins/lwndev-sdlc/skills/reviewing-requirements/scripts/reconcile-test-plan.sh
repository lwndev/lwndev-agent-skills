#!/usr/bin/env bash
# TODO(NFR-6 / FEAT-026): This matcher shares logic with executing-qa's upcoming
# qa-reconcile-delta.sh. Factor into lib/match-traceability.sh when that script
# lands. The PR that ships second reconciles the duplication.
# See: requirements/features/FEAT-026-reviewing-requirements-scripts.md NFR-6.
#
# reconcile-test-plan.sh — Bidirectional traceability matcher between a
# requirement document and its QA test plan (FEAT-026 / FR-5).
#
# Parses both documents and emits a classification object with five arrays:
#   {"gaps":[],"contradictions":[],"surplus":[],"drift":[],"modeMismatch":[]}
# Each entry is {"id":"FR-3","location":"req-doc|test-plan:<line>","detail":"..."}.
#
# Match classes (R1–R5 from SKILL.md):
#   R1 (gaps)          — requirement-side IDs with no matching test-plan scenario.
#   R2 (contradictions)— scenarios referencing a requirement ID whose `expected:`
#                        phrase appears to disagree with the requirement body.
#                        Surfaces the mismatch; the model decides if it is real.
#   R3 (surplus)       — scenarios with no requirement-side ID reference.
#   R4 (drift)         — scenario priority tag disagrees with requirement priority.
#   R5 (modeMismatch)  — scenario `mode:` disagrees with Testing Requirements
#                        guidance in the requirement doc.
#
# Test-plan format support (NFR-3):
#   * Version-2 prose: lines starting with `[P0]`, `[P1]`, or `[P2]`. IDs can
#     appear anywhere after the priority tag (including embedded inside
#     `expected:` text, e.g. `expected: FR-4 condition 1 satisfied`).
#   * Legacy table: rows with `| RC-N | AC-N |` style columns. Detected by the
#     presence of `| RC-` or `| AC-` column-cell markers.
#
# Usage:
#   reconcile-test-plan.sh <req-doc> <plan-doc>
#
# Exit codes:
#   0  success (any classification including all-empty)
#   1  unreadable input files; req-doc missing `## Acceptance Criteria`;
#      test plan contains zero parseable scenario lines
#   2  missing args
#
# Dependencies:
#   bash, grep, awk, sed. `jq` is optional — used for JSON assembly when
#   available; falls back to pure-bash printf construction otherwise.

set -euo pipefail

# --- Argument handling --------------------------------------------------------

if [[ $# -lt 2 ]]; then
  echo "[error] usage: reconcile-test-plan.sh <req-doc> <plan-doc>" >&2
  exit 2
fi

REQ_DOC="$1"
PLAN_DOC="$2"

if [[ -z "$REQ_DOC" || -z "$PLAN_DOC" ]]; then
  echo "[error] usage: reconcile-test-plan.sh <req-doc> <plan-doc>" >&2
  exit 2
fi

if [[ ! -r "$REQ_DOC" || ! -f "$REQ_DOC" ]]; then
  echo "[error] reconcile-test-plan: cannot read req-doc: ${REQ_DOC}" >&2
  exit 1
fi
if [[ ! -r "$PLAN_DOC" || ! -f "$PLAN_DOC" ]]; then
  echo "[error] reconcile-test-plan: cannot read plan-doc: ${PLAN_DOC}" >&2
  exit 1
fi

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# --- Requirement-doc parsing --------------------------------------------------
# Collect:
#   REQ_IDS_LIST          — newline-separated list of all requirement-side IDs
#                           (FR-N, NFR-N, RC-N, AC-N).
#   REQ_BODIES            — "ID|body" records (one line per ID; body is the
#                           first line of the section after the heading,
#                           compressed to single-line).
#   REQ_PRIORITY_PER_ID   — "ID|P0|P1|P2" records when a Priority field is
#                           present for that ID (or the doc-level priority).
#   REQ_TESTING_MODE      — executable|exploratory|manual|unknown (from a
#                           Testing Requirements heading's body text).

REQ_IDS_LIST=""
REQ_BODIES=""
REQ_PRIORITY_PER_ID=""
REQ_TESTING_MODE="unknown"

# Ensure the requirement doc has an Acceptance Criteria heading.
if ! grep -qE '^##[[:space:]]+Acceptance Criteria' "$REQ_DOC"; then
  echo "[error] reconcile-test-plan: requirement doc missing '## Acceptance Criteria' heading" >&2
  exit 1
fi

# Document-level priority fallback: look for `Priority: Low/Medium/High` or
# `- **Priority**: ...` near the top of the doc, or an `## Priority` section.
_doc_level_priority_raw=$(
  grep -E '^[[:space:]]*(\*\*)?[[:space:]]*Priority(\*\*)?[[:space:]]*:[[:space:]]*' "$REQ_DOC" \
    | head -n 1 \
    | sed -E 's/.*[Pp]riority[^:]*:[[:space:]]*//' \
    || true
)
# Normalize the doc-level priority into a P0/P1/P2 tag.
_normalize_priority() {
  local raw="$1"
  raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  case "$raw" in
    *p0*|*critical*|*high*)  echo "P0" ;;
    *p1*|*medium*)            echo "P1" ;;
    *p2*|*low*)               echo "P2" ;;
    *)                        echo "" ;;
  esac
}
REQ_DOC_PRIORITY=$(_normalize_priority "$_doc_level_priority_raw")

# Walk the requirement doc line by line: when we hit `### FR-N:`, `### NFR-N:`,
# or `### RC-N:`, capture the ID and the first non-empty body line that follows.
# We also scan the `## Acceptance Criteria` section for `- AC-N:` style entries.
# AWK keeps the parsing concise and handles trailing-whitespace edge cases.
_req_parse=$(awk -v default_priority="$REQ_DOC_PRIORITY" '
  BEGIN {
    current_id=""; current_body=""; in_ac=0; in_testing=0;
    testing_mode="unknown";
  }
  function flush_id() {
    if (current_id != "") {
      # Trim leading/trailing whitespace on body.
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", current_body)
      printf "ID\t%s\t%s\n", current_id, current_body
      if (current_priority != "") {
        printf "PRIO\t%s\t%s\n", current_id, current_priority
      } else if (default_priority != "") {
        printf "PRIO\t%s\t%s\n", current_id, default_priority
      }
      current_id=""; current_body=""; current_priority="";
    }
  }
  /^## +Acceptance Criteria/ { flush_id(); in_ac=1; in_testing=0; next }
  /^## +Testing Requirements/ { flush_id(); in_ac=0; in_testing=1; next }
  /^## +[^#]/ {
    # Any other top-level H2 ends both special sections.
    if (in_ac || in_testing) { flush_id(); in_ac=0; in_testing=0 }
  }
  /^### +(FR|NFR|RC)-[0-9]+/ {
    flush_id()
    match($0, /(FR|NFR|RC)-[0-9]+/)
    current_id=substr($0, RSTART, RLENGTH)
    current_body=""
    current_priority=""
    in_ac=0; in_testing=0
    next
  }
  # Capture first non-empty body line after an FR/NFR/RC heading.
  current_id != "" && current_body == "" && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#/ {
    current_body=$0
  }
  # Per-item Priority field: `- Priority: P0` or `- **Priority**: High`.
  current_id != "" && /[Pp]riority[^:]*:/ {
    line=$0
    sub(/.*[Pp]riority[^:]*:[[:space:]]*/, "", line)
    sub(/[[:space:]]+$/, "", line)
    low=tolower(line)
    if (low ~ /p0|critical|high/)      current_priority="P0"
    else if (low ~ /p1|medium/)         current_priority="P1"
    else if (low ~ /p2|low/)            current_priority="P2"
  }
  # Acceptance Criteria entries: `- AC-N: ...` or `- [ ] AC-N: ...`.
  in_ac && /- *(\[[x ]\])?[[:space:]]*AC-[0-9]+/ {
    match($0, /AC-[0-9]+/)
    ac_id=substr($0, RSTART, RLENGTH)
    body=$0
    sub(/.*AC-[0-9]+[[:space:]]*:?[[:space:]]*/, "", body)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", body)
    printf "ID\t%s\t%s\n", ac_id, body
    if (default_priority != "") {
      printf "PRIO\t%s\t%s\n", ac_id, default_priority
    }
  }
  # Testing Requirements body: look for an `executable` / `exploratory` /
  # `manual` keyword. Pick the first hit.
  in_testing {
    low=tolower($0)
    if (testing_mode == "unknown") {
      if (low ~ /executable/)        testing_mode="executable"
      else if (low ~ /exploratory/)  testing_mode="exploratory"
      else if (low ~ /manual/)       testing_mode="manual"
    }
  }
  END {
    flush_id()
    printf "TESTMODE\t%s\n", testing_mode
  }
' "$REQ_DOC")

# Split _req_parse into arrays.
while IFS=$'\t' read -r kind a b; do
  case "$kind" in
    ID)
      REQ_IDS_LIST+="${a}"$'\n'
      REQ_BODIES+="${a}|${b}"$'\n'
      ;;
    PRIO)
      REQ_PRIORITY_PER_ID+="${a}|${b}"$'\n'
      ;;
    TESTMODE)
      REQ_TESTING_MODE="$a"
      ;;
  esac
done <<< "$_req_parse"

# --- Test-plan parsing --------------------------------------------------------
# Two formats to support:
#   Version-2 prose: lines starting with `[P0]`, `[P1]`, or `[P2]`.
#   Legacy table: rows whose cells contain `| RC-N |` / `| AC-N |` markers.
#
# We collect a list of scenario records, each a tab-separated tuple:
#   LINENO \t PRIORITY \t MODE \t FULL_LINE \t REFERENCED_IDS_CSV
# REFERENCED_IDS are extracted from the full scenario body.

PLAN_SCENARIOS=""  # concatenated scenario records, one per line

# Detect legacy format by presence of `| RC-` or `| AC-` column cells in body.
_legacy_signal=$(grep -cE '\|[[:space:]]*(RC|AC)-[0-9]+' "$PLAN_DOC" || true)

_scenario_count=0

# Awk emits scenario records on stdout with fields delimited by a single TAB.
# Empty fields are emitted as the sentinel `-` so bash 3.2's read -r (which
# collapses consecutive IFS whitespace) preserves field boundaries. Downstream
# we translate `-` back to `""`.
_SENTINEL="-"

# Version-2 prose parse.
while IFS= read -r _line_record; do
  [[ -z "$_line_record" ]] && continue
  _scenario_count=$((_scenario_count + 1))
  PLAN_SCENARIOS+="$_line_record"$'\n'
done < <(awk -v S="$_SENTINEL" '
  BEGIN { n=0 }
  /^\[P[012]\]/ {
    n=NR
    line=$0
    # Extract priority.
    match(line, /^\[P[012]\]/)
    prio=substr(line, RSTART+1, RLENGTH-2)
    # Extract mode (first `mode:` value, up to next ` | ` or end of line).
    mode=""
    if (match(line, /mode:[[:space:]]*[^|]+/)) {
      mode=substr(line, RSTART+5, RLENGTH-5)
      sub(/^[[:space:]]+/, "", mode)
      sub(/[[:space:]]+$/, "", mode)
    }
    if (mode == "") mode=S
    # Extract every FR-N / NFR-N / RC-N / AC-N reference from the full body
    # after the priority tag.
    body=line
    sub(/^\[P[012]\][[:space:]]*/, "", body)
    refs=""
    tmp=body
    while (match(tmp, /(FR|NFR|RC|AC)-[0-9]+/)) {
      ref=substr(tmp, RSTART, RLENGTH)
      if (refs == "") refs=ref; else refs=refs "," ref
      tmp=substr(tmp, RSTART+RLENGTH)
    }
    if (refs == "") refs=S
    # Emit record: LINENO \t PRIORITY \t MODE \t FULL_LINE \t REFS
    gsub(/\t/, " ", line)
    printf "%d\t%s\t%s\t%s\t%s\n", n, prio, mode, line, refs
  }
' "$PLAN_DOC")

# Legacy table parse: each row that matches `| RC-N |` or `| AC-N |` becomes a
# scenario record. We treat the whole row as the body; priority is unknown (""),
# mode is unknown (""). References come from every (RC|AC|FR|NFR)-N token in
# the row.
if [[ "$_legacy_signal" -gt 0 ]]; then
  while IFS= read -r _line_record; do
    [[ -z "$_line_record" ]] && continue
    _scenario_count=$((_scenario_count + 1))
    PLAN_SCENARIOS+="$_line_record"$'\n'
  done < <(awk -v S="$_SENTINEL" '
    /\|[[:space:]]*(RC|AC)-[0-9]+/ {
      line=$0
      refs=""
      tmp=line
      while (match(tmp, /(FR|NFR|RC|AC)-[0-9]+/)) {
        ref=substr(tmp, RSTART, RLENGTH)
        if (refs == "") refs=ref; else refs=refs "," ref
        tmp=substr(tmp, RSTART+RLENGTH)
      }
      if (refs == "") refs=S
      gsub(/\t/, " ", line)
      printf "%d\t%s\t%s\t%s\t%s\n", NR, S, S, line, refs
    }
  ' "$PLAN_DOC")
fi

if [[ "$_scenario_count" -eq 0 ]]; then
  echo "[error] reconcile-test-plan: no parseable scenario lines found in test plan" >&2
  exit 1
fi

# --- Bidirectional match ------------------------------------------------------
# Build newline-separated lookup sets (bash 3.2 compatible — no assoc arrays).
#   REQ_IDS_SET            — newline-joined uniq list of requirement-side IDs.
#   PLAN_REFERENCED_SET    — newline-joined uniq list of IDs referenced by any
#                            scenario.
# `set_has ID $SET` returns 0 when ID is a member, 1 otherwise.

REQ_IDS_SET=$(printf '%s' "$REQ_IDS_LIST" | awk 'NF' | awk '!seen[$0]++')

# _unescape_fields translates sentinel `-` back to empty string.
_unseed() {
  [[ "$1" == "$_SENTINEL" ]] && printf '' || printf '%s' "$1"
}

# Parse a scenario record ("LINENO\tPRIO\tMODE\tBODY\tREFS") into the five
# variables _lineno / _prio / _mode / _body / _refs. Uses awk to robustly split
# on tab boundaries (bash 3.2's `read` collapses consecutive IFS whitespace).
_parse_rec() {
  local rec="$1"
  _lineno=$(printf '%s' "$rec" | awk -F'\t' '{print $1}')
  _prio=$(printf '%s'   "$rec" | awk -F'\t' '{print $2}')
  _mode=$(printf '%s'   "$rec" | awk -F'\t' '{print $3}')
  _body=$(printf '%s'   "$rec" | awk -F'\t' '{print $4}')
  _refs=$(printf '%s'   "$rec" | awk -F'\t' '{print $5}')
  _prio=$(_unseed "$_prio")
  _mode=$(_unseed "$_mode")
  _body=$(_unseed "$_body")
  _refs=$(_unseed "$_refs")
}

PLAN_REFERENCED_SET=""
while IFS= read -r _rec; do
  [[ -z "$_rec" ]] && continue
  _parse_rec "$_rec"
  if [[ -n "$_refs" ]]; then
    IFS=',' read -ra _ref_arr <<< "$_refs"
    for _r in "${_ref_arr[@]}"; do
      [[ -z "$_r" ]] && continue
      PLAN_REFERENCED_SET+="${_r}"$'\n'
    done
  fi
done <<< "$PLAN_SCENARIOS"
PLAN_REFERENCED_SET=$(printf '%s' "$PLAN_REFERENCED_SET" | awk 'NF' | awk '!seen[$0]++')

set_has() {
  # $1 = needle, $2 = set var content (newline-separated)
  local needle="$1" set="$2"
  # Use grep -Fx for exact-line match; absorb zero-match rc under set -e.
  printf '%s\n' "$set" | grep -Fxq -- "$needle"
}

# --- Buckets ------------------------------------------------------------------
# Lines: id|location|detail
GAPS_LINES=""
CONTRADICTIONS_LINES=""
SURPLUS_LINES=""
DRIFT_LINES=""
MODE_MISMATCH_LINES=""

append_line() {
  local var="$1" id="$2" loc="$3" detail="$4"
  # Replace any literal `|` in detail with an ASCII substitute so the three
  # pipe-separated fields (id|location|detail) don't collide. Uses the
  # Unicode-equivalent broken-bar glyph so human readers see something
  # reasonable and the JSON is still valid UTF-8.
  detail=$(printf '%s' "$detail" | tr '|' '/')
  local line="${id}|${loc}|${detail}"
  printf -v "$var" '%s%s\n' "${!var}" "$line"
}

# R1: gaps — req-side IDs with no test-plan reference.
while IFS= read -r _rid; do
  [[ -z "$_rid" ]] && continue
  if ! set_has "$_rid" "$PLAN_REFERENCED_SET"; then
    append_line GAPS_LINES "$_rid" "req-doc" "no test-plan scenario references ${_rid}"
  fi
done <<< "$REQ_IDS_SET"

# R3 (surplus), R4 (drift), R5 (modeMismatch), R2 (contradictions): scenario loop.
lookup_req_body() {
  local id="$1"
  while IFS= read -r _rec; do
    [[ -z "$_rec" ]] && continue
    local rid="${_rec%%|*}"
    if [[ "$rid" == "$id" ]]; then
      printf '%s' "${_rec#*|}"
      return 0
    fi
  done <<< "$REQ_BODIES"
  return 1
}

lookup_req_priority() {
  local id="$1"
  while IFS= read -r _rec; do
    [[ -z "$_rec" ]] && continue
    local rid="${_rec%%|*}"
    if [[ "$rid" == "$id" ]]; then
      printf '%s' "${_rec#*|}"
      return 0
    fi
  done <<< "$REQ_PRIORITY_PER_ID"
  return 1
}

while IFS= read -r _rec; do
  [[ -z "$_rec" ]] && continue
  _parse_rec "$_rec"

  if [[ -z "$_refs" ]]; then
    # R3 surplus: no requirement IDs referenced.
    local_snippet="${_body:0:120}"
    append_line SURPLUS_LINES "-" "test-plan:${_lineno}" "scenario references no requirement ID: ${local_snippet}"
    continue
  fi

  IFS=',' read -ra _ref_arr <<< "$_refs"
  scenario_has_known_ref=0
  for _r in "${_ref_arr[@]}"; do
    [[ -z "$_r" ]] && continue
    if set_has "$_r" "$REQ_IDS_SET"; then
      scenario_has_known_ref=1
      # R4 drift: scenario priority vs requirement priority.
      req_prio=$(lookup_req_priority "$_r" || true)
      if [[ -n "$_prio" && -n "$req_prio" && "$_prio" != "$req_prio" ]]; then
        append_line DRIFT_LINES "$_r" "test-plan:${_lineno}" "scenario priority ${_prio} disagrees with requirement priority ${req_prio}"
      fi
      # R2 contradictions: does `expected:` phrase contain a word that
      # appears to disagree with the requirement body?
      # We surface a mismatch whenever the `expected:` slice exists AND
      # the requirement body exists AND they share no 4+ letter word.
      req_body=$(lookup_req_body "$_r" || true)
      if [[ -n "$req_body" && "$_body" == *expected:* ]]; then
        expected_slice="${_body#*expected:}"
        expected_slice="${expected_slice%%|*}"
        # Trim.
        expected_slice=$(printf '%s' "$expected_slice" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
        # Shared 4+ letter word check (case-insensitive).
        expected_lc=$(printf '%s' "$expected_slice" | tr '[:upper:]' '[:lower:]')
        req_lc=$(printf '%s' "$req_body" | tr '[:upper:]' '[:lower:]')
        shared=0
        for w in $(printf '%s\n' "$expected_lc" | tr -cs '[:alpha:]' ' '); do
          [[ ${#w} -lt 4 ]] && continue
          if [[ "$req_lc" == *"$w"* ]]; then
            shared=1
            break
          fi
        done
        if [[ "$shared" -eq 0 && -n "$expected_slice" ]]; then
          append_line CONTRADICTIONS_LINES "$_r" "test-plan:${_lineno}" "scenario expected '${expected_slice}' shares no substantive word with requirement body"
        fi
      fi
      # R5 modeMismatch: scenario mode vs Testing Requirements guidance.
      if [[ -n "$_mode" && "$REQ_TESTING_MODE" != "unknown" ]]; then
        mode_lc=$(printf '%s' "$_mode" | tr '[:upper:]' '[:lower:]')
        if [[ "$mode_lc" != *"$REQ_TESTING_MODE"* ]]; then
          append_line MODE_MISMATCH_LINES "$_r" "test-plan:${_lineno}" "scenario mode '${_mode}' disagrees with Testing Requirements (${REQ_TESTING_MODE})"
        fi
      fi
    fi
  done
  if [[ "$scenario_has_known_ref" -eq 0 ]]; then
    local_snippet="${_body:0:120}"
    append_line SURPLUS_LINES "-" "test-plan:${_lineno}" "scenario references no known requirement ID: ${local_snippet}"
  fi
done <<< "$PLAN_SCENARIOS"

# --- JSON assembly ------------------------------------------------------------

emit_entries_array() {
  if [[ "$HAS_JQ" -eq 1 ]]; then
    jq -Rs '
      split("\n")
      | map(select(length > 0))
      | map(
          (split("|")) as $parts
          | {id: ($parts[0] // ""),
             location: ($parts[1] // ""),
             detail: ($parts[2] // "")}
        )
    '
  else
    local first=1
    printf '['
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local id loc detail rest
      id="${line%%|*}"
      rest="${line#*|}"
      loc="${rest%%|*}"
      if [[ "$rest" == *"|"* ]]; then
        detail="${rest#*|}"
      else
        detail=""
      fi
      if [[ "$first" -eq 1 ]]; then first=0; else printf ','; fi
      local esc
      esc="${detail//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      esc="${esc//$'\t'/\\t}"
      esc="${esc//$'\r'/\\r}"
      esc="${esc//$'\n'/\\n}"
      printf '{"id":"%s","location":"%s","detail":"%s"}' "$id" "$loc" "$esc"
    done
    printf ']'
  fi
}

arr_gaps=$(printf '%s' "$GAPS_LINES" | emit_entries_array)
arr_contr=$(printf '%s' "$CONTRADICTIONS_LINES" | emit_entries_array)
arr_surplus=$(printf '%s' "$SURPLUS_LINES" | emit_entries_array)
arr_drift=$(printf '%s' "$DRIFT_LINES" | emit_entries_array)
arr_mode=$(printf '%s' "$MODE_MISMATCH_LINES" | emit_entries_array)

if [[ "$HAS_JQ" -eq 1 ]]; then
  jq -cn \
    --argjson gaps "$arr_gaps" \
    --argjson contr "$arr_contr" \
    --argjson surplus "$arr_surplus" \
    --argjson drift "$arr_drift" \
    --argjson mode "$arr_mode" \
    '{gaps: $gaps, contradictions: $contr, surplus: $surplus, drift: $drift, modeMismatch: $mode}'
else
  printf '{"gaps":%s,"contradictions":%s,"surplus":%s,"drift":%s,"modeMismatch":%s}\n' \
    "$arr_gaps" "$arr_contr" "$arr_surplus" "$arr_drift" "$arr_mode"
fi
